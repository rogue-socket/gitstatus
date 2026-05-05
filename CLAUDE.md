# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

`GitStatusBar` is a tiny native macOS menu bar app (AppKit `NSStatusItem`, no
Dock icon) that scans configured folders for git repositories and shows each
repo's branch + working-tree state in its dropdown. It is the GUI equivalent of
`../git-overview.sh` (sibling of this repo, in `~/Documents/git-overview.sh`) —
the Swift code reproduces that script's command list and verdict logic. Treat
the script as the behavioural spec.

## Build / run

There is no Xcode project; this is a SwiftPM executable target.

```sh
swift build -c release            # compile only
./build-app.sh                    # compile + assemble GitStatusBar.app + ad-hoc codesign
open GitStatusBar.app             # launch (no Dock icon — look at the menu bar)
```

`build-app.sh` is the canonical build command — it copies the binary into
`GitStatusBar.app/Contents/MacOS/` alongside `Resources/Info.plist` (which sets
`LSUIElement=true` so the app stays out of the Dock). Always rebuild via this
script when changing anything that affects packaging.

There are no tests, no linter, and no CI. Verification is manual: launch the
`.app`, click the menu bar icon, cross-check repo counts/verdicts against
`bash ~/Documents/git-overview.sh` (with no `--fetch`), and check footprint with
`ps -o rss,pid,comm -p $(pgrep GitStatusBar)` — RSS should sit in single-digit MB.

Minimum target: macOS 13. Swift 5.9+.

## Architecture

Four files in `Sources/GitStatusBar/`, each with a focused responsibility — keep
this separation when extending:

- **`main.swift`** — `AppDelegate` owns the `NSStatusItem`, the menu, persisted
  settings, and the refresh lifecycle. The menu is rebuilt from scratch
  (`rebuildMenu`) on every state change rather than mutated in place; this is
  cheap and avoids stale-item bugs. `menuNeedsUpdate` triggers an auto-refresh
  if the cached scan is older than 2 s.
- **`GitScanner.swift`** — pure scan logic. `scan(roots:fetch:)` walks each
  root with `FileManager` (depth-limited to 3, doesn't descend into a found
  repo), then per-repo shells out to `git` via `Process`. Concurrency is
  bounded to 8 in-flight tasks via a manual `TaskGroup` loop so a slow repo
  can't block the menu. Every `git` call has a 5 s timeout (15 s for `fetch`)
  enforced by polling `Process.isRunning` against a deadline. Results are
  deduped by absolute path so overlapping roots don't double-count.
- **`RepoStatus.swift`** — plain value type plus a computed `verdict` string.
  Mirrors the verdict logic in `git-overview.sh` exactly; if you change it,
  also update the script (or note the divergence).
- **`MenuStyle.swift`** — all visual styling (colours, monospaced font,
  status-dot glyph, inline `arrow.triangle.branch` SF Symbol attachment for
  the branch icon). Centralised so colour/glyph tweaks happen in one place.
  Repo-line layout assumes a monospaced font for column alignment — don't
  switch fonts here without re-checking padding.

### Refresh model

Two explicit user actions, no background timer:

- `refresh(fetch: false)` — local scan only. Bound to ⌘R and to the
  auto-refresh on menu open.
- `refresh(fetch: true)` — runs `git fetch --quiet` per repo first. Bound to
  ⇧⌘R.

`scanning` guards re-entry. The status bar icon is recomputed in
`updateStatusBarIcon()` after every refresh: green seal when clean, teal up
arrow when only ahead, yellow warning triangle when any repo is dirty/behind,
plain branch glyph before the first scan. A numeric badge appears on the
status bar button when dirty count > 0.

### Persisted settings

Only one key in `UserDefaults`: `scanRoots` (`[String]`, with `~` rewritten
back to `$HOME` for portability). When unset, defaults to `["~/Documents"]`.
There is no preferences window — settings live in the `Settings ▸` submenu
(folder list with per-folder Reveal/Remove submenus, plus `Add folder…` which
opens an `NSOpenPanel`).

## Conventions specific to this repo

- Don't introduce SwiftUI, Combine, or async-stream APIs for the menu — the
  whole point of using `NSStatusItem`/`NSMenu` directly is the small RAM/CPU
  footprint. Likewise, don't add a background polling timer.
- Don't call out to the existing `git-overview.sh` from the app — `GitScanner`
  shells `git` directly to avoid an extra `bash` process per refresh.
- Repo discovery uses `FileManager` (not `Process`/`find`) and stops descending
  on entering a `.git` directory to avoid picking up submodules. Preserve both
  behaviours.
- Every `Process` call must set `GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0`,
  `LC_ALL=C` and a timeout — see `GitScanner.git(_:in:timeout:)`. New git
  invocations should go through that helper.
- The plan file in `~/.claude/plans/i-want-to-create-reactive-acorn.md`
  describes the original design; update it if the architecture changes
  meaningfully.
