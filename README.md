# ORP Highlighting for KOReader

Highlights the **Optimal Recognition Point (ORP)** of every word while you read a
normal, manually-paged reflowable book (EPUB / TXT / FB2) in KOReader.

ORP rule (configurable in `orp.lua`):

```
1-2 letters  -> letter 1
3-5 letters  -> letter 2
6-9 letters  -> letter 3
10+ letters  -> letter 4
```

The page stays a normal page: no RSVP, no auto-advance, no scrolling, and the
book file is never modified.

## Features

- **Underline**, **Inverse**, **Bold** emphasis on each word's ORP letter
- **Diagnostic**: prints a `word | letters | ORP` table for the current page so
  you can verify the algorithm independently of the highlight

## Requirements

- A jailbroken e-reader running **KOReader**.
- A KOReader build that includes the **visible-glyph engine API**
  (`document:orpVisibleWords`). This is a small additive KOReader engine
  capability (upstream: `koreader-base` #2512 + `koreader` #16022). Until it is in
  a stock release, use a build that has it (see the companion repo
  `koreader-orp-releases` for ready-built packages).
  - The **Diagnostic** works on any KOReader.
  - The **Underline / Inverse / Bold** highlight needs that engine API.

## Install

1. Download the latest **`orp_highlighting.koplugin.zip`** from
   [Releases](../../releases).
2. Extract it, then copy the **`orp_highlighting.koplugin`** folder into
   `koreader/plugins/` on your device.
3. Restart KOReader, open a book, and go to **Tools > ORP Highlighting**:
   toggle **ON** and pick a **Style**, or run the **Diagnostic**.

## Changing the ORP rule

Edit the `DEFAULT_RULES` table near the top of `orp_highlighting.koplugin/orp.lua`.

## Structure

```
orp_highlighting.koplugin/
  _meta.lua     plugin metadata
  main.lua      reader plugin: menu, toggle, styles, diagnostic, overlay
  orp.lua       pure, dependency-free ORP core (UTF-8 safe)
  test_orp.lua  offline unit tests
```

Run the offline tests with any Lua 5.1+ interpreter:

```
lua orp_highlighting.koplugin/test_orp.lua
```

## License

MIT
