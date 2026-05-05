import Foundation

enum GitScanner {

    static func scan(roots: [URL], fetch: Bool, maxDepth: Int = 3) async -> [RepoStatus] {
        // Discover repos under each root, attributing each to its origin root
        // (so the displayed name can be relative). Dedupe by absolute path in
        // case roots overlap.
        var seen = Set<String>()
        var pairs: [(repo: URL, root: URL)] = []
        for root in roots {
            let std = root.standardizedFileURL
            for repo in findRepos(root: std, maxDepth: maxDepth) {
                let key = repo.standardizedFileURL.path
                if seen.insert(key).inserted {
                    pairs.append((repo, std))
                }
            }
        }

        let multipleRoots = roots.count > 1

        return await withTaskGroup(of: RepoStatus?.self) { group in
            let limit = 8
            var iterator = pairs.makeIterator()
            var inflight = 0
            var results: [RepoStatus] = []

            func addNext() {
                if let pair = iterator.next() {
                    let repo = pair.repo
                    let root = pair.root
                    group.addTask { inspect(repo: repo, root: root, fetch: fetch, prefixRootName: multipleRoots) }
                    inflight += 1
                }
            }
            for _ in 0..<limit { addNext() }

            while inflight > 0 {
                if let r = await group.next() {
                    inflight -= 1
                    if let r = r { results.append(r) }
                    addNext()
                }
            }
            return results.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    static func scan(root: URL, fetch: Bool, maxDepth: Int = 3) async -> [RepoStatus] {
        let repoPaths = findRepos(root: root, maxDepth: maxDepth)

        return await withTaskGroup(of: RepoStatus?.self) { group in
            // Bound concurrency
            let limit = 8
            var iterator = repoPaths.makeIterator()
            var inflight = 0
            var results: [RepoStatus] = []

            func addNext() {
                if let path = iterator.next() {
                    group.addTask { inspect(repo: path, root: root, fetch: fetch) }
                    inflight += 1
                }
            }
            for _ in 0..<limit { addNext() }

            while inflight > 0 {
                if let r = await group.next() {
                    inflight -= 1
                    if let r = r { results.append(r) }
                    addNext()
                }
            }
            return results.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    // MARK: - Repo discovery

    private static func findRepos(root: URL, maxDepth: Int) -> [URL] {
        var found: [URL] = []
        let fm = FileManager.default
        guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey]),
              rootValues.isDirectory == true else { return [] }

        func walk(_ dir: URL, depth: Int) {
            // Check if this dir has a .git child
            let gitDir = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitDir.path, isDirectory: &isDir), isDir.boolValue {
                found.append(dir)
                return // don't descend into a repo (avoid submodule .git dirs)
            }
            if depth >= maxDepth { return }
            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for child in children {
                let vals = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if vals?.isSymbolicLink == true { continue }
                if vals?.isDirectory == true {
                    walk(child, depth: depth + 1)
                }
            }
        }

        walk(root, depth: 0)
        return found
    }

    // MARK: - Per-repo inspection

    private static func inspect(repo: URL, root: URL, fetch: Bool, prefixRootName: Bool = false) -> RepoStatus {
        let name: String = {
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            let p = repo.path
            let rel: String
            if p.hasPrefix(rootPath) {
                rel = String(p.dropFirst(rootPath.count))
            } else {
                rel = repo.lastPathComponent
            }
            return prefixRootName ? "\(root.lastPathComponent)/\(rel)" : rel
        }()

        let branch = git(["symbolic-ref", "--short", "HEAD"], in: repo)
            ?? git(["rev-parse", "--short", "HEAD"], in: repo)
            ?? "unknown"

        let staged    = lineCount(git(["diff", "--cached", "--numstat"], in: repo))
        let modified  = lineCount(git(["diff", "--numstat"], in: repo))
        let untracked = lineCount(git(["ls-files", "--others", "--exclude-standard"], in: repo))
        let stashes   = lineCount(git(["stash", "list"], in: repo))

        let upstream = git(["rev-parse", "--abbrev-ref", "@{upstream}"], in: repo)
        let hasUpstream = (upstream != nil && !(upstream ?? "").isEmpty)

        var ahead = 0
        var behind = 0
        if let up = upstream, !up.isEmpty {
            if fetch {
                _ = git(["fetch", "--quiet"], in: repo, timeout: 15)
            }
            ahead  = Int(git(["rev-list", "--count", "\(up)..HEAD"], in: repo) ?? "0") ?? 0
            behind = Int(git(["rev-list", "--count", "HEAD..\(up)"], in: repo) ?? "0") ?? 0
        }

        let lastDate = git(["log", "-1", "--format=%ar"], in: repo) ?? "no commits"
        var lastMsg  = git(["log", "-1", "--format=%s"], in: repo) ?? ""
        if lastMsg.count > 60 { lastMsg = String(lastMsg.prefix(57)) + "..." }

        return RepoStatus(
            name: name, path: repo, branch: branch,
            staged: staged, modified: modified, untracked: untracked, stashes: stashes,
            ahead: ahead, behind: behind, hasUpstream: hasUpstream,
            lastDate: lastDate, lastMsg: lastMsg
        )
    }

    // MARK: - Process helpers

    private static func git(_ args: [String], in dir: URL, timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = dir
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        // Avoid pager / locale weirdness
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "C"
        p.environment = env

        do { try p.run() } catch { return nil }

        // Simple timeout
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if p.isRunning {
            p.terminate()
            return nil
        }

        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lineCount(_ s: String?) -> Int {
        guard let s = s, !s.isEmpty else { return 0 }
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }.count
    }
}
