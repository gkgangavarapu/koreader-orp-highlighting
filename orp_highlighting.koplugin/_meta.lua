--[[--
ORP Highlighting plugin metadata.

@module koplugin.ORPHighlighting._meta
--]]--

local _ = require("gettext")
return {
    fullname = _("ORP Highlighting"),
    description = _([[
Highlights the Optimal Recognition Point (ORP) character of every word on the
manually-read page with a distinct visual style. The page remains a normal,
paged, non-RSVP reading view.
]]),
}
