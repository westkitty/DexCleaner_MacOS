import Foundation

public enum CapabilityEcosystem: String, Codable, Hashable, Sendable {
    case gradle = "Gradle or Android"
    case xcode = "Xcode"
    case kotlinNative = "Kotlin Native"
    case python = "Python"
    case aiModel = "AI model store"
    case toolchain = "Compiler or toolchain"
}

public enum CapabilityRole: String, Codable, Hashable, Sendable {
    case generatedProjectOutput = "Generated project output"
    case globalCache = "Global cache"
    case installedCapability = "Installed capability"
    case sharedBlobStore = "Shared blob store"
    case unknown = "Unknown role"
}

public struct CapabilityFinding: Codable, Hashable, Sendable {
    public var path: String
    public var ecosystem: CapabilityEcosystem
    public var role: CapabilityRole
    public var disposition: AdapterDisposition
    public var reason: String
    public var active: Bool
    public var projectReferenced: Bool
}

public enum CapabilityClassifier {
    public static func classify(path: String, ecosystem: CapabilityEcosystem, role: CapabilityRole, active: Bool = false, isDefault: Bool = false, projectReferenced: Bool = false) -> CapabilityFinding {
        let normalized = SafetyEngine.lexicalNormalize(path)
        if role == .sharedBlobStore { return CapabilityFinding(path: normalized, ecosystem: ecosystem, role: role, disposition: .protected, reason: "Shared blobs may back multiple models or installations; naive per-directory cleanup is forbidden.", active: active, projectReferenced: projectReferenced) }
        if active || isDefault || projectReferenced { return CapabilityFinding(path: normalized, ecosystem: ecosystem, role: role, disposition: .protected, reason: "Active, default, or project-referenced capability is protected.", active: active, projectReferenced: projectReferenced) }
        if role == .installedCapability { return CapabilityFinding(path: normalized, ecosystem: ecosystem, role: role, disposition: .review, reason: "Installed models, SDKs, runtimes, environments, archives, and toolchains are capabilities, not mere old files.", active: active, projectReferenced: projectReferenced) }
        if role == .generatedProjectOutput { return CapabilityFinding(path: normalized, ecosystem: ecosystem, role: role, disposition: .review, reason: "Generated semantics are plausible, but this ecosystem has no cleanup authority adapter yet.", active: active, projectReferenced: projectReferenced) }
        return CapabilityFinding(path: normalized, ecosystem: ecosystem, role: role, disposition: .unknown, reason: "Ownership or rebuildability is incomplete; review only.", active: active, projectReferenced: projectReferenced)
    }
}
