# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-09-14

### Added

- **Over-the-air (OTA) updates:** checks GitHub Releases about once a week and
  can download, verify (SHA-256), install in place, and ask for a restart.
  A manual **Check for updates** item is available under **Other**.
- **Bold thickness** selection (Thin / Medium / Thick / Extra thick), rendered
  in the plugin's own overlay so it needs no special KOReader build.
- **Support this project**: a built-in funding dialog with a scannable QR code
  (Buy Me a Coffee) and the link as text.
- A **Version** menu item showing the installed version and the releases page.

### Changed

- The main menu is reorganised: toggle, **Style**, and **Bold thickness** stay
  on top; the diagnostic, update check, version, support, and about now live
  under **Other**.
- Bold emphasis is now painted by the plugin's overlay instead of the CREngine
  `setOrpBoldRects` path, so it works on every build and its thickness is
  selectable.

### Fixed

- `.github/FUNDING.yml` added so GitHub shows the Buy Me a Coffee button.

## [0.1.0] - 2026-09-07

### Added

- Initial release: **Underline**, **Inverse**, and **Bold** emphasis of each
  word's ORP letter on normal, paged, reflowable books (EPUB / TXT / FB2).
- **Run ORP diagnostic on current page**: a `word | letters | ORP` table that
  works on any KOReader, with or without the visible-glyph engine API.
- Pure, dependency-free ORP core (`orp.lua`) with offline unit tests.
