# GitStatusBar

A tiny macOS menu bar app that scans `~/Documents` for git repos and shows each
one's branch + working-tree state. Native AppKit (`NSStatusItem`), no Dock icon,
manual refresh only — idle CPU is 0% and RSS sits in single-digit MB.

Mirrors the behaviour of `../git-overview.sh`.

## Build

Requires the Xcode command-line tools (Swift 5.9+, macOS 13+).

```sh
./build-app.sh
open GitStatusBar.app
```

To install: `mv GitStatusBar.app /Applications/`. To launch on login, drag it
into System Settings → General → Login Items.

## Use

Click the branch icon in the menu bar:

- Top: scan root + summary counts.
- Per-repo line: `name  ⎇ branch  · verdict`. Click → reveal in Finder. Hover →
  last commit.
- `Settings ▸`
  - `Folders to scan`: each configured folder appears here. Hover to reveal a
    submenu with `Reveal in Finder` and `Remove`.
  - `Add folder…` opens a system picker (multi-select supported).
- `↻ Refresh (local)` (⌘R) — rescan working trees only. Fast, no network.
- `⇣ Refresh with remote` (⇧⌘R) — runs `git fetch --quiet` per repo before
  computing ahead/behind. Slower, contacts remotes.
- `Quit` (⌘Q).

## Scope / config

- Default scan root is `~/Documents`, depth 3 (matches `git-overview.sh`).
- Configured folders persist in `UserDefaults` under key `scanRoots`.
- When more than one folder is configured, repo names are prefixed with the
  root's name to disambiguate.
