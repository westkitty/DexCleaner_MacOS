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
    public static func decision(for item: ScanItem, home: String = NSHomeDirectory()) -> SafetyDecision {
        guard CleanupCatalog.isAvailable else {
            return SafetyDecision(allowed: false, reason: "Cleanup authority manifest is unavailable or invalid.")
        }
        let path = lexicalNormalize(item.path)
        let homePath = lexicalNormalize(home)

        guard item.action == .moveToTrash else { return SafetyDecision(allowed: false, reason: "Audit-only item cannot be cleaned.") }
        guard item.risk == .safe else { return SafetyDecision(allowed: false, reason: "Only Safe items can be moved to Trash.") }
        guard path != homePath && path != "/" else { return SafetyDecision(allowed: false, reason: "Refusing home or root path.") }
        guard path.hasPrefix(homePath + "/") else { return SafetyDecision(allowed: false, reason: "Path is outside the current user's home directory.") }

        let broadRoots = [
            homePath + "/.cache", homePath + "/Library/Caches", homePath + "/Library/Application Support",
            homePath + "/Library", homePath + "/Projects", homePath + "/Developer",
            homePath + "/Documents", homePath + "/Downloads", homePath + "/Movies",
            homePath + "/Pictures", homePath + "/Desktop"
        ]
        guard !broadRoots.contains(path) else { return SafetyDecision(allowed: false, reason: "Refusing broad root path.") }

        for fragment in CleanupCatalog.forbiddenFragments where path.localizedCaseInsensitiveContains(fragment) {
            return SafetyDecision(allowed: false, reason: "Protected state, session, cloud, project, or user-data path: \(fragment)")
        }
        guard !containsSymlinkComponent(path: path, home: homePath) else {
            return SafetyDecision(allowed: false, reason: "Refusing path with a symlink component.")
        }
        guard CleanupCatalog.exactAllowedPaths(home: homePath).contains(path) else {
            return SafetyDecision(allowed: false, reason: "Path is not an exact manifest allowlist target.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return SafetyDecision(allowed: false, reason: "Target no longer exists.")
        }
        guard FileIdentity.capture(path: path) != nil else {
            return SafetyDecision(allowed: false, reason: "Target identity could not be read.")
        }
        return SafetyDecision(allowed: true, reason: "Exact manifest-approved regeneratable cache path.")
    }

    public static func decision(for planItem: CleanupPlanItem, home: String = NSHomeDirectory()) -> SafetyDecision {
        guard planItem.risk == .safe, planItem.action == .moveToTrash else {
            return SafetyDecision(allowed: false, reason: "Previewed target no longer carries Safe Trash-only authority.")
        }
        guard let entry = CleanupCatalog.entry(forManifestID: planItem.manifestID) else {
            return SafetyDecision(allowed: false, reason: "Manifest entry no longer exists.")
        }
        let expectedPath = CleanupCatalog.exactPath(for: entry, home: home)
        guard lexicalNormalize(planItem.path) == expectedPath else {
            return SafetyDecision(allowed: false, reason: "Manifest ID and exact target path no longer match.")
        }
        let item = ScanItem(
            manifestID: entry.id,
            path: planItem.path,
            displayName: planItem.displayName,
            group: entry.group,
            category: entry.category,
            risk: entry.risk,
            sizeBytes: planItem.sizeBytes,
            explanation: entry.explanation,
            recoveryNote: entry.recoveryNote,
            action: entry.action,
            isSelected: true
        )
        let base = decision(for: item, home: home)
        guard base.allowed else { return base }
        guard let current = FileIdentity.capture(path: planItem.path), current == planItem.identity else {
            return SafetyDecision(allowed: false, reason: "Target identity changed after preview. Run a new scan and preview.")
        }
        return SafetyDecision(allowed: true, reason: "Previewed target identity and manifest authority still match.")
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
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil { return true }
        }
        return false
    }
}
