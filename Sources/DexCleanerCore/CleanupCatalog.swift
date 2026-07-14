import Foundation

public struct CatalogEntry: Hashable, Codable, Sendable {
    public var id: String
    public var relativePath: String
    public var displayName: String
    public var group: String
    public var category: CleanupCategory
    public var risk: RiskLevel
    public var explanation: String
    public var recoveryNote: String
    public var defaultSelected: Bool

    public init(
        id: String,
        relativePath: String,
        displayName: String,
        group: String,
        category: CleanupCategory,
        risk: RiskLevel,
        explanation: String,
        recoveryNote: String,
        defaultSelected: Bool = false
    ) {
        self.id = id
        self.relativePath = relativePath
        self.displayName = displayName
        self.group = group
        self.category = category
        self.risk = risk
        self.explanation = explanation
        self.recoveryNote = recoveryNote
        self.defaultSelected = defaultSelected
    }

    public var action: CleanupAction { risk == .safe ? .moveToTrash : .auditOnly }
}

public struct CleanupManifest: Codable, Sendable {
    public var version: String
    public var name: String
    public var policy: String
    public var safeExactTargets: [CatalogEntry]
    public var forbiddenFragments: [String]

    public init(version: String, name: String, policy: String, safeExactTargets: [CatalogEntry], forbiddenFragments: [String]) {
        self.version = version
        self.name = name
        self.policy = policy
        self.safeExactTargets = safeExactTargets
        self.forbiddenFragments = forbiddenFragments
    }
}

public struct ManifestLoadResult: Sendable {
    public var manifest: CleanupManifest?
    public var checksum: String
    public var errors: [String]

    public init(manifest: CleanupManifest?, checksum: String, errors: [String]) {
        self.manifest = manifest
        self.checksum = checksum
        self.errors = errors
    }
}

public enum ManifestValidator {
    private static let forbiddenBroadRoots: Set<String> = [
        ".cache", ".Trash", "Applications", "Developer", "Library",
        "Library/Caches", "Library/Application Support", "Library/CloudStorage",
        "Library/Developer", "Library/Developer/Xcode", "Library/Developer/Xcode/DerivedData",
        "Desktop", "Documents", "Downloads", "Movies", "Pictures", "Projects"
    ]

    public static func validate(_ manifest: CleanupManifest) -> [String] {
        var errors: [String] = []
        validateRequiredText(manifest.version, name: "Manifest version", errors: &errors)
        validateRequiredText(manifest.name, name: "Manifest name", errors: &errors)
        validateRequiredText(manifest.policy, name: "Manifest policy", errors: &errors)
        if manifest.safeExactTargets.isEmpty { errors.append("Manifest contains no exact targets.") }

        var seenFragments = Set<String>()
        for fragment in manifest.forbiddenFragments {
            if fragment.isEmpty || fragment != fragment.trimmingCharacters(in: .whitespacesAndNewlines) {
                errors.append("Manifest contains an empty or whitespace-padded forbidden fragment.")
            }
            if !fragment.hasPrefix("/") {
                errors.append("Forbidden fragment must begin with '/': \(fragment).")
            }
            if !seenFragments.insert(fragment).inserted {
                errors.append("Duplicate forbidden fragment: \(fragment).")
            }
        }

        var seenIDs = Set<String>()
        var seenPaths = Set<String>()
        var canonicalPaths: [String?] = []

        for (index, entry) in manifest.safeExactTargets.enumerated() {
            let id = entry.id
            if id.isEmpty || id != id.trimmingCharacters(in: .whitespacesAndNewlines) {
                errors.append("Target at index \(index) has an empty or whitespace-padded id.")
            }
            if !seenIDs.insert(id).inserted { errors.append("Duplicate manifest id: \(id).") }

            let canonicalPath = canonicalRelativePath(entry.relativePath)
            canonicalPaths.append(canonicalPath)
            guard let path = canonicalPath else {
                errors.append("Target \(id) has an invalid canonical relative path: \(entry.relativePath).")
                continue
            }
            if !seenPaths.insert(path).inserted { errors.append("Duplicate manifest path: \(path).") }
            if forbiddenBroadRoots.contains(path) { errors.append("Target \(id) is a forbidden broad root: \(path).") }
            let rootedPath = "/" + path
            for fragment in manifest.forbiddenFragments where rootedPath.contains(fragment) {
                errors.append("Target \(id) conflicts with forbidden fragment \(fragment).")
            }
            if entry.risk != .safe { errors.append("Cleanup authority manifest target \(id) is not Safe.") }
            if entry.defaultSelected { errors.append("Target \(id) must not be selected by default.") }

            validateRequiredText(entry.displayName, name: "Target \(id) displayName", errors: &errors)
            validateRequiredText(entry.group, name: "Target \(id) group", errors: &errors)
            validateRequiredText(entry.explanation, name: "Target \(id) explanation", errors: &errors)
            validateRequiredText(entry.recoveryNote, name: "Target \(id) recoveryNote", errors: &errors)
        }

        let paths = canonicalPaths.compactMap { $0 }
        for leftIndex in paths.indices {
            for rightIndex in paths.indices where rightIndex > leftIndex {
                let left = paths[leftIndex]
                let right = paths[rightIndex]
                if left.hasPrefix(right + "/") || right.hasPrefix(left + "/") {
                    errors.append("Overlapping manifest paths: \(left) and \(right).")
                }
            }
        }
        return errors
    }

    public static func canonicalRelativePath(_ rawPath: String) -> String? {
        guard !rawPath.isEmpty,
              rawPath == rawPath.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.hasPrefix("/") else { return nil }
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        let canonical = components.joined(separator: "/")
        guard canonical == rawPath else { return nil }
        return canonical
    }

    private static func validateRequiredText(_ value: String, name: String, errors: inout [String]) {
        if value.isEmpty || value != value.trimmingCharacters(in: .whitespacesAndNewlines) {
            errors.append("\(name) is empty or whitespace-padded.")
        }
    }
}

public enum CleanupCatalog {
    public static let loadResult: ManifestLoadResult = loadManifest()
    public static var manifest: CleanupManifest? { loadResult.manifest }
    public static var isAvailable: Bool { manifest != nil && loadResult.errors.isEmpty }
    public static var validationErrors: [String] { loadResult.errors }
    public static var exactSafeEntries: [CatalogEntry] { manifest?.safeExactTargets ?? [] }
    public static var cleanableEntries: [CatalogEntry] { isAvailable ? exactSafeEntries : [] }
    public static var policyVersion: String { manifest?.version ?? "unavailable" }
    public static var manifestChecksum: String { loadResult.checksum }
    public static var forbiddenFragments: [String] { manifest?.forbiddenFragments ?? conservativeForbiddenFragments }

    public static func exactAllowedPaths(home: String = NSHomeDirectory()) -> Set<String> {
        guard isAvailable else { return [] }
        let homeURL = URL(fileURLWithPath: home).standardizedFileURL
        return Set(cleanableEntries.map { SafetyEngine.lexicalNormalize(homeURL.appendingPathComponent($0.relativePath).path) })
    }

    public static func entry(forManifestID manifestID: String) -> CatalogEntry? {
        cleanableEntries.first { $0.id == manifestID }
    }

    public static func exactPath(for entry: CatalogEntry, home: String = NSHomeDirectory()) -> String {
        SafetyEngine.lexicalNormalize(URL(fileURLWithPath: home).appendingPathComponent(entry.relativePath).path)
    }

    private static func loadManifest() -> ManifestLoadResult {
        guard let url = Bundle.module.url(forResource: "CleanupManifest", withExtension: "json") else {
            return ManifestLoadResult(manifest: nil, checksum: "unavailable", errors: ["Bundled cleanup manifest is missing. Cleanup is disabled."])
        }
        do {
            let data = try Data(contentsOf: url)
            let checksum = stableChecksum(data)
            let manifest = try JSONDecoder().decode(CleanupManifest.self, from: data)
            let errors = ManifestValidator.validate(manifest)
            guard errors.isEmpty else { return ManifestLoadResult(manifest: nil, checksum: checksum, errors: errors) }
            return ManifestLoadResult(manifest: manifest, checksum: checksum, errors: [])
        } catch {
            return ManifestLoadResult(manifest: nil, checksum: "unavailable", errors: ["Cleanup manifest could not be decoded: \(error.localizedDescription). Cleanup is disabled."])
        }
    }

    private static func stableChecksum(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static let conservativeForbiddenFragments = [
        "/.cache", "/.antigravity", "/.antigravity_archive", "/Antigravity",
        "/Local Storage", "/Session Storage", "/IndexedDB", "/Service Worker",
        "/User/globalStorage", "/User/workspaceStorage", "/User/History",
        "/Library/Keychains", "/Library/CloudStorage", "/iCloud Drive", "/Dropbox",
        "/OneDrive", "/Google Drive", "/Projects", "/Documents", "/Downloads",
        "/Movies", "/Pictures"
    ]
}
