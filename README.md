# Ramlet

[![CI](https://github.com/0xtlt/ramlet/actions/workflows/ci.yml/badge.svg)](https://github.com/0xtlt/ramlet/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/0xtlt/ramlet?style=flat-square)](https://github.com/0xtlt/ramlet/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Lightweight macOS menu bar monitor for unified memory. It shows allocated /
compressed / wired / swap at a glance, plus per-app physical footprint.

The menu follows the system language (**English**, **French**, **Spanish**).
Byte sizes use the macOS locale (for example `12,84 Go` in French).

## Screenshot

Ramlet is a menu bar extra: a `memorychip` icon, a fixed-width allocated-memory
figure, and a dropdown. The dropdown shows unified memory (allocated /
compressed / wired / swap), then apps by physical footprint with their macOS
icons, macOS services, unattributed caches, and actions (refresh, Activity
Monitor, quit). The original French UI is the visual reference; English and
Spanish keep the same layout and SF Symbols.

## Features

- **Menu bar total** — allocated unified memory on a fixed-width status item
- **Memory breakdown** — compressed, wired, and swap
- **Per-app footprint** — apps grouped with helper processes, using each app’s macOS icon
- **Caches toggle** — persist whether file cache, shared memory, and other unattributed memory count toward the menu bar total
- **GPU note** — physical footprint includes GPU when macOS can attribute it
- **Refresh** — automatic every 15 seconds, and immediately when the menu opens (`⌘R` to refresh, `⌘Q` to quit)
- **Activity Monitor** — one click from the menu

Per-app numbers come from the physical footprint published by macOS
(`proc_pid_rusage`). On Apple Silicon, GPU allocations share the unified memory
pool, but macOS does not expose a complete per-app GPU breakdown. Ramlet labels
this as GPU included when attributable.

## Install

### Download a release

Grab the latest signed DMG from
[Releases](https://github.com/0xtlt/ramlet/releases):

- `Ramlet-arm64.dmg` for Apple Silicon
- `Ramlet-x86_64.dmg` for Intel

Open the DMG and drag **Ramlet** to Applications. Ramlet is a menu bar extra
(`LSUIElement`); it does not show a Dock icon.

GitHub Release builds are signed with a Developer ID certificate and notarized,
using the same secret names as [Vitrail](https://github.com/0xtlt/vitrail) and
[Foldbar](https://github.com/0xtlt/foldbar).

### From source

Requires **macOS 13+**, Rust 1.85+ (edition 2024), and Xcode Command Line Tools.

```bash
git clone https://github.com/0xtlt/ramlet.git
cd ramlet
cargo test --locked
./scripts/package-macos.sh
dist/Ramlet.app/Contents/MacOS/ramlet --snapshot
dist/Ramlet.app/Contents/MacOS/ramlet --self-test-ui
open dist/Ramlet.app
```

`scripts/package-macos.sh` builds `dist/Ramlet.app`, a zip, and a DMG. Pass
`arm64` or `x86_64` to cross-compile. Local bundles are ad-hoc signed; they are
not notarized.

```bash
./scripts/package-macos.sh --release arm64
./scripts/package-macos.sh --release x86_64
```

## Localization

UI strings live in `macos/{en,fr,es}.lproj/Localizable.strings` and are copied
into the app bundle. Ramlet uses the macOS preferred language, with English as
the development language.

| Locale | Menu example |
| --- | --- |
| English | Used / compressed / wired / swap · Refresh Now · Quit Ramlet |
| French | Utilisés / compressée / câblée / swap · Actualiser maintenant · Quitter Ramlet |
| Spanish | Usados / comprimida / reservada / swap · Actualizar ahora · Salir de Ramlet |

## Releasing

1. Confirm `Cargo.toml` and `macos/Info.plist` share the same version
   (`CFBundleShortVersionString`). Bump `CFBundleVersion` as well.
2. Add these repository secrets if they are not already inherited from the
   account (same names as Vitrail — do not invent new ones):
   - `CERTIFICATE_BASE64`
   - `CERTIFICATE_PASSWORD`
   - `APPLE_ID`
   - `APPLE_ID_PASSWORD`
   - `APPLE_TEAM_ID`
3. Commit on `main`, then publish a GitHub Release whose tag is `v` plus the
   crate version (first public cut: **`v0.3.0`**).

   ```bash
   git tag v0.3.0
   git push origin v0.3.0
   gh release create v0.3.0 --title "Ramlet 0.3.0" --generate-notes
   ```

4. `.github/workflows/release.yml` runs on `release: created`. It builds
   **arm64** and **x86_64**, signs with Developer ID, notarizes, staples, and
   uploads `Ramlet-arm64.dmg` and `Ramlet-x86_64.dmg`.

Creating the GitHub Release is what starts packaging. Wait until both matrix
jobs finish before sharing the DMGs.

A Homebrew cask can be added later to [`0xtlt/tap`](https://github.com/0xtlt/homebrew-tap),
the same way as Vitrail and Foldbar.

## Requirements

- macOS 13 Ventura or later
- Rust 1.85+ and Xcode Command Line Tools to build from source

## License

[MIT](LICENSE)
