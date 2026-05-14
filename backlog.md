# Backlog

The single TODO list for this project. Each entry: one-line item specific enough to act on cold, with an optional status tag and **Why:** if non-obvious.

Status tags:
- `[active YYYY-MM-DD]` — currently being worked on (date set when activated)
- `[next]` — pick up next session
- `[blocked: <reason>]` — can't proceed; reason inline
- (no tag) — someday/maybe (default)

`/get-started` reads `[active]` and `[next]` to brief the next session. `[active]` items older than 7 days are flagged for staleness review.

## Open

- Verify whether tooltips actually render inside `NSMenu` custom views before reattempting any icon-based menu UI. **Why:** rationale for ditching the icon strip mid-session, never empirically confirmed — would unblock a future icon-strip experiment.
- Consider a hover indicator on `TextActionRow` segments (faint underline + hand cursor on entry). **Why:** segments aren't visually obvious as buttons; user said the lack is acceptable but flagged it as worth doing if cheap.
- Move `BranchSubmenu`, `TextActionRow`, and `CompactRowView` out of `main.swift` into their own file(s). **Why:** project's "four files" convention in CLAUDE.md; `main.swift` is now 821 lines and hosts three classes that could each live alone.
- `BranchSubmenu` shows a "loading…" placeholder briefly on first hover. **Why:** acceptable but visible; could be hidden behind a 100ms delay or replaced with a shimmer.
