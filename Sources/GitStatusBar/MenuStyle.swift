import AppKit

// Visual styling helpers for the menu. Centralised so colours/symbols are easy
// to tweak in one place.
enum MenuStyle {

    static let mono   = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let monoBd = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    static let small  = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    // Status colours
    static let cClean    = NSColor.systemGreen
    static let cDirty    = NSColor.systemYellow
    static let cStaged   = NSColor.systemGreen
    static let cModified = NSColor.systemRed
    static let cUntrack  = NSColor.systemYellow
    static let cAhead    = NSColor.systemTeal
    static let cBehind   = NSColor.systemOrange
    static let cBranch   = NSColor.systemBlue
    static let cDim      = NSColor.secondaryLabelColor
    static let cFg       = NSColor.labelColor

    // Single-glyph status indicator for a repo
    static func dot(for r: RepoStatus) -> (String, NSColor) {
        if r.isDirty && r.behind > 0 { return ("◆", .systemRed) }
        if r.isDirty                 { return ("●", cDirty) }
        if r.behind > 0              { return ("▼", cBehind) }
        if r.ahead > 0               { return ("▲", cAhead) }
        return ("●", cClean)
    }

    // Build the attributed line for a single repo, monospaced and column-aligned.
    // Compact: single-space gaps; deeply nested names rendered as `first/../last`;
    // verdict is colour-coded counts (no per-category icons).
    static func repoLine(_ r: RepoStatus, nameWidth: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()

        let (glyph, dotColor) = dot(for: r)
        s.append(run("\(glyph) ", font: mono, color: dotColor))

        let paddedName = pad(compactName(r.name, max: nameWidth), to: nameWidth)
        s.append(run(paddedName + " ", font: monoBd, color: cFg))

        s.append(branchIcon())
        s.append(run(" ", font: mono, color: cDim))
        s.append(run(pad(truncate(r.branch, max: 10), to: 10) + " ", font: mono, color: cBranch))

        s.append(verdictAttr(r))
        return s
    }

    // Submenu row: per-branch ahead/behind + last commit. Indented under the
    // repo line; current branch marked with a filled dot in branch colour.
    static func branchLine(_ b: BranchStatus) -> NSAttributedString {
        let s = NSMutableAttributedString()

        s.append(run(b.isCurrent ? "● " : "  ",
                     font: mono,
                     color: b.isCurrent ? cBranch : cDim))
        s.append(run(pad(truncate(b.name, max: 22), to: 22) + "  ",
                     font: b.isCurrent ? monoBd : mono,
                     color: cFg))

        if b.upstreamGone {
            s.append(run("⊘ gone", font: mono, color: cDim))
        } else if b.upstream == nil {
            s.append(run("⊘ no remote", font: mono, color: cDim))
        } else if b.ahead == 0 && b.behind == 0 {
            s.append(run("✓", font: mono, color: cClean))
        } else {
            var first = true
            if b.ahead > 0 {
                s.append(run("↑\(b.ahead)", font: mono, color: cAhead))
                first = false
            }
            if b.behind > 0 {
                if !first { s.append(run(" ", font: mono, color: cDim)) }
                s.append(run("↓\(b.behind)", font: mono, color: cBehind))
            }
        }

        if !b.lastDate.isEmpty {
            s.append(run("   ⏱ \(b.lastDate)", font: small, color: cDim))
        }
        if !b.lastMsg.isEmpty {
            s.append(run("  · “\(truncate(b.lastMsg, max: 50))”", font: small, color: cDim))
        }
        return s
    }

    // SF Symbol "arrow.triangle.branch" rendered inline, tinted blue.
    private static func branchIcon() -> NSAttributedString {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [cBranch]))
        guard let img = NSImage(
            systemSymbolName: "arrow.triangle.branch",
            accessibilityDescription: "branch"
        )?.withSymbolConfiguration(cfg) else {
            return run("⎇", font: mono, color: cBranch)
        }
        let att = NSTextAttachment()
        att.image = img
        // Nudge the icon down a hair so it sits on the text baseline.
        att.bounds = CGRect(x: 0, y: -2, width: img.size.width, height: img.size.height)
        return NSAttributedString(attachment: att)
    }

    static func summaryLine(total: Int, clean: Int, dirty: Int, ahead: Int, behind: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(run("\(total) ", font: monoBd, color: cFg))
        s.append(run("✓\(clean) ",  font: mono, color: cClean))
        s.append(run("✗\(dirty) ",  font: mono, color: dirty > 0 ? cDirty : cDim))
        s.append(run("↑\(ahead) ",  font: mono, color: ahead > 0 ? cAhead : cDim))
        s.append(run("↓\(behind)",  font: mono, color: behind > 0 ? cBehind : cDim))
        return s
    }

    static func headerLine(_ text: String) -> NSAttributedString {
        run(text, font: small, color: cDim)
    }

    // MARK: - Repo submenu styling

    // Top-of-submenu: status dot + bold repo name + branch icon + branch name.
    static func repoHeader(_ r: RepoStatus) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let (glyph, dotColor) = dot(for: r)
        s.append(run("\(glyph)  ", font: monoBd, color: dotColor))
        s.append(run(r.name, font: NSFont.systemFont(ofSize: 13, weight: .semibold), color: cFg))
        s.append(run("   ", font: mono, color: cDim))
        s.append(branchIcon())
        s.append(run(" \(r.branch)", font: mono, color: cBranch))
        return s
    }

    // Dim file path under the header.
    static func repoPath(_ url: URL) -> NSAttributedString {
        let path = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return run("   " + path, font: small, color: cDim)
    }

    // Section title ("Status", "Branches"): small caps-style dim line.
    static func sectionHeader(_ text: String) -> NSAttributedString {
        run(text.uppercased(), font: small, color: cDim)
    }

    // "2 staged   3 modified   1 untracked" — nil when nothing dirty.
    static func statusCounts(_ r: RepoStatus) -> NSAttributedString? {
        if r.staged == 0 && r.modified == 0 && r.untracked == 0 { return nil }
        let s = NSMutableAttributedString()
        var first = true
        func add(_ n: Int, _ label: String, _ color: NSColor) {
            if n == 0 { return }
            if !first { s.append(run("   ", font: mono, color: cDim)) }
            s.append(run("\(n) \(label)", font: mono, color: color))
            first = false
        }
        add(r.staged,    "staged",    cStaged)
        add(r.modified,  "modified",  cModified)
        add(r.untracked, "untracked", cUntrack)
        return s
    }

    // "↑3 ahead   ↓1 behind   2 stashes   no remote" — nil when none of those.
    static func statusTrack(_ r: RepoStatus) -> NSAttributedString? {
        if r.ahead == 0 && r.behind == 0 && r.stashes == 0 && r.hasUpstream { return nil }
        let s = NSMutableAttributedString()
        var first = true
        func add(_ piece: String, _ color: NSColor) {
            if !first { s.append(run("   ", font: mono, color: cDim)) }
            s.append(run(piece, font: mono, color: color))
            first = false
        }
        if r.ahead > 0    { add("↑\(r.ahead) ahead",   cAhead) }
        if r.behind > 0   { add("↓\(r.behind) behind", cBehind) }
        if r.stashes > 0  { add("\(r.stashes) stash",  cDim) }
        if !r.hasUpstream { add("no remote",           cDim) }
        return first ? nil : s
    }

    // "last: 2d ago — \"fix login\"" — uses HEAD's last commit info.
    static func statusLast(_ r: RepoStatus) -> NSAttributedString? {
        if r.lastDate.isEmpty && r.lastMsg.isEmpty { return nil }
        let s = NSMutableAttributedString()
        s.append(run("last: ", font: small, color: cDim))
        if !r.lastDate.isEmpty {
            s.append(run(r.lastDate, font: small, color: cDim))
        }
        if !r.lastMsg.isEmpty {
            s.append(run("  · ", font: small, color: cDim))
            s.append(run("“\(truncate(r.lastMsg, max: 50))”", font: small, color: cDim))
        }
        return s
    }

    static func statusClean() -> NSAttributedString {
        run("✓ clean", font: mono, color: cClean)
    }

    // Indent helper for status content rows under a section header.
    static func indent(_ attr: NSAttributedString) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(run("   ", font: mono, color: cDim))
        s.append(attr)
        return s
    }

    static func plainDim(_ text: String) -> NSAttributedString {
        run(text, font: mono, color: cDim)
    }

    // MARK: - Internals

    private static func verdictAttr(_ r: RepoStatus) -> NSAttributedString {
        let s = NSMutableAttributedString()
        var first = true
        func add(_ piece: String, _ color: NSColor) {
            if !first { s.append(run(" ", font: mono, color: cDim)) }
            s.append(run(piece, font: mono, color: color))
            first = false
        }

        // Counts: colour-coded numbers, no per-category icon.
        // Order is fixed so the colour-position mapping is learnable:
        // green=staged, red=modified, yellow=untracked, teal=ahead,
        // orange=behind, dim=stash.
        if r.staged > 0    { add("\(r.staged)", cStaged) }
        if r.modified > 0  { add("\(r.modified)", cModified) }
        if r.untracked > 0 { add("\(r.untracked)", cUntrack) }
        if r.ahead > 0     { add("\(r.ahead)", cAhead) }
        if r.behind > 0    { add("\(r.behind)", cBehind) }
        if r.stashes > 0   { add("\(r.stashes)", cDim) }
        if !r.hasUpstream  { add("⊘", cDim) }
        if first {
            s.append(run("✓", font: mono, color: cClean))
        }
        return s
    }

    private static func run(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        if max <= 1 { return String(s.prefix(max)) }
        return String(s.prefix(max - 1)) + "…"
    }

    // For deeply nested repo names like "Documents/work/foo/myrepo", render as
    // "Documents/../myrepo" when the full path doesn't fit. Single-segment
    // names fall through to plain truncation.
    private static func compactName(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 3 {
            let candidate = "\(parts.first!)/../\(parts.last!)"
            if candidate.count <= max { return candidate }
            return truncate(candidate, max: max)
        }
        return truncate(s, max: max)
    }

    private static func pad(_ s: String, to width: Int) -> String {
        if s.count >= width { return s }
        return s + String(repeating: " ", count: width - s.count)
    }
}
