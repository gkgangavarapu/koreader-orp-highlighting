--[[--
ORP (Optimal Recognition Point) core.

Pure, dependency-free Lua (Lua 5.1+). Safe to run outside KOReader for unit tests.

The only thing it needs to know about a "word" is its text; it never touches the
document, layout or rendering. It:
  * iterates UTF-8 by codepoint (never counts bytes as characters),
  * identifies the letters within a token (ignoring punctuation, apostrophes,
    hyphens, combining diacritics, whitespace, digits and symbol codepoints),
  * decides which-th letter is the Optimal Recognition Point from a rule table,
  * and reports where that letter sits in the ORIGINAL token string, so a caller
    can later locate/highlight it without ambiguity.

Rule table (default, configurable):
    letter count   ORP
    1-2            letter 1
    3-5            letter 2
    6-9            letter 3
    10+            letter 4

@module orp
--]]--

local orp = {}

-- Codepoint ranges that are NOT letters for the purpose of counting ORP length.
-- This includes ASCII + common punctuation, apostrophes/quotes, hyphens/dashes,
-- general punctuation & symbol blocks, digits, whitespace/controls, and combining
-- diacritics / variation selectors (so an accented composed letter counts once,
-- and a decomposed letter + combining mark also counts once).
local NON_LETTER = {
    -- controls / whitespace
    { 0x00, 0x2F },     -- 0x00-0x2F : C0 controls, space .. '/' (ASCII punctuation)
    { 0x3A, 0x40 },     -- ':' .. '@'
    { 0x5B, 0x60 },     -- '[' .. '`'
    { 0x7B, 0xA0 },     -- '{' .. 0xA0 (incl. DEL, C1 controls, NBSP)
    -- common typographic punctuation
    { 0x2010, 0x206F }, -- hyphens/dashes .. general punctuation incl. soft/zero-width
    -- Latin-1 maths / misc symbols that could otherwise be miscounted as letters
    { 0x2100, 0x214F }, -- letterlike symbols
    { 0x2190, 0x22FF }, -- arrows, mathematical operators
    { 0x25A0, 0x27BF }, -- geometric shapes, dingbats
    { 0x2600, 0x26FF }, -- miscellaneous symbols (weather, chess, etc.)
    { 0x2E00, 0x2E7F }, -- supplemental punctuation
    { 0xFE50, 0xFE6F }, -- small form variants (punctuation)
    { 0xFF00, 0xFF0F }, -- fullwidth forms punctuation
    { 0xFFE0, 0xFFEF }, -- fullwidth symbols
    -- emoji / pictographs
    { 0x1F000, 0x1FAFF },
    -- combining diacritical marks + modifiers + variation selectors.
    -- (These are marks: they modify the preceding letter and add no length.)
    { 0x0300, 0x036F }, -- combining diacriticals
    { 0x0483, 0x0489 }, -- cyrillic combining
    { 0x0591, 0x05C7 }, -- hebrew points/cantillation
    { 0x0610, 0x061A }, -- arabic sign
    { 0x064B, 0x065F }, -- arabic combining
    { 0x0670, 0x0670 },
    { 0x06D6, 0x06DC },
    { 0x06DF, 0x06E4 },
    { 0x06E7, 0x06E8 },
    { 0x06EA, 0x06ED },
    { 0x0711, 0x0711 },
    { 0x0730, 0x074A }, -- syriac combining
    { 0x07A6, 0x07B0 },
    { 0x07EB, 0x07F3 }, -- nko combining
    { 0x0816, 0x082D }, -- samaritan combining
    { 0x0859, 0x085B },
    { 0x08E3, 0x0902 },
    { 0x093C, 0x093C }, -- devanagari sign nukta
    { 0x0941, 0x0948 }, -- devanagari vowels
    { 0x094D, 0x094D }, -- devanagari virama
    { 0x0951, 0x0957 }, -- devanagari extended accents
    { 0x0962, 0x0963 },
    { 0x0E31, 0x0E31 }, -- thai
    { 0x0E34, 0x0E3A },
    { 0x0E47, 0x0E4E },
    { 0x0EB1, 0x0EB1 }, -- lao
    { 0x0EB4, 0x0EBC },
    { 0x0EC8, 0x0ECD },
    { 0x0F71, 0x0F84 }, -- tibetan
    { 0x0F86, 0x0F87 },
    { 0x1AB0, 0x1AFF }, -- combining diacritical extended
    { 0x1DC0, 0x1DFF }, -- combining supplementary
    { 0x20D0, 0x20FF }, -- combining marks for symbols
    { 0xFE20, 0xFE2F }, -- combining half marks
    { 0xFE00, 0xFE0F }, -- variation selectors
}

local function cpIsLetter(cp)
    if cp >= 0x80 then
        for i = 1, #NON_LETTER do
            local r = NON_LETTER[i]
            if cp < r[1] then
                break -- table is ascending; no need to scan further
            elseif cp <= r[2] then
                return false
            end
        end
        return true
    else
        -- ASCII fast path: letter iff A-Z / a-z
        return (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
    end
end

-- Sort NON_LETTER ascending (defensive; author keeps it sorted but be safe).
table.sort(NON_LETTER, function(a, b) return a[1] < b[1] end)

-- Codepoints that glue to a word while not being letters themselves:
-- apostrophes/quotes, hyphens/dashes, and combining marks (kept attached so an
-- accented letter or a contracted/hyphenated word stays one token).
local GLUE = {
    { 0x27, 0x27 },       -- '
    { 0x2D, 0x2D },       -- -
    { 0x00AD, 0x00AD },   -- soft hyphen
    { 0x02BC, 0x02BC },   -- modifier apostrophe
    { 0x2010, 0x2015 },   -- hyphen / dash family
    { 0x2018, 0x2019 },   -- ' ' quotes (apostrophes)
    -- combining marks (same ranges as NON_LETTER) so decomposition stays attached
    { 0x0300, 0x036F },
    { 0x0483, 0x0489 },
    { 0x1AB0, 0x1AFF },
    { 0x1DC0, 0x1DFF },
    { 0x20D0, 0x20FF },
    { 0xFE20, 0xFE2F },
    { 0xFE00, 0xFE0F },
}

-- Sort ascending (cpIsGlue early-exits on the first lo > cp).
table.sort(GLUE, function(a, b) return a[1] < b[1] end)

local function cpIsGlue(cp)
    for i = 1, #GLUE do
        local r = GLUE[i]
        if cp < r[1] then
            break
        elseif cp <= r[2] then
            return true
        end
    end
    return false
end


-- Default ORP rules: list of { up_to = <letter count>, target = <which-th letter> }.
-- Entries must be ascending by up_to; the final entry may have up_to = nil ("rest").
local DEFAULT_RULES = {
    { up_to = 2, target = 1 },
    { up_to = 5, target = 2 },
    { up_to = 9, target = 3 },
    { up_to = nil, target = 4 }, -- 10+ letters
}

orp.rules = DEFAULT_RULES

-- Decodes one UTF-8 codepoint starting at byte i of s.
-- Returns: byte_start, byte_len, codepoint (or nil at end of string).
local function decodeAt(s, i)
    local b1 = s:byte(i)
    if not b1 then return nil end
    if b1 < 0x80 then
        return i, 1, b1
    end
    local n
    if b1 >= 0xF0 then n = 4
    elseif b1 >= 0xE0 then n = 3
    elseif b1 >= 0xC0 then n = 2
    else
        -- stray continuation / invalid lead byte: treat as a single opaque char
        return i, 1, b1
    end
    local cp = b1 - (n == 2 and 0xC0 or n == 3 and 0xE0 or 0xF0)
    -- validate continuation bytes, fail-safe to a single opaque byte
    for j = 1, n - 1 do
        local b = s:byte(i + j)
        if not b or (b < 0x80 or b > 0xBF) then
            return i, 1, b1
        end
        cp = cp * 0x40 + (b - 0x80)
    end
    return i, n, cp
end

--- Override the ORP rule table.
-- @param rules table of { up_to = number|nil, target = number } ascending by up_to.
function orp.setRules(rules)
    orp.rules = rules or DEFAULT_RULES
end

--- Determine which-th letter is the ORP for a given letter count.
function orp.targetForLetterCount(letter_count)
    if letter_count < 1 then return nil end
    for i = 1, #orp.rules do
        local r = orp.rules[i]
        if not r.up_to or letter_count <= r.up_to then
            return r.target
        end
    end
    return 1
end

--- Analyse a single token (a "word" as delivered by the caller).
-- Returns a table:
--   {
--     token       = original string,
--     letters     = { {ch=, cp=, index=, byte=}, ... }  -- every letter, index = which-th letter (1-based)
--     letter_count= number of letters,
--     target_n    = which-th letter is ORP (nil when there are no letters),
--     orp         = {ch=, cp=, index=, byte=, n=}       -- the ORP letter (or nil),
--   }
-- where `index` is the 1-based position counting ALL codepoints in the original
-- token (so it can be used to slice the original string), and `byte` is the
-- 1-based byte offset of that letter in the UTF-8 token.
function orp.analyse(token)
    local letters = {}
    local total_chars = 0
    local i = 1
    local len = #token
    while i <= len do
        local start, n, cp = decodeAt(token, i)
        total_chars = total_chars + 1
        if cpIsLetter(cp) then
            letters[#letters + 1] = {
                ch = token:sub(start, start + n - 1),
                cp = cp,
                index = total_chars,
                byte = start,
                n = #letters + 1,
            }
        end
        i = start + n
    end

    local letter_count = #letters
    local target_n = orp.targetForLetterCount(letter_count)
    local orp_letter = target_n and letters[target_n] or nil

    return {
        token = token,
        letters = letters,
        letter_count = letter_count,
        target_n = target_n,
        orp = orp_letter,
    }
end

--- Convenience: return the ORP character as a string (or nil).
function orp.character(token)
    local a = orp.analyse(token)
    return a.orp and a.orp.ch or nil
end

--- Convenience: return the 1-based index of the ORP char within the original token.
function orp.index(token)
    local a = orp.analyse(token)
    return a.orp and a.orp.index or nil
end

--- True when a codepoint is a letter. Exposed for callers (e.g. tokenizers).
function orp.isLetter(cp)
    return cpIsLetter(cp)
end

--- True when a codepoint may appear *inside* a word token (letter, apostrophe,
-- hyphen or combining mark). Exposed for callers that group glyphs into words.
function orp.isWordChar(cp)
    return cpIsLetter(cp) or cpIsGlue(cp)
end

--- Variants taking a single UTF-8 character string (used when iterating glyphs).
function orp.charIsLetter(s)
    if s == "" then return false end
    local _, _, cp = decodeAt(s, 1)
    return cpIsLetter(cp)
end

function orp.charIsWordChar(s)
    if s == "" then return false end
    local _, _, cp = decodeAt(s, 1)
    return cpIsGlue(cp) or cpIsLetter(cp)
end

--- Split a text blob into word tokens, keeping apostrophes/hyphens/accents inside
-- each word and trimming surrounding punctuation. Returns an array of strings.
function orp.splitWords(text)
    local words = {}
    local len = #text
    local i = 1
    local cur_start
    while i <= len do
        local start, n, cp = decodeAt(text, i)
        if cpIsLetter(cp) then
            if not cur_start then
                cur_start = start
            end
        else
            if cur_start and cpIsGlue(cp) then
                -- glue char continues the current word
            else
                if cur_start then
                    words[#words + 1] = text:sub(cur_start, start - 1)
                    cur_start = nil
                end
            end
        end
        i = start + n
    end
    if cur_start then
        words[#words + 1] = text:sub(cur_start)
    end
    return words
end

return orp
