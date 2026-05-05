import AppKit
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var lastScan: [RepoStatus] = []
    private var lastScanAt: Date = .distantPast
    private var scanning = false

    // MARK: - Persisted settings

    private let rootsKey = "scanRoots"

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

        let dirty  = lastScan.filter { $0.isDirty }.count
        let behind = lastScan.filter { $0.behind > 0 }.count
        let ahead  = lastScan.filter { $0.ahead > 0 }.count

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
            rootSummary = "📂  \(displayPath(roots[0]))"
        } else {
            rootSummary = "📂  \(roots.count) folders"
        }
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.attributedTitle = MenuStyle.headerLine(rootSummary)
        header.isEnabled = false
        menu.addItem(header)

        if let placeholder = placeholder, lastScan.isEmpty {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.attributedTitle = MenuStyle.plainDim(placeholder)
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let total = lastScan.count
            let clean = lastScan.filter { $0.isClean }.count
            let dirty = lastScan.filter { $0.isDirty }.count
            let ahead = lastScan.filter { $0.ahead > 0 }.count
            let behind = lastScan.filter { $0.behind > 0 }.count
            let summary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            summary.attributedTitle = MenuStyle.summaryLine(
                total: total, clean: clean, dirty: dirty, ahead: ahead, behind: behind
            )
            summary.isEnabled = false
            menu.addItem(summary)
        }

        menu.addItem(.separator())

        // Compute name column width once, capped to keep menu narrow.
        let maxName = min(40, max(12, lastScan.map { $0.name.count }.max() ?? 12))
        for repo in lastScan {
            let item = NSMenuItem(title: repo.name, action: #selector(openRepo(_:)), keyEquivalent: "")
            item.attributedTitle = MenuStyle.repoLine(repo, nameWidth: maxName)
            item.target = self
            item.representedObject = repo.path
            if !repo.lastMsg.isEmpty {
                item.toolTip = "last: \(repo.lastMsg) (\(repo.lastDate))"
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Settings submenu
        let settingsItem = NSMenuItem(title: "⚙︎  Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = buildSettingsMenu()
        menu.addItem(settingsItem)

        let refreshLocal = NSMenuItem(
            title: scanning ? "↻  Refreshing…" : "↻  Refresh (local)",
            action: #selector(refreshLocalAction(_:)),
            keyEquivalent: "r"
        )
        refreshLocal.target = self
        refreshLocal.isEnabled = !scanning
        refreshLocal.toolTip = "Rescan working trees only — fast, no network."
        menu.addItem(refreshLocal)

        let refreshRemote = NSMenuItem(
            title: scanning ? "⇣  Fetching…" : "⇣  Refresh with remote",
            action: #selector(refreshRemoteAction(_:)),
            keyEquivalent: "R"
        )
        refreshRemote.keyEquivalentModifierMask = [.command, .shift]
        refreshRemote.target = self
        refreshRemote.isEnabled = !scanning
        refreshRemote.toolTip = "Run `git fetch` per repo before computing ahead/behind. Slower."
        menu.addItem(refreshRemote)

        menu.addItem(NSMenuItem(title: "⏻  Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func buildSettingsMenu() -> NSMenu {
        let m = NSMenu()

        let foldersHeader = NSMenuItem(title: "Folders to scan", action: nil, keyEquivalent: "")
        foldersHeader.isEnabled = false
        m.addItem(foldersHeader)

        let roots = scanRoots
        for (idx, root) in roots.enumerated() {
            let folderItem = NSMenuItem(title: "  " + displayPath(root), action: nil, keyEquivalent: "")
            let sub = NSMenu()

            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealRoot(_:)), keyEquivalent: "")
            revealItem.target = self
            revealItem.representedObject = root
            sub.addItem(revealItem)

            let removeItem = NSMenuItem(title: "Remove", action: #selector(removeRoot(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = idx
            removeItem.isEnabled = roots.count > 1  // keep at least one
            sub.addItem(removeItem)

            folderItem.submenu = sub
            m.addItem(folderItem)
        }

        let addItem = NSMenuItem(title: "Add folder…", action: #selector(addFolder(_:)), keyEquivalent: "")
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

    @objc private func openRepo(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
