import Foundation

struct RepoStatus {
    let name: String
    let path: URL
    let branch: String
    let staged: Int
    let modified: Int
    let untracked: Int
    let stashes: Int
    let ahead: Int
    let behind: Int
    let hasUpstream: Bool
    let lastDate: String
    let lastMsg: String

    var isDirty: Bool { staged > 0 || modified > 0 || untracked > 0 }
    var isClean: Bool { !isDirty && ahead == 0 && behind == 0 }

    var verdict: String {
        var parts: [String] = []
        if staged > 0    { parts.append("\(staged) staged") }
        if modified > 0  { parts.append("\(modified) modified") }
        if untracked > 0 { parts.append("\(untracked) untracked") }
        if ahead > 0     { parts.append("↑\(ahead) ahead") }
        if behind > 0    { parts.append("↓\(behind) behind") }
        if stashes > 0   { parts.append("\(stashes) stash") }
        if !hasUpstream  { parts.append("no remote") }
        return parts.isEmpty ? "✓ clean" : parts.joined(separator: "  ")
    }
}

struct BranchStatus {
    let name: String
    let isCurrent: Bool
    let upstream: String?
    let ahead: Int
    let behind: Int
    let upstreamGone: Bool
    let lastDate: String
    let lastMsg: String
}
