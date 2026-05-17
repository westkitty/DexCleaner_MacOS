import Foundation

public struct SafetyDecision: Hashable, Sendable {
    public var allowed: Bool
    public var reason: String

    public init(allowed: Bool, reason: String) {
        self.allowed = allowed
        self.reason = reason
    }
}

public enum SafetyEngine {
    public static let gitTempPackMinimumAge: TimeInterval = 10 * 60

    public static func decision(
        for item: ScanItem,
        home: String = NSHomeDirectory(),
        gitProcessChecker: () -> Bool = gitProcessIsRunning
    ) -> SafetyDecision {
        let path = lexicalNormalize(item.path)
        let homePath = lexicalNormalize(home)

        if item.action != .moveToTrash {
            return SafetyDecision(allowed: false, reason: "Audit-only item cannot be cleaned.")
        }

        if item.risk != .safe {
            return SafetyDecision(allowed: false, reason: "Only Safe items can be moved to Trash.")
        }

        if path == homePath || path == "/" {
            return SafetyDecision(allowed: false, reason: "Refusing home or root path.")
        }

        guard path == homePath || path.hasPrefix(homePath + "/") else {
            return SafetyDecision(allowed: false, reason: "Path is outside the current user's home directory.")
        }

        if item.category == .gitTemporaryPack {
            return gitTemporaryPackDecision(path: path, home: homePath, gitProcessChecker: gitProcessChecker)
        }

        let broadRoots = [
            homePath + "/.cache",
            homePath + "/Library/Caches",
            homePath + "/Library/Application Support",
            homePath + "/Library",
            homePath + "/Projects",
            homePath + "/Documents",
            homePath + "/Downloads",
            homePath + "/Movies",
            homePath + "/Pictures",
            homePath + "/Desktop"
        ]
        if broadRoots.contains(path) {
            return SafetyDecision(allowed: false, reason: "Refusing broad root path.")
        }

        for fragment in CleanupCatalog.forbiddenFragments where path.contains(fragment) {
            return SafetyDecision(allowed: false, reason: "Protected state/session/user-data path: \(fragment)")
        }

        if containsSymlinkComponent(path: path, home: homePath) {
            return SafetyDecision(allowed: false, reason: "Refusing path with symlink component. Exact cleanup targets must not redirect elsewhere.")
        }

        let allowedPaths = CleanupCatalog.exactAllowedPaths(home: homePath)
        guard allowedPaths.contains(path) else {
            return SafetyDecision(allowed: false, reason: "Path is not an exact manifest allowlist target.")
        }

        return SafetyDecision(allowed: true, reason: "Exact manifest-approved cache path.")
    }

    public static func lexicalNormalize(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    public static func containsSymlinkComponent(path: String, home: String) -> Bool {
        let normalizedPath = lexicalNormalize(path)
        let normalizedHome = lexicalNormalize(home)
        guard normalizedPath.hasPrefix(normalizedHome + "/") else { return true }

        let relative = String(normalizedPath.dropFirst(normalizedHome.count + 1))
        guard !relative.isEmpty else { return false }

        var current = URL(fileURLWithPath: normalizedHome)
        for component in relative.split(separator: "/").map(String.init) {
            current.appendPathComponent(component)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil {
                return true
            }
        }
        return false
    }

    public static func gitTemporaryPackDecision(
        path: String,
        home: String,
        gitProcessChecker: () -> Bool
    ) -> SafetyDecision {
        guard path.hasPrefix(home + "/") else {
            return SafetyDecision(allowed: false, reason: "Git temporary pack is outside the current user's home directory.")
        }

        guard !containsSymlinkComponent(path: path, home: home) else {
            return SafetyDecision(allowed: false, reason: "Refusing Git temporary pack with symlink component.")
        }

        let url = URL(fileURLWithPath: path)
        let packDirectory = url.deletingLastPathComponent()
        let objectsDirectory = packDirectory.deletingLastPathComponent()
        let gitDirectory = objectsDirectory.deletingLastPathComponent()

        guard url.lastPathComponent.hasPrefix("tmp_pack_") else {
            return SafetyDecision(allowed: false, reason: "Git temp-pack filename must start with tmp_pack_.")
        }
        guard packDirectory.lastPathComponent == "pack",
              objectsDirectory.lastPathComponent == "objects",
              gitDirectory.lastPathComponent == ".git" else {
            return SafetyDecision(allowed: false, reason: "Git temp-pack file must be directly under .git/objects/pack/.")
        }

        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]), values.isRegularFile == true else {
            return SafetyDecision(allowed: false, reason: "Git temp-pack candidate is not a regular file.")
        }

        if let modified = values.contentModificationDate, Date().timeIntervalSince(modified) < gitTempPackMinimumAge {
            return SafetyDecision(allowed: false, reason: "Git temp-pack file is too recent; it may belong to an active operation.")
        }

        if packDirectoryContainsLockFile(packDirectory) {
            return SafetyDecision(allowed: false, reason: "Git pack directory contains a lock file. Try again later.")
        }

        if gitProcessChecker() {
            return SafetyDecision(allowed: false, reason: "Git process is running. Try again later.")
        }

        return SafetyDecision(allowed: true, reason: "Strictly validated abandoned Git tmp_pack file.")
    }

    public static func packDirectoryContainsLockFile(_ directory: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        return names.contains { $0.hasSuffix(".lock") }
    }

    public static func gitProcessIsRunning() -> Bool {
        let result = Shell.run("/usr/bin/pgrep", ["-f", "[g]it|[g]it-remote|[g]it-lfs"], timeout: 3)
        return result.status == 0
    }
}
