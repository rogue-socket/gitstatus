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
    static func repoLine(_ r: RepoStatus, nameWidth: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()

        let (glyph, dotColor) = dot(for: r)
        s.append(run("\(glyph)  ", font: mono, color: dotColor))

        let paddedName = pad(truncate(r.name, max: nameWidth), to: nameWidth)
        s.append(run(paddedName + "  ", font: monoBd, color: cFg))

        s.append(branchIcon())
        s.append(run(" ", font: mono, color: cDim))
        s.append(run(pad(truncate(r.branch, max: 18), to: 18) + "  ", font: mono, color: cBranch))

        s.append(verdictAttr(r))
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
        s.append(run("\(total) repos   ", font: monoBd, color: cFg))
        s.append(run("✓\(clean) clean   ", font: mono, color: cClean))
        s.append(run("✗\(dirty) dirty   ", font: mono, color: dirty > 0 ? cDirty : cDim))
        s.append(run("↑\(ahead) ahead   ", font: mono, color: ahead > 0 ? cAhead : cDim))
        s.append(run("↓\(behind) behind",   font: mono, color: behind > 0 ? cBehind : cDim))
        return s
    }

    static func headerLine(_ text: String) -> NSAttributedString {
        run(text, font: small, color: cDim)
    }

    static func plainDim(_ text: String) -> NSAttributedString {
        run(text, font: mono, color: cDim)
    }

    // MARK: - Internals

    private static func verdictAttr(_ r: RepoStatus) -> NSAttributedString {
        let s = NSMutableAttributedString()
        var first = true
        func add(_ piece: String, _ color: NSColor) {
            if !first { s.append(run("  ", font: mono, color: cDim)) }
            s.append(run(piece, font: mono, color: color))
            first = false
        }

        if r.staged > 0    { add("●\(r.staged) staged",    cStaged) }
        if r.modified > 0  { add("✎\(r.modified) modified", cModified) }
        if r.untracked > 0 { add("?\(r.untracked) untracked", cUntrack) }
        if r.ahead > 0     { add("↑\(r.ahead) ahead",     cAhead) }
        if r.behind > 0    { add("↓\(r.behind) behind",   cBehind) }
        if r.stashes > 0   { add("≡\(r.stashes) stash",   cDim) }
        if !r.hasUpstream  { add("⊘ no remote",           cDim) }
        if first {
            s.append(run("✓ clean", font: mono, color: cClean))
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

    private static func pad(_ s: String, to width: Int) -> String {
        if s.count >= width { return s }
        return s + String(repeating: " ", count: width - s.count)
    }
}
