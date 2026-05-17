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
        group: String = "Ungrouped",
        category: CleanupCategory,
        risk: RiskLevel = .safe,
        explanation: String,
        recoveryNote: String = "Regeneratable cache. If needed, rerun the owning tool or app.",
        defaultSelected: Bool
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.group = try container.decodeIfPresent(String.self, forKey: .group) ?? "Ungrouped"
        self.category = try container.decode(CleanupCategory.self, forKey: .category)
        self.risk = try container.decodeIfPresent(RiskLevel.self, forKey: .risk) ?? .safe
        self.explanation = try container.decode(String.self, forKey: .explanation)
        self.recoveryNote = try container.decodeIfPresent(String.self, forKey: .recoveryNote) ?? "Regeneratable cache. If needed, rerun the owning tool or app."
        self.defaultSelected = try container.decodeIfPresent(Bool.self, forKey: .defaultSelected) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case relativePath
        case displayName
        case group
        case category
        case risk
        case explanation
        case recoveryNote
        case defaultSelected
    }

    public var action: CleanupAction {
        risk == .safe ? .moveToTrash : .auditOnly
    }
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

public enum CleanupCatalog {
    public static let manifest: CleanupManifest = loadManifest()

    /// Historical name retained for compatibility. This now includes Safe, Caution, Audit only, and Forbidden manifest targets.
    public static var exactSafeEntries: [CatalogEntry] {
        manifest.safeExactTargets
    }

    public static var cleanableEntries: [CatalogEntry] {
        manifest.safeExactTargets.filter { $0.risk == .safe }
    }

    public static var auditOnlyEntries: [CatalogEntry] {
        manifest.safeExactTargets.filter { $0.risk != .safe }
    }

    public static var policyVersion: String {
        manifest.version
    }

    public static var forbiddenFragments: [String] {
        manifest.forbiddenFragments
    }

    public static func exactAllowedPaths(home: String = NSHomeDirectory()) -> Set<String> {
        let homeURL = URL(fileURLWithPath: home).standardizedFileURL
        return Set(cleanableEntries.map { entry in
            SafetyEngine.lexicalNormalize(homeURL.appendingPathComponent(entry.relativePath).path)
        })
    }

    public static func entry(forManifestID manifestID: String) -> CatalogEntry? {
        manifest.safeExactTargets.first { $0.id == manifestID }
    }

    public static func entries(groupedBy group: String) -> [CatalogEntry] {
        manifest.safeExactTargets.filter { $0.group == group }
    }

    private static func loadManifest() -> CleanupManifest {
        guard let url = Bundle.module.url(forResource: "CleanupManifest", withExtension: "json") else {
            return fallbackManifest
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CleanupManifest.self, from: data)
        } catch {
            return fallbackManifest
        }
    }

    // Emergency fallback only. The bundled JSON manifest is the intended source of truth.
    private static let fallbackManifest = CleanupManifest(
        version: "fallback-3",
        name: "DexCleaner fallback cleanup manifest",
        policy: "Exact canonical allowlist only. Move to Trash. No broad cache roots. No app state/session stores.",
        safeExactTargets: [
            CatalogEntry(id: "homebrew-cache", relativePath: "Library/Caches/Homebrew", displayName: "Homebrew cache", group: "Homebrew", category: .packageCache, risk: .safe, explanation: "Homebrew download/build cache. Regeneratable.", recoveryNote: "Homebrew will re-download packages when needed.", defaultSelected: false),
            CatalogEntry(id: "pip-cache", relativePath: "Library/Caches/pip", displayName: "pip cache", group: "Python", category: .packageCache, risk: .safe, explanation: "Python pip package cache. Regeneratable.", recoveryNote: "pip will re-download packages when needed.", defaultSelected: false),
            CatalogEntry(id: "swiftpm-cache", relativePath: "Library/Caches/org.swift.swiftpm", displayName: "Swift Package Manager cache", group: "Swift", category: .developerCache, risk: .safe, explanation: "SwiftPM dependency cache. Regeneratable.", recoveryNote: "SwiftPM will resolve and fetch packages again.", defaultSelected: false),
            CatalogEntry(id: "npm-cache", relativePath: "Library/Caches/npm", displayName: "npm cache", group: "Node", category: .packageCache, risk: .safe, explanation: "npm cache. Regeneratable.", recoveryNote: "npm will re-download packages when needed.", defaultSelected: false),
            CatalogEntry(id: "pnpm-cache", relativePath: "Library/Caches/pnpm", displayName: "pnpm cache", group: "JavaScript", category: .packageCache, risk: .safe, explanation: "pnpm cache. Regeneratable.", recoveryNote: "pnpm will re-download packages when needed.", defaultSelected: false),
            CatalogEntry(id: "yarn-cache", relativePath: "Library/Caches/Yarn", displayName: "Yarn cache", group: "JavaScript", category: .packageCache, risk: .safe, explanation: "Yarn cache. Regeneratable.", recoveryNote: "Yarn will re-download packages when needed.", defaultSelected: false),
            CatalogEntry(id: "cocoapods-cache", relativePath: "Library/Caches/CocoaPods", displayName: "CocoaPods cache", group: "CocoaPods", category: .packageCache, risk: .safe, explanation: "CocoaPods cache. Regeneratable.", recoveryNote: "CocoaPods will download pods again when needed.", defaultSelected: false),
            CatalogEntry(id: "gradle-cache", relativePath: "Library/Caches/Gradle", displayName: "Gradle cache", group: "Gradle", category: .packageCache, risk: .safe, explanation: "Gradle cache. Regeneratable.", recoveryNote: "Gradle will download dependencies again when needed.", defaultSelected: false),
            CatalogEntry(id: "xcode-cache", relativePath: "Library/Caches/com.apple.dt.Xcode", displayName: "Xcode cache", group: "Xcode", category: .developerCache, risk: .safe, explanation: "Xcode cache. Regeneratable.", recoveryNote: "Xcode will rebuild cache data when needed.", defaultSelected: false),
            CatalogEntry(id: "xcode-module-cache", relativePath: "Library/Developer/Xcode/DerivedData/ModuleCache.noindex", displayName: "Xcode module cache", group: "Xcode", category: .developerCache, risk: .safe, explanation: "Xcode module cache. Regeneratable.", recoveryNote: "Xcode will rebuild module cache data during future builds.", defaultSelected: false),
            CatalogEntry(id: "simulator-cache", relativePath: "Library/Developer/CoreSimulator/Caches", displayName: "CoreSimulator cache", group: "Simulator", category: .developerCache, risk: .safe, explanation: "CoreSimulator cache. Regeneratable.", recoveryNote: "Simulator and Xcode will recreate cache data when needed.", defaultSelected: false),
            CatalogEntry(id: "vscode-cache", relativePath: "Library/Application Support/Code/Cache", displayName: "VS Code cache", group: "VS Code", category: .exactCache, risk: .safe, explanation: "VS Code runtime cache only.", recoveryNote: "VS Code will regenerate cache after launch.", defaultSelected: false),
            CatalogEntry(id: "xcode-deriveddata", relativePath: "Library/Developer/Xcode/DerivedData", displayName: "Xcode DerivedData", group: "Xcode", category: .developerCache, risk: .caution, explanation: "Large developer build artifacts. Review before deleting.", recoveryNote: "Xcode will rebuild, but this may cause long rebuilds.", defaultSelected: false)
        ],
        forbiddenFragments: [
            "/.cache", "/.antigravity", "/.antigravity_archive", "/Antigravity", "/Local Storage", "/Session Storage", "/IndexedDB", "/Service Worker", "/User/globalStorage", "/User/workspaceStorage", "/User/History", "/Library/Keychains", "/Library/CloudStorage", "/iCloud Drive", "/Dropbox", "/OneDrive", "/Google Drive", "/Library/Application Support/BraveSoftware", "/Library/Application Support/Google/DriveFS", "/Library/Application Support/Google/Chrome", "/Library/Application Support/Claude/vm_bundles", "/Projects", "/Documents", "/Downloads", "/Movies", "/Pictures"
        ]
    )
}
