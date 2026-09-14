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
- **Bold thickness** selection (Thin / Medium / Thick / Extra thick)
- **Diagnostic**: prints a `word | letters | ORP` table for the current page so
  you can verify the algorithm independently of the highlight
- **In-app updates**: checks GitHub Releases and installs a newer plugin in
  place (a restart applies it)
- **Support the project**: a built-in QR code / link for funding

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

## Updates

The plugin checks its GitHub Releases once a week and offers to update in place
when a newer version exists. You can also check manually from
**Tools > ORP Highlighting > Other > Check for updates**. The updater verifies
the release zip's SHA-256 before swapping the plugin folder and keeps the old
folder as a backup until the next successful start.

## Support

**Tools > ORP Highlighting > Other > Support this project** shows a QR code and
link for funding the project.

## Structure

```
orp_highlighting.koplugin/
  _meta.lua       plugin metadata
  main.lua        reader plugin: menu, toggle, styles, bold thickness, overlay
  orp.lua         pure, dependency-free ORP core (UTF-8 safe)
  update.lua      GitHub Releases update checker / installer
  support.lua     support (funding) dialog
  support_qr.lua  precomputed QR matrix for the support dialog
  test_orp.lua    offline unit tests
```

Run the offline tests with any Lua 5.1+ interpreter:

```
lua orp_highlighting.koplugin/test_orp.lua
```

## License

MIT
