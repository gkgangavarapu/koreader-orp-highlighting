# ORP Highlighting for KOReader

Highlights the **Optimal Recognition Point (ORP)** of every word while you read a
normal, manually-paged reflowable book (EPUB / TXT / FB2 / HTML) in KOReader.

Reading-by-ORP is the trick behind RSVP speed readers: your eye lands on the same
part of each word, so it moves less and reading feels smoother. This plugin keeps
the page a *normal* page — no RSVP, no auto-advance, no scrolling — and only
marks each word's recognition point.

Default ORP rule (configurable in `orp.lua`):

```
1-2 letters  -> letter 1
3-5 letters  -> letter 2
6-9 letters  -> letter 3
10+ letters  -> letter 4
```

The page stays a normal page: no auto-advance and the book file is never
modified.

## Features

- **Underline**, **Inverse**, and **Bold** emphasis on each word's ORP letter.
  Bold is drawn by CREngine while the page is rendered, so it is smooth and
  lag-free.
- **Diagnostic** on the current page: prints a `word | letters | ORP` table so
  you can verify the algorithm independently of the highlight. Works on any
  KOReader, even without the engine capability.
- **Over-the-air (OTA) updates:** checks GitHub Releases about once a week and
  can download, verify (SHA-256), install, and restart for you on request — no
  cable or manual copying needed.
- **Support the project:** a built-in QR code and link for funding.
- Everything is stored in KOReader's global settings, so your choice survives
  across sessions, books, and restarts.
- **No analytics and no telemetry.** The plugin only touches the network when you
  ask it to check for updates.

## Usage

The plugin appears under **Tools → ORP Highlighting** both in the file browser
and while reading. The highlight itself only applies to a reflowable book, so the
toggle and the diagnostic are disabled until a book is open.

1. Open a reflowable book (EPUB, TXT, FB2, HTML).
2. Go to **Tools → ORP Highlighting**.
3. Toggle **ORP Highlighting** on.
4. Pick a **Style**: **Underline**, **Inverse**, or **Bold**.
5. The page is repainted with each word's ORP character marked.

All other entries live under **Other**:

| Menu item | What it does |
|---|---|
| Run ORP diagnostic on current page | Shows the `word / letters / ORP` table for this page |
| Check for updates | Checks GitHub Releases and offers an in-place update |
| Version: … | Shows the installed version and the releases page |
| Support this project | Shows a QR code and link to fund development |
| About | A short description of the plugin |

> **Note:** Underline, Inverse, and Bold need KOReader's visible-glyph engine API
> (`document:orpVisibleWords`) so the plugin knows where each letter is. The
> Diagnostic works without it. See [Requirements](#requirements).

## Requirements

- A jailbroken e-reader running **KOReader**.
- A KOReader build that includes the **visible-glyph engine API**
  (`document:orpVisibleWords`). This is a small additive KOReader engine
  capability (upstream: `koreader-base` #2512 + `koreader` #16022).
  - The **Diagnostic** works on any KOReader.
  - The **Underline / Inverse / Bold** highlight needs that engine API.

Until the capability is in a stock release, use a ready-built package from the
companion repo **[koreader-orp-releases](https://github.com/gkgangavarapu/koreader-orp-releases)**
(Kindle Paperwhite/PW2 builds).

## Download

Get the latest `orp_highlighting.koplugin.zip` from the
[Releases](https://github.com/gkgangavarapu/koreader-orp-highlighting/releases)
page.

## Installation

### Manually

1. Unzip the download and copy the `orp_highlighting.koplugin` folder into your
   KOReader `plugins` directory:
   - Kindle: `/mnt/us/koreader/plugins/` — tested
   - Kobo: `.adds/koreader/plugins/` — untested
   - Android: `/sdcard/koreader/plugins/` — untested
   - Linux / macOS: `~/.config/koreader/plugins/` — untested
2. Restart KOReader.
3. Open a book and go to **Tools → ORP Highlighting**, then toggle it on and
   pick a **Style**.

> Updating from an older version (≤ v0.1.0) has to be done manually once. From
> v0.2.0 onward the plugin can update itself (see [Updates](#updates)).

## Updates

The plugin checks its GitHub Releases once a week and offers to update in place
when a newer version exists. You can also check manually from
**Tools → ORP Highlighting → Other → Check for updates**.

The updater:

- downloads the release zip and its SHA-256 checksum,
- verifies the checksum before touching anything,
- extracts to a staging folder and swaps the plugin folder in place,
- keeps the previous folder as a backup until the next successful start,
- asks you to restart KOReader to apply the new code.

## Changing the ORP rule

Edit the `DEFAULT_RULES` table near the top of
`orp_highlighting.koplugin/orp.lua`:

```lua
local DEFAULT_RULES = {
    { up_to = 2, target = 1 },
    { up_to = 5, target = 2 },
    { up_to = 9, target = 3 },
    { up_to = nil, target = 4 }, -- 10+ letters
}
```

`up_to` is the maximum letter count for a rule (the last entry uses `nil` for
"everything larger"), and `target` is which letter is the recognition point.

## Structure

```
orp_highlighting.koplugin/
  _meta.lua       plugin metadata
  main.lua        reader plugin: menu, toggle, styles, overlay, OTA wiring
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

## Disclaimer

- This is an **unofficial, community project**. It is **not affiliated with,
  endorsed by, or sponsored by KOReader** or its contributors.
- **No warranty.** The software is provided "as is", without warranty of any
  kind, express or implied. Use it at your own risk. The authors are not liable
  for any loss, damage, or consequences arising from its use.
- The plugin does not send your reading data anywhere. It only contacts GitHub
  when checking for an update, and only after you ask it to.

## Support

If you find this plugin useful and want to support its continued development,
you can **Buy Me a Coffee**:

[**https://buymeacoffee.com/gkgangavarapu**](https://buymeacoffee.com/gkgangavarapu)

You can also open the same link (with a scannable QR code) from the plugin:
**Tools → ORP Highlighting → Other → Support this project**.

## License

MIT — see [LICENSE](LICENSE).
