--[[--
Standalone offline test for orp.lua. No KOReader required; run with any
Lua >= 5.1 interpreter:

    lua test_orp.lua            (or: luajit test_orp.lua)

Prints a table of word -> ORP character for the requested test text and
asserts the expected positions.
--]]--

package.path = "./orp_highlighting.koplugin/?.lua;" .. package.path
local orp = require("orp")

local tests = {
    -- { word, expected_orp_char }
    { "I",              "I" },
    { "am",             "a" },
    { "the",            "h" },   -- 3 letters (3-5) -> ORP letter 2 = 'h'
    { "quick",          "u" },
    { "brown",          "r" },
    { "beautiful",      "a" },   -- 9 letters (6-9) -> ORP letter 3 = 'a'
    { "recognition",    "o" },   -- 11 letters (10+) -> ORP letter 4 = 'o'
    { "characterization", "r" }, -- 16 letters (10+) -> ORP letter 4 = 'r'
    -- punctuation / apostrophes / hyphens must not be counted
    { "don't",          "o" },   -- 4 letters -> ORP letter 2 = 'o'
    { "well-known",     "l" },   -- 9 letters -> ORP letter 3 = 'l'
    { "can't",          "a" },   -- 4 letters -> ORP letter 2 = 'a'
    -- accented / unicode letters (each composed letter counts once)
    { "café",           "a" },   -- 4 letters c,a,f,é -> letter 2 = 'a'
    { "naïve",          "a" },   -- 5 letters -> letter 2 = 'a'
    -- hyphen handled, apostrophe ignored, trailing punctuation dropped at call site
}

local expected = {}
for _, t in ipairs(tests) do
    expected[t[1]] = t[2]
end

local fail = 0
print(string.format("%-22s %-5s %-8s %-8s %s", "word", "letters", "ORP#", "ORP", "expected"))
print(string.rep("-", 60))
for _, word in ipairs({
    "I","am","the","quick","brown","beautiful","recognition","characterization",
    "don't","well-known","can't","café","naïve",
}) do
    local a = orp.analyse(word)
    local got = a.orp and a.orp.ch or "(none)"
    local want = expected[word]
    local ok = got == want
    if not ok then fail = fail + 1 end
    print(string.format("%-22s %-5d %-8s %-8s %s %s",
        word, a.letter_count,
        tostring(a.target_n), got, want, ok and "ok" or "<-- MISMATCH"))
end

print(string.rep("-", 60))
if fail == 0 then
    print("ALL PASS")
    return
else
    print(fail .. " FAILURE(S)")
    os.exit(1)
end
