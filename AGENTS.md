# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftPM macOS menu bar app with one executable target, `GitStatusBar`.
Source lives in `Sources/GitStatusBar/`:

- `main.swift`: AppKit status item, menus, settings, refresh lifecycle, and UI actions.
- `GitScanner.swift`: repository discovery and `git` process calls.
- `RepoStatus.swift`: status value types and verdict computation.
- `MenuStyle.swift`: colors, fonts, glyphs, and row styling.

Packaging resources live in `Resources/` (`Info.plist`, icon assets, icon generator). User-facing docs and images live in `README.md`, `docs/`, `decisions.md`, and `glossary.md`. There is currently no `Tests/` directory.

## Build, Test, and Development Commands

- `swift build -c release`: compile the SwiftPM executable target.
- `./build-app.sh`: canonical build; compiles, assembles `GitStatusBar.app`, copies `Info.plist` and the icon, and ad-hoc signs the app.
- `open GitStatusBar.app`: launch the packaged app; it has no Dock icon, so check the menu bar.
- `ps -o rss,pid,comm -p "$(pgrep GitStatusBar)"`: inspect resident memory after launch; ~50-80 MB is expected for AppKit.

Use `./build-app.sh` for any change that could affect packaging, resources, or launch behavior.

## Coding Style & Naming Conventions

Use Swift 5.9+ and AppKit. Follow the existing four-space indentation and Swift naming conventions: types in `UpperCamelCase`, functions/properties in `lowerCamelCase`. Keep responsibilities separated by the files above. Do not introduce SwiftUI, Combine, background polling, or broad abstractions unless the architecture intentionally changes.

New `git` invocations should go through the existing scanner helper path so environment variables, timeouts, and prompt suppression stay consistent.

## Testing Guidelines

There is no automated test suite, linter, or CI at present. Verify changes manually with:

```sh
./build-app.sh && open GitStatusBar.app
```

For scanner or verdict changes, compare menu counts and verdicts against the behavioral reference noted in `CLAUDE.md` (`~/Documents/Scripts/git-overview.sh`) when available. If adding testable non-UI logic, prefer focused SwiftPM tests under `Tests/GitStatusBarTests/`.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative messages such as `Clean up dead code and sync docs with current UI` and `Tighten repo submenu layout and add hover highlight`. Match that style.

Pull requests should include a short behavior summary, manual verification steps, linked issues when relevant, and screenshots or screen recordings for visible menu/UI changes. Note any deliberate divergence from `git-overview.sh` behavior.

## Session docs

- `handoffs/*` - folder with dated handoff files
- `backlog.md` - living TODO. Tags: `[active]`, `[next]`, `[blocked: <reason>]`, no tag = someday.
- Both gitignored.
