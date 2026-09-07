--[[--
ORP Highlighting plugin.

Toggles a mode where the Optimal Recognition Point (ORP) character of every word
on the normal, manually-read, paged view is visually distinguished.

This is a *reader* plugin (is_doc_only = true). ReaderUI instantiates it and calls
init() with self.ui / self.view / self.document set, exactly like other doc plugins.

Phases implemented here:
  Phase 1  plugin skeleton + persistent ON/OFF toggle + reader gear-menu submenu.
  Phase 2  the pure ORP algorithm lives in orp.lua (independently testable).
  Phase 4  "Run ORP diagnostic on current page": prints  word | ORP  for the page.
           No visual change. This path uses only the *text* APIs, so it works
           without any core change.
  Phase 5  precise single-glyph styling. The body of a CRE page is rasterized by
           CREngine in C++, so per-glyph rects are not exposed by the stock Lua
           API. This plugin therefore *looks* for an (additive, reversible)
            crengine export, document:orpVisibleWords(), provided by the separate
            patch in crengine-patch/. When present it paints an overlay; when absent
            it reports the boundary instead of silently degrading or rewriting the
            EPUB / RSVP / etc.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local orp = require("orp")

-- CREngine reports a word that is split across a line-break hyphen as two visual
-- "words" (e.g. "recogni-" + "tion"). Rejoin such fragments so ORP is computed on
-- the whole logical word. A fragment is a continuation only if it follows a
-- trailing break-hyphen and begins with a lowercase letter (a new sentence/word
-- wouldn't). Layout/punctuation of genuine compounds (e.g. "well-known") that sit
-- on one line are a single word from crengine and are untouched.
local function rejoinHyphenated(words)
    local out = {}
    local i = 1
    while i <= #words do
        local cur = words[i]
        local cont = true
        while cont do
            local last = cur.text:sub(-1)
            if (last == "-" or last == "\u{2010}") and i < #words then
                local nxt = words[i + 1]
                local first = nxt.text:sub(1, 1)
                if nxt.chars and cur.chars
                        and first == first:lower() and first:match("%a") then
                    i = i + 1
                    cur.text = cur.text:sub(1, -2) .. nxt.text
                    for _, c in ipairs(nxt.chars) do
                        cur.chars[#cur.chars + 1] = c
                    end
                else
                    cont = false
                end
            else
                cont = false
            end
        end
        out[#out + 1] = cur
        i = i + 1
    end
    return out
end

local ORPHighlighting = WidgetContainer:extend{
    name = "orp_highlighting",
    is_doc_only = true,
    -- Keys managed in G_reader_settings (global KOReader settings), so the
    -- toggle survives across sessions and books.
    settings_key = "orp_highlighting",
    key_enabled = "orp_highlighting_enabled",
    key_style = "orp_highlighting_style",

    -- The visual styles the ORP glyph can take. Underline/inverse are drawn as an
    -- overlay by paintTo(); "bold" is emboldened by CREngine at page render time
    -- via document:setOrpBoldRects (drawCurrentPage thickens the glyph).
    STYLES = {
        { id = "underline", text = _("Underline") },
        { id = "inverse",   text = _("Inverse") },
        { id = "bold",      text = _("Bold") },
    },

    is_enabled = false,
    style = "underline",
    orp_targets = nil,      -- array of { x, y, w, h } overlay rects (page coords)
    doc_is_cre = false,
    patch_available = false,
    warned_no_patch = false,
}

function ORPHighlighting:init()
    self.is_enabled = G_reader_settings:isTrue(self.key_enabled)
    self.style = G_reader_settings:readSetting(self.key_style, "underline")
    if not self:_isValidStyle(self.style) then
        self.style = "underline"
    end
    self.doc_is_cre = self:_isCre()
    self:registerToMainMenu()
    if self.view and self.view.registerViewModule then
        -- So ReaderView calls our paintTo() overlay on top of the page.
        self.view:registerViewModule(self.name, self)
    end
end

-- True when the current document is in reflowable (CREngine) mode.
-- This mirrors KOReader's own rule (ReaderUI uses the "cre" branch when the
-- document has no fixed pages and exposes CRE text APIs), rather than checking
-- a provider string that isn't reliably present on `document.info`.
function ORPHighlighting:_isCre(doc)
    doc = doc or self.ui.document
    return doc ~= nil
        and doc.info ~= nil
        and doc.info.has_pages == false
        and type(doc.getTextFromPositions) == "function"
end

function ORPHighlighting:_isValidStyle(id)
    for _, s in ipairs(self.STYLES) do
        if s.id == id then return true end
    end
    return false
end

function ORPHighlighting:_save()
    G_reader_settings:saveSetting(self.key_enabled, self.is_enabled)
    G_reader_settings:saveSetting(self.key_style, self.style)
end

function ORPHighlighting:deletePluginSettings()
    G_reader_settings:delSetting(self.key_enabled)
    G_reader_settings:delSetting(self.key_style)
end

function ORPHighlighting:registerToMainMenu()
    if self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function ORPHighlighting:addToMainMenu(menu_items)
    local style_items = {}
    for _, s in ipairs(self.STYLES) do
        style_items[#style_items + 1] = {
            text = s.text,
            checked_func = function() return self.style == s.id end,
            callback = function()
                self.style = s.id
                self:_save()
                self:refresh()
                return true
            end,
        }
    end

    menu_items.orp_highlighting = {
        text = _("ORP Highlighting"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("ORP Highlighting"),
                checked_func = function() return self.is_enabled end,
                callback = function()
                    self.is_enabled = not self.is_enabled
                    self:_save()
                    self:refresh()
                    if self.is_enabled then
                        self:_reportCapability()
                    end
                    return true
                end,
            },
            {
                text = _("Style"),
                keep_menu_open = true,
                sub_item_table = style_items,
            },
            {
                text = _("Run ORP diagnostic on current page"),
                keep_menu_open = true,
                callback = function()
                    self:showDiagnostic()
                end,
            },
            {
                text = _("About"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _([[
Highlights the Optimal Recognition Point (ORP) of each word.
Uses 1-2→1, 3-5→2, 6-9→3, 10+→4 letters by default.

The page stays a normal, paged, non-RSVP reading view.
Precise single-glyph styling requires the reversible crengine
glyph export patch (see crengine-patch/). The diagnostic works
without it.
]]),
                    })
                end,
            },
        },
    }
end

-- Capability boundary report (Phase 3 / Phase 5 constraint).
function ORPHighlighting:_reportCapability()
    if not self.doc_is_cre then
        UIManager:show(InfoMessage:new{
            text = _("ORP Highlighting only applies to reflowable (CREngine) documents."),
        })
        return
    end
    self.patch_available = self:_probeGlyphPatch()
    if not self.patch_available then
        UIManager:show(InfoMessage:new{
            text = _([[ORP Highlighting is ON, but precise per-glyph styling needs the
crengine glyph export patch (additive & reversible, see crengine-patch/).
Without it the Lua API only exposes a rasterized page: individual glyphs
cannot be restyled after layout.

The "Run ORP diagnostic" item and the pure orp.lua algorithm still work.
]]),
        })
    end
end

function ORPHighlighting:_probeGlyphPatch()
    local doc = self.ui.document
    if not doc then return false end
    local ok = pcall(function()
        local res = doc:orpVisibleWords()
        if type(res) ~= "table" then error("unexpected") end
    end)
    return ok
end

-- Toggle / style changed: recompute overlay for the current page and repaint.
function ORPHighlighting:refresh()
    if self.is_enabled and self.doc_is_cre then
        if self:_probeGlyphPatch() then
            self.orp_targets = self:_computeTargets()
        else
            self.orp_targets = nil
        end
    else
        self.orp_targets = nil
    end
    self:_syncBoldTargets()
    if self.view and self.view.dimen then
        UIManager:setDirty(self.view, "partial")
    end
end

-- Whenever a new page is shown, recompute the ORP overlay targets (page coords).
function ORPHighlighting:onPageUpdate()
    if self.is_enabled and self.doc_is_cre then
        if self.patch_available or self:_probeGlyphPatch() then
            self.orp_targets = self:_computeTargets()
        elseif not self.warned_no_patch then
            self.warned_no_patch = true
            self.orp_targets = nil
        end
    else
        self.orp_targets = nil
    end
    self:_syncBoldTargets()
    -- returning nil lets the default handler run (page drawing proceeds normally)
end

-- When style == "bold", hand the ORP rectangles to the engine (drawCurrentPage
-- emboldens them at page-render time). For every other style we clear them and
-- let paintTo() draw the overlay instead.
function ORPHighlighting:_syncBoldTargets()
    local doc = self.ui.document
    if not doc or not doc.setOrpBoldRects then return end
    if self.is_enabled and self.doc_is_cre and self.style == "bold" and self.orp_targets then
        local rects = {}
        for i, r in ipairs(self.orp_targets) do
            rects[i] = { x0 = r.x, y0 = r.y, x1 = r.x + r.w, y1 = r.y + r.h }
        end
        pcall(doc.setOrpBoldRects, doc, rects)
    else
        pcall(doc.setOrpBoldRects, doc, {})
    end
end

-- Core-glyph-patch interface (document:orpVisibleWords, additive read-only):
--   returns array of words on the current page, each
--   { text = <word text>, chars = { {char=, x0,y0,x1,y1}, ... } }
--   with char rects in page coordinates. Absent on stock KOReader.
function ORPHighlighting:_computeTargets()
    local doc = self.ui.document
    if not doc or not doc.orpVisibleWords then return nil end
    local ok, words = pcall(doc.orpVisibleWords, doc)
    if not ok or type(words) ~= "table" then return nil end
    words = rejoinHyphenated(words)

    local targets = {}
    for _, w in ipairs(words) do
        local a = orp.analyse(w.text or "")
        if a.orp then -- has at least one letter
            local want = a.target_n
            local seen = 0
            for _, c in ipairs(w.chars) do
                if c and c.char and orp.charIsLetter(c.char) then
                    seen = seen + 1
                    if seen == want then
                        targets[#targets + 1] = {
                            x = c.x0, y = c.y0,
                            w = c.x1 - c.x0, h = c.y1 - c.y0,
                        }
                        break
                    end
                end
            end
        end
    end

    return targets
end

-- Overlay painter, invoked by ReaderView on top of the page.
function ORPHighlighting:paintTo(bb, x, y)
    if not self.is_enabled or not self.orp_targets then return end
    if self.style == "bold" then
        -- Bold is done by CREngine at render time (see _syncBoldTargets), not here.
        return
    end
    for _, r in ipairs(self.orp_targets) do
        local rx = x + r.x
        local ry = y + r.y
        local rw, rh = r.w, r.h
        if self.style == "inverse" then
            bb:invertRect(rx, ry, rw, rh)
        elseif self.style == "underline" then
            local thick = math.max(1, math.floor(rh * 0.12))
            bb:paintRect(rx, ry + rh - thick, rw, thick, Blitbuffer.COLOR_BLACK)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Phase 4 diagnostic: word | ORP  for the current CRE page (text-only).
-- ---------------------------------------------------------------------------
function ORPHighlighting:_pageTextOrpList()
    local doc = self.ui.document
    if not doc then return nil, "no document" end
    if not self:_isCre(doc) then return nil, "not a reflowable (CREngine) document" end

    local word_count = 0
    local rows = {}
    local function add_word(w)
        word_count = word_count + 1
        local a = orp.analyse(w)
        local orp_char = a.orp and a.orp.ch or "-"
        rows[#rows + 1] = { word = w, letters = a.letter_count, orp_char = orp_char }
    end

    if doc.orpVisibleWords then
        -- Preferred: exact per-word visible content from the (optional) core patch.
        local ok, words = pcall(doc.orpVisibleWords, doc)
        if ok and type(words) == "table" then
            for _, w in ipairs(words) do
                if w.text and w.text ~= "" then
                    add_word(w.text)
                end
            end
            return rows, nil, word_count
        end
    end

    -- Stock path: pull the visible text directly from the current page.
    local top_y, content_h, left, width, header, margins
    local ok = pcall(function()
        header = doc:getHeaderHeight() or 0
        margins = doc:getPageMargins() or {}
        top_y = doc:getCurrentPos() or 0
        local screen_h = self.ui.dimen and self.ui.dimen.h or 0
        content_h = math.max(1, screen_h - header - (margins.top or 0) - (margins.bottom or 0))
        left = margins.left or 0
        local screen_w = self.ui.dimen and self.ui.dimen.w or 0
        width = screen_w - left - (margins.right or 0)
    end)
    if not ok then return nil, "could not read page geometry" end

    local tr = doc:getTextFromPositions(
        { x = left, y = top_y + (margins.top or 0) + header },
        { x = left + width, y = top_y + content_h + (margins.top or 0) + header },
        true) -- do_not_draw_selection

    local text = tr and (tr.text or "") or ""
    if text == "" then
        return nil, "no text extracted from current page"
    end
    for _, w in ipairs(orp.splitWords(text)) do
        add_word(w)
    end
    return rows, nil, word_count
end

function ORPHighlighting:showDiagnostic()
    local doc = self.ui.document
    if not doc then return end
    if not self:_isCre(doc) then
        UIManager:show(InfoMessage:new{
            text = _([[
This book is not in reflowable (CREngine) mode, so its laid-out text can't be
read for a diagnostic.

Reflowable books work: EPUB, TXT, FB2, HTML.
Fixed-layout books do not: PDF, DJVU, CBZ, scans.
]]),
        })
        return
    end

    local rows, err = self:_pageTextOrpList()
    if not rows then
        UIManager:show(InfoMessage:new{ text = "Diagnostic: " .. tostring(err) })
        logger.warn("orp_highlighting diagnostic error:", err)
        return
    end

    -- Column widths: size the word column to the longest word and keep the
    -- others fixed, then build EVERY line (header included) with the same
    -- string.format, so nothing overflows and the columns stay aligned.
    local col_word, col_orp = 4, 3
    for _, r in ipairs(rows) do
        if #r.word > col_word then col_word = #r.word end
        if #r.orp_char > col_orp then col_orp = #r.orp_char end
    end
    local fmt = string.format("%%-%ds  %%-8s  %%-%ds", col_word, col_orp)
    local lines = { string.format(fmt, "word", "letters", "ORP") }
    for _, r in ipairs(rows) do
        lines[#lines + 1] = string.format(fmt, r.word, r.letters, r.orp_char)
    end
    local body = table.concat(lines, "\n")
    logger.info("ORP diagnostic:\n" .. body)
    UIManager:show(InfoMessage:new{
        text = body,
        monospace_font = true, -- keep the columns aligned
    })
end

-- Drop overlay when leaving the document.
function ORPHighlighting:onCloseDocument()
    self.orp_targets = nil
    local doc = self.ui.document
    if doc and doc.setOrpBoldRects then
        pcall(doc.setOrpBoldRects, doc, {})
    end
end

return ORPHighlighting
