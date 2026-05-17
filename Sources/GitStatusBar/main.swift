import AppKit
import Foundation
import ServiceManagement

struct EditorApp {
    let name: String
    let url: URL
}

// representedObject payloads for action handlers.
struct EditorPayload {
    let repo: URL
    let app: URL
}
struct CheckoutPayload {
    let repo: RepoStatus
    let branch: String
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var lastScan: [RepoStatus] = []
    private var lastScanAt: Date = .distantPast
    private var scanning = false

    // MARK: - Persisted settings

    private let rootsKey = "scanRoots"

    // Detected once at launch — checked again is overkill.
    lazy var installedEditors: [EditorApp] = AppDelegate.detectEditors()

    private static func detectEditors() -> [EditorApp] {
        // Each candidate: (display name, bundle IDs to try, fallback paths).
        let candidates: [(String, [String], [String])] = [
            (
                "Sublime Text",
                ["com.sublimetext.4", "com.sublimetext.3"],
                ["/Applications/Sublime Text.app"]
            ),
            (
                "Zed",
                ["dev.zed.Zed"],
                ["/Applications/Zed.app"]
            ),
        ]
        let ws = NSWorkspace.shared
        let fm = FileManager.default
        var found: [EditorApp] = []
        for (name, bids, paths) in candidates {
            var url: URL?
            for bid in bids {
                if let u = ws.urlForApplication(withBundleIdentifier: bid) {
                    url = u
                    break
                }
            }
            if url == nil {
                for p in paths where fm.fileExists(atPath: p) {
                    url = URL(fileURLWithPath: p)
                    break
                }
            }
            if let u = url { found.append(EditorApp(name: name, url: u)) }
        }
        return found
    }

    // Convert a git remote URL (ssh or https) to a web URL we can open in a
    // browser. Returns nil for hosts we don't recognise rather than guessing,
    // since branch deep-links differ per host.
    static func webURL(forRemote remote: String) -> URL? {
        let allowedHosts: Set<String> = [
            "github.com", "gitlab.com", "bitbucket.org",
            "codeberg.org", "git.sr.ht",
        ]
        var s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }

        // SSH style: user@host:path
        if let regex = try? NSRegularExpression(pattern: #"^[^@\s]+@([^:\s]+):(.+)$"#),
            let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
            let hr = Range(m.range(at: 1), in: s),
            let pr = Range(m.range(at: 2), in: s)
        {
            let host = String(s[hr])
            let path = String(s[pr])
            guard allowedHosts.contains(host) else { return nil }
            return URL(string: "https://\(host)/\(path)")
        }

        // ssh://, https://, http://
        if let url = URL(string: s), let host = url.host, allowedHosts.contains(host) {
            return URL(string: "https://\(host)\(url.path)")
        }
        return nil
    }

    // Per-host deep link to a branch's tree view. Falls back to the repo root
    // for hosts where we don't know the path scheme.
    static func branchWebURL(base: URL, branch: String) -> URL {
        guard let host = base.host else { return base }
        switch host {
        case "github.com", "codeberg.org":
            return base.appendingPathComponent("tree").appendingPathComponent(branch)
        case "gitlab.com":
            return base.appendingPathComponent("-")
                .appendingPathComponent("tree")
                .appendingPathComponent(branch)
        case "bitbucket.org":
            return base.appendingPathComponent("src").appendingPathComponent(branch)
        default:
            return base
        }
    }

    private var scanRoots: [URL] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: rootsKey) ?? []
            if stored.isEmpty {
                let home = FileManager.default.homeDirectoryForCurrentUser
                return [home.appendingPathComponent("Documents")]
            }
            return stored.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        }
        set {
            // Store with ~ where possible for portability across user switches.
            let home = NSHomeDirectory()
            let strings = newValue.map { url -> String in
                let p = url.path
                return p.hasPrefix(home) ? "~" + String(p.dropFirst(home.count)) : p
            }
            UserDefaults.standard.set(strings, forKey: rootsKey)
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarIcon()
        menu.delegate = self
        statusItem.menu = menu

        rebuildMenu(placeholder: "Click to scan…")
        Task { await refresh(fetch: false) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if Date().timeIntervalSince(lastScanAt) > 2 && !scanning {
            Task { await refresh(fetch: false) }
        }
        rebuildMenu()
    }

    // MARK: - Refresh

    @MainActor
    private func refresh(fetch: Bool) async {
        if scanning { return }
        scanning = true
        rebuildMenu(placeholder: fetch ? "Fetching from remotes…" : "Scanning…")
        let roots = scanRoots
        let results = await Task.detached(priority: .userInitiated) {
            await GitScanner.scan(roots: roots, fetch: fetch)
        }.value
        lastScan = results
        lastScanAt = Date()
        scanning = false
        updateStatusBarIcon()
        rebuildMenu()
    }

    // MARK: - Status bar icon

    private func updateStatusBarIcon() {
        guard let btn = statusItem.button else { return }

        let dirty = lastScan.filter { $0.isDirty }.count
        let behind = lastScan.filter { $0.behind > 0 }.count
        let ahead = lastScan.filter { $0.ahead > 0 }.count

        let symbolName: String
        let tint: NSColor?
        if lastScan.isEmpty {
            symbolName = "arrow.triangle.branch"
            tint = nil
        } else if behind > 0 || dirty > 0 {
            symbolName = "exclamationmark.triangle.fill"
            tint = .systemYellow
        } else if ahead > 0 {
            symbolName = "arrow.up.circle.fill"
            tint = .systemTeal
        } else {
            symbolName = "checkmark.seal.fill"
            tint = .systemGreen
        }

        let img: NSImage?
        if let tint = tint, #available(macOS 12.0, *) {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [tint])
            img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Git Status")?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
        } else {
            img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Git Status")
            img?.isTemplate = true
        }
        btn.image = img

        // Optional small numeric badge: count of dirty repos.
        if dirty > 0 {
            btn.title = " \(dirty)"
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            btn.imagePosition = .imageLeft
        } else {
            btn.title = ""
            btn.imagePosition = .imageOnly
        }
    }

    // MARK: - Menu construction

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func rebuildMenu(placeholder: String? = nil) {
        menu.removeAllItems()

        let roots = scanRoots
        let rootSummary: String
        if roots.count == 1 {
            rootSummary = "\(displayPath(roots[0]))"
        } else {
            rootSummary = "\(roots.count) folders"
        }
        menu.addItem(makeCompactItem(MenuStyle.headerLine(rootSummary), enabled: false))

        if let placeholder = placeholder, lastScan.isEmpty {
            menu.addItem(makeCompactItem(MenuStyle.plainDim(placeholder), enabled: false))
        } else {
            let total = lastScan.count
            let clean = lastScan.filter { $0.isClean }.count
            let dirty = lastScan.filter { $0.isDirty }.count
            let ahead = lastScan.filter { $0.ahead > 0 }.count
            let behind = lastScan.filter { $0.behind > 0 }.count
            menu.addItem(
                makeCompactItem(
                    MenuStyle.summaryLine(
                        total: total, clean: clean, dirty: dirty, ahead: ahead, behind: behind),
                    enabled: false
                ))
        }

        menu.addItem(.separator())

        // Compute name column width once, capped tight. Long multi-segment
        // names get compacted to `first/../last` by MenuStyle.repoLine to fit.
        let maxName = min(28, max(12, lastScan.map { $0.name.count }.max() ?? 12))
        for repo in lastScan {
            // Item with a submenu — clicking the parent opens the submenu (the
            // submenu's "Reveal in Finder" item replaces the old click action).
            // Custom view suppresses the AppKit disclosure arrow + its padding.
            let item = NSMenuItem(title: repo.name, action: nil, keyEquivalent: "")
            let attr = MenuStyle.repoLine(repo, nameWidth: maxName)
            item.attributedTitle = attr
            item.view = CompactRowView(attr: attr)
            item.representedObject = repo.path
            item.submenu = BranchSubmenu(repo: repo, owner: self)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Settings — keep submenu attached; custom view suppresses the arrow.
        let settingsItem = makeCompactItem(controlAttr("⚙︎  Settings", shortcut: ""))
        settingsItem.submenu = buildSettingsMenu()
        menu.addItem(settingsItem)

        let refreshLocal = makeCompactItem(
            controlAttr(scanning ? "↻  Refreshing…" : "↻  Refresh", shortcut: scanning ? "" : "⌘R"),
            action: #selector(refreshLocalAction(_:)),
            keyEquiv: "r"
        )
        refreshLocal.isEnabled = !scanning
        menu.addItem(refreshLocal)

        let refreshRemote = makeCompactItem(
            controlAttr(
                scanning ? "⇣  Fetching…" : "⇣  Refresh + fetch", shortcut: scanning ? "" : "⇧⌘R"),
            action: #selector(refreshRemoteAction(_:)),
            keyEquiv: "R",
            keyMask: [.command, .shift]
        )
        refreshRemote.isEnabled = !scanning
        menu.addItem(refreshRemote)

        menu.addItem(
            makeCompactItem(
                controlAttr("⏻  Quit", shortcut: "⌘Q"),
                action: #selector(NSApplication.terminate(_:)),
                target: NSApp,
                keyEquiv: "q"
            ))
    }

    // MARK: - Compact item helpers

    private func makeCompactItem(
        _ attr: NSAttributedString,
        action: Selector? = nil,
        target: AnyObject? = nil,
        keyEquiv: String = "",
        keyMask: NSEvent.ModifierFlags = [],
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: keyEquiv)
        item.keyEquivalentModifierMask = keyMask
        item.target = target ?? self
        item.view = CompactRowView(attr: attr)
        item.isEnabled = enabled
        return item
    }

    // Title + dim shortcut hint, used for non-repo control rows.
    private func controlAttr(_ title: String, shortcut: String) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.menuFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor,
                ]))
        if !shortcut.isEmpty {
            s.append(
                NSAttributedString(
                    string: "  " + shortcut,
                    attributes: [
                        .font: NSFont.menuFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]))
        }
        return s
    }

    private func buildSettingsMenu() -> NSMenu {
        let m = NSMenu()

        let foldersHeader = NSMenuItem(title: "Folders to scan", action: nil, keyEquivalent: "")
        foldersHeader.isEnabled = false
        m.addItem(foldersHeader)

        let roots = scanRoots
        for (idx, root) in roots.enumerated() {
            let folderItem = NSMenuItem(
                title: "  " + displayPath(root), action: nil, keyEquivalent: "")
            let sub = NSMenu()

            let revealItem = NSMenuItem(
                title: "Reveal in Finder", action: #selector(revealRoot(_:)), keyEquivalent: "")
            revealItem.target = self
            revealItem.representedObject = root
            sub.addItem(revealItem)

            let removeItem = NSMenuItem(
                title: "Remove", action: #selector(removeRoot(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = idx
            removeItem.isEnabled = roots.count > 1  // keep at least one
            sub.addItem(removeItem)

            folderItem.submenu = sub
            m.addItem(folderItem)
        }

        let addItem = NSMenuItem(
            title: "Add folder…", action: #selector(addFolder(_:)), keyEquivalent: "")
        addItem.target = self
        m.addItem(addItem)

        m.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(launchItem)

        return m
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Actions

    @objc private func revealRoot(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func refreshLocalAction(_ sender: NSMenuItem) {
        Task { await refresh(fetch: false) }
    }

    @objc private func refreshRemoteAction(_ sender: NSMenuItem) {
        Task { await refresh(fetch: true) }
    }

    @objc private func addFolder(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more folders to scan for git repositories."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        var roots = scanRoots
        let existing = Set(roots.map { $0.standardizedFileURL.path })
        for url in panel.urls {
            let std = url.standardizedFileURL
            if !existing.contains(std.path) {
                roots.append(std)
            }
        }
        scanRoots = roots
        Task { await refresh(fetch: false) }
    }

    @objc private func removeRoot(_ sender: NSMenuItem) {
        guard let idx = sender.representedObject as? Int else { return }
        var roots = scanRoots
        guard roots.indices.contains(idx), roots.count > 1 else { return }
        roots.remove(at: idx)
        scanRoots = roots
        Task { await refresh(fetch: false) }
    }

    // MARK: - Repo submenu actions

    @objc func actOpenInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func actOpenInTerminal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let term =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")
        guard let term = term else {
            warn("No terminal app found", "Install Terminal.app or iTerm2.")
            return
        }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: term,
            configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func actOpenInEditor(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? EditorPayload else { return }
        NSWorkspace.shared.open(
            [p.repo],
            withApplicationAt: p.app,
            configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func actCopyString(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    @objc func actOpenURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func actCheckout(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? CheckoutPayload else { return }
        if p.repo.isDirty {
            warn(
                "Working tree has uncommitted changes",
                "Checking out \(p.branch) could clobber local changes. Commit or stash first.")
            return
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                GitScanner.checkout(branch: p.branch, in: p.repo.path)
            }.value
            if !result.ok {
                self?.warn(
                    "Checkout failed",
                    result.message.isEmpty ? "git exited non-zero" : result.message)
            }
            await self?.refresh(fetch: false)
        }
    }

    private func warn(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// Custom row view used in place of NSMenuItem.attributedTitle. Suppresses
// AppKit's standard menu chrome (submenu arrow, reserved shortcut column,
// trailing padding) so the menu's natural width tracks our content exactly.
final class CompactRowView: NSView {
    init(attr: NSAttributedString) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithAttributedString: attr)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let size = attr.size()
        frame.size = NSSize(
            width: ceil(size.width) + 22,
            height: max(24, ceil(size.height) + 8)
        )
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard enclosingMenuItem?.isHighlighted == true else { return }
        let rect = bounds.insetBy(dx: 5, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
        path.fill()
    }
}

// Per-repo submenu. Builds four blocks: header (name + path), Status
// (counts + ahead/behind + last commit), Actions (open/copy on one row),
// Branches (list, each with its own sub-submenu of branch actions).
//
// Branches and remote URL load lazily on first hover via two git calls; cached
// per submenu instance, so refresh (which recreates these) invalidates the
// cache for free.
final class BranchSubmenu: NSMenu, NSMenuDelegate {
    let repo: RepoStatus
    weak var owner: AppDelegate?
    private var loaded = false
    private var loading = false
    private var branches: [BranchStatus]? = nil
    private var remoteWebURL: URL? = nil

    init(repo: RepoStatus, owner: AppDelegate) {
        self.repo = repo
        self.owner = owner
        super.init(title: "")
        delegate = self
        rebuild()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if loaded || loading { return }
        loading = true
        let path = repo.path
        Task { [weak self] in
            async let branchList = GitScanner.branches(in: path)
            async let remote = GitScanner.remoteURL(in: path)
            let loadedBranches = await branchList
            let loadedRemote = await remote
            guard let self else { return }
            self.branches = loadedBranches
            self.remoteWebURL = loadedRemote.flatMap { AppDelegate.webURL(forRemote: $0) }
            self.loaded = true
            self.loading = false
            self.rebuild()
        }
    }

    private func rebuild() {
        removeAllItems()
        guard let owner = owner else { return }

        // --- Header
        addInfo(MenuStyle.repoHeader(repo))

        addItem(.separator())

        // --- Status
        addInfo(MenuStyle.sectionHeader("Status"))
        let counts = MenuStyle.statusCounts(repo)
        let track  = MenuStyle.statusTrack(repo)
        if counts != nil || track != nil {
            let line = NSMutableAttributedString()
            if let c = counts { line.append(c) }
            if let t = track {
                if line.length > 0 { line.append(MenuStyle.plainDim("   ")) }
                line.append(t)
            }
            addInfo(MenuStyle.indent(line))
        } else {
            addInfo(MenuStyle.indent(MenuStyle.statusClean()))
        }
        if let line = MenuStyle.statusLast(repo) {
            addInfo(MenuStyle.indent(line))
        }

        addItem(.separator())

        // --- Actions (two compact text rows: "Open: ..." and "Copy: ...")
        var openActions: [TextAction] = [
            TextAction(
                label: "Finder",
                target: owner,
                action: #selector(AppDelegate.actOpenInFinder(_:)),
                representedObject: repo.path),
            TextAction(
                label: "Terminal",
                target: owner,
                action: #selector(AppDelegate.actOpenInTerminal(_:)),
                representedObject: repo.path),
        ]
        for editor in owner.installedEditors {
            openActions.append(
                TextAction(
                    label: editor.name,
                    target: owner,
                    action: #selector(AppDelegate.actOpenInEditor(_:)),
                    representedObject: EditorPayload(repo: repo.path, app: editor.url)
                ))
        }
        if let webURL = remoteWebURL {
            openActions.append(
                TextAction(
                    label: webURL.host ?? "remote",
                    target: owner,
                    action: #selector(AppDelegate.actOpenURL(_:)),
                    representedObject: webURL
                ))
        }
        let copyActions: [TextAction] = [
            TextAction(
                label: "path",
                target: owner,
                action: #selector(AppDelegate.actCopyString(_:)),
                representedObject: repo.path.path),
            TextAction(
                label: "branch",
                target: owner,
                action: #selector(AppDelegate.actCopyString(_:)),
                representedObject: repo.branch),
        ]

        let actionsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        actionsItem.view = TextActionRow(groups: [
            TextActionGroup(prefix: "Open:", actions: openActions),
            TextActionGroup(prefix: "Copy:", actions: copyActions),
        ])
        addItem(actionsItem)

        addItem(.separator())

        // --- Branches
        addInfo(MenuStyle.sectionHeader("Branches"))

        guard let branches = branches else {
            addInfo(MenuStyle.indent(MenuStyle.plainDim("loading…")))
            return
        }
        if branches.isEmpty {
            addInfo(MenuStyle.indent(MenuStyle.plainDim("(no local branches)")))
            return
        }

        for b in branches {
            let attr = MenuStyle.branchLine(b)
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.attributedTitle = attr
            // Custom view escapes the menu cell's disabled-appearance overlay
            // and matches the parent menu's repo-row styling.
            item.view = CompactRowView(attr: attr)
            item.submenu = makeBranchSubmenu(b, owner: owner)
            addItem(item)
        }
    }

    private func makeBranchSubmenu(_ b: BranchStatus, owner: AppDelegate) -> NSMenu {
        let m = NSMenu()
        let copy = NSMenuItem(
            title: "Copy name",
            action: #selector(AppDelegate.actCopyString(_:)),
            keyEquivalent: "")
        copy.target = owner
        copy.representedObject = b.name
        m.addItem(copy)

        if let webURL = remoteWebURL {
            let branchURL = AppDelegate.branchWebURL(base: webURL, branch: b.name)
            let open = NSMenuItem(
                title: "Open on \(webURL.host ?? "remote")",
                action: #selector(AppDelegate.actOpenURL(_:)),
                keyEquivalent: "")
            open.target = owner
            open.representedObject = branchURL
            m.addItem(open)
        }

        if !b.isCurrent {
            let co = NSMenuItem(
                title: "Checkout",
                action: #selector(AppDelegate.actCheckout(_:)),
                keyEquivalent: "")
            co.target = owner
            co.representedObject = CheckoutPayload(repo: repo, branch: b.name)
            if repo.isDirty {
                co.toolTip = "Working tree has uncommitted changes — checkout will be refused."
            }
            m.addItem(co)
        }
        return m
    }

    // Display-only row. Uses a custom view rather than attributedTitle +
    // isEnabled=false because AppKit applies a "disabled appearance" overlay
    // to disabled menu cells that washes out explicit colours; custom views
    // render at full opacity regardless.
    private func addInfo(_ attr: NSAttributedString) {
        let it = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        it.view = CompactRowView(attr: attr)
        it.isEnabled = false
        addItem(it)
    }

}

// One clickable text segment in TextActionRow. Carries the same
// (target, action, representedObject) shape as an NSMenuItem so we can route
// clicks straight to the existing AppDelegate handlers.
struct TextAction {
    let label: String
    let target: AnyObject
    let action: Selector
    let representedObject: Any?
}

// One labelled run of actions inside a TextActionRow, e.g. ("Open:", [Finder, Terminal]).
struct TextActionGroup {
    let prefix: String
    let actions: [TextAction]
}

// A row like "Open: Finder · Terminal   Copy: path · branch" rendered as a
// menu item view. Each group's dim verb prefix sits before its action labels;
// borderless NSButton labels close the menu hierarchy and invoke the handler
// with a synthetic NSMenuItem carrying representedObject — so AppDelegate's
// existing `act*` handlers don't need to know about this widget.
final class TextActionRow: NSView {
    private let actions: [TextAction]

    init(groups: [TextActionGroup]) {
        self.actions = groups.flatMap { $0.actions }
        super.init(frame: .zero)

        let font = NSFont.menuFont(ofSize: 13)
        let prefixColor = NSColor.secondaryLabelColor
        let textColor = NSColor.labelColor
        let sepColor = NSColor.tertiaryLabelColor
        let leading: CGFloat = 14
        let trailing: CGFloat = 14
        let topPad: CGFloat = 3
        let bottomPad: CGFloat = 3

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false

        var tag = 0
        for (gi, group) in groups.enumerated() {
            if gi > 0 {
                // Wider visual gap between groups than between action items.
                stack.addArrangedSubview(label("   ", font: font, color: sepColor))
            }
            stack.addArrangedSubview(label(group.prefix, font: font, color: prefixColor))
            for (i, a) in group.actions.enumerated() {
                if i > 0 {
                    stack.addArrangedSubview(label("·", font: font, color: sepColor))
                }
                let btn = NSButton()
                btn.isBordered = false
                btn.bezelStyle = .inline
                btn.attributedTitle = NSAttributedString(
                    string: a.label,
                    attributes: [
                        .font: font,
                        .foregroundColor: textColor,
                    ])
                btn.target = self
                btn.action = #selector(clicked(_:))
                btn.tag = tag
                tag += 1
                stack.addArrangedSubview(btn)
            }
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailing),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: topPad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPad),
        ])

        let fitting = stack.fittingSize
        frame.size = NSSize(
            width: fitting.width + leading + trailing,
            height: fitting.height + topPad + bottomPad)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = font
        t.textColor = color
        t.drawsBackground = false
        t.isBordered = false
        t.isEditable = false
        t.isSelectable = false
        return t
    }

    @objc private func clicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < actions.count else { return }
        let a = actions[sender.tag]
        // Walk up to the topmost menu and cancel tracking — closes the whole
        // menu chain, matching the feel of clicking a normal menu item.
        var m = enclosingMenuItem?.menu
        while let parent = m?.supermenu { m = parent }
        m?.cancelTrackingWithoutAnimation()
        // AppDelegate handlers expect NSMenuItem and read representedObject.
        let item = NSMenuItem()
        item.representedObject = a.representedObject
        _ = a.target.perform(a.action, with: item)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
