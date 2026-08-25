import Foundation

public enum AdapterDisposition: String, Codable, Hashable, Sendable {
    case actionable = "Actionable"
    case review = "Review required"
    case protected = "Protected"
    case unknown = "Unknown"
}

public struct HomebrewLayoutEvidence: Codable, Hashable, Sendable {
    public var prefix: String
    public var stagingRoot: String
    public var installedRoots: [String]
    public var managerExecutable: String
    public var managerAvailable: Bool
    public var managerIdentityVerified: Bool

    public init(prefix: String, stagingRoot: String, installedRoots: [String], managerExecutable: String, managerAvailable: Bool, managerIdentityVerified: Bool) {
        self.prefix = SafetyEngine.lexicalNormalize(prefix)
        self.stagingRoot = SafetyEngine.lexicalNormalize(stagingRoot)
        self.installedRoots = installedRoots.map(SafetyEngine.lexicalNormalize)
        self.managerExecutable = managerExecutable
        self.managerAvailable = managerAvailable
        self.managerIdentityVerified = managerIdentityVerified
    }
}

public struct HomebrewStagingFinding: Codable, Hashable, Sendable {
    public var path: String
    public var disposition: AdapterDisposition
    public var reason: String
    public var evidence: CandidateEvidenceBundle?

    public var scanItem: ScanItem {
        let allowed = disposition == .actionable && evidence?.isActionable == true
        return ScanItem(
            manifestID: evidence?.candidateID,
            path: path,
            displayName: "Homebrew staging item",
            group: "Homebrew",
            category: .packageCache,
            risk: allowed ? .safe : (disposition == .protected ? .protected : .auditOnly),
            sizeBytes: evidence?.identity.sizeBytes ?? 0,
            explanation: reason,
            recoveryNote: "Homebrew may recreate verified staging content; installed Cellar and Caskroom state remains protected.",
            action: allowed ? .moveToTrash : .auditOnly,
            isSelected: false,
            measuredAt: Date(),
            measurementSource: evidence == nil ? .notMeasured : .fresh,
            evidence: evidence
        )
    }
}

public enum HomebrewStagingAdapter {
    public static let adapterVersion = "1.0.0"
    public static let ruleID = "homebrew.verified-staging"
    public static let adapterChecksum = StableFingerprint.fnv1a("homebrew|verified-prefix|exact-staging-child|installed-roots-protected|inactive|closed|v1")

    public static var provenance: RuleProvenance {
        RuleProvenance(ruleID: ruleID, ruleVersion: adapterVersion, sourceKind: .dedicatedAdapter, sourceVersion: adapterVersion, sourceChecksum: adapterChecksum)
    }

    public static func analyze(candidate: URL, layout: HomebrewLayoutEvidence, managerActive: Bool, openState: ExactOpenFileState, allowCleanup: Bool) -> HomebrewStagingFinding {
        let path = SafetyEngine.lexicalNormalize(candidate.path)
        let staging = layout.stagingRoot
        let prefix = layout.prefix
        func finding(_ disposition: AdapterDisposition, _ reason: String) -> HomebrewStagingFinding {
            HomebrewStagingFinding(path: path, disposition: disposition, reason: reason, evidence: nil)
        }
        guard layout.managerAvailable, layout.managerIdentityVerified else { return finding(.unknown, "Homebrew or its current prefix/layout identity could not be verified.") }
        guard staging.hasPrefix(prefix + "/"), path.hasPrefix(staging + "/"), path != staging else { return finding(.protected, "Only an exact descendant of the verified Homebrew staging root can be considered.") }
        guard !layout.installedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return finding(.protected, "Installed Homebrew Cellar/Caskroom/package state is protected.") }
        guard !SafetyEngine.containsSymlinkComponent(path: path, home: prefix) else { return finding(.protected, "Symlinked Homebrew state is protected.") }
        guard managerActive == false else { return finding(.protected, "An active Homebrew operation blocks staging cleanup.") }
        switch openState {
        case .closed: break
        case .inUse: return finding(.protected, "An open handle blocks staging cleanup.")
        case .unavailable: return finding(.unknown, "Open-file state is unavailable; the adapter fails closed.")
        }
        guard let identity = FileIdentity.capture(path: path) else { return finding(.unknown, "The exact staging candidate identity is unavailable.") }
        let candidateID = "adapter:\(ruleID):\(StableFingerprint.fnv1a(path))"
        let observed = Date()
        let evidence = CandidateEvidenceBundle(
            candidateID: candidateID,
            path: path,
            identity: identity,
            ownership: .userScoped,
            protection: allowCleanup ? .actionable : .review,
            rebuildability: .proven,
            risk: allowCleanup ? .safe : .auditOnly,
            records: [
                CandidateEvidenceRecord(kind: .identity, source: "FileManager attributes", observedAt: observed, completeness: .complete, detail: "Captured the exact staging object identity."),
                CandidateEvidenceRecord(kind: .authority, source: layout.managerExecutable, observedAt: observed, completeness: .complete, detail: "Verified Homebrew prefix and exact staging root; no broad package-manager root authority was granted."),
                CandidateEvidenceRecord(kind: .protection, source: "Homebrew layout", observedAt: observed, completeness: .complete, detail: "Installed Cellar, Caskroom, and package roots were excluded."),
                CandidateEvidenceRecord(kind: .activeUse, source: "Process and open-file checks", observedAt: observed, completeness: .complete, detail: "No active Homebrew operation or open handle was observed."),
                CandidateEvidenceRecord(kind: .rebuildability, source: "Homebrew staging semantics", observedAt: observed, completeness: .complete, detail: "The verified staging item is manager-created transient state, not an installed capability.")
            ],
            provenance: provenance
        )
        return HomebrewStagingFinding(path: path, disposition: allowCleanup ? .actionable : .review, reason: allowCleanup ? "Exact Homebrew staging proof passed; Preview and final preflight remain required." : "Exact staging proof passed in read-only mode.", evidence: evidence)
    }
}

public enum HomebrewSafetyAdapter {
    public static func decision(path: String, manifestID: String, evidence: CandidateEvidenceBundle?, identity: FileIdentity? = nil, home: String) -> SafetyDecision {
        guard let evidence,
              evidence.provenance == HomebrewStagingAdapter.provenance,
              evidence.candidateID == manifestID,
              evidence.path == path,
              evidence.isActionable else { return SafetyDecision(allowed: false, reason: "Homebrew staging evidence is missing, incomplete, or stale.") }
        if let identity, evidence.identity != identity { return SafetyDecision(allowed: false, reason: "Homebrew staging identity changed after preview.") }
        guard !SafetyEngine.containsSymlinkComponent(path: path, home: home) else { return SafetyDecision(allowed: false, reason: "Homebrew staging path gained a symlink component.") }
        guard !ProcessDetector.homebrewOperationIsRunning() else { return SafetyDecision(allowed: false, reason: "An active Homebrew operation blocks cleanup.") }
        return SafetyDecision(allowed: true, reason: "Verified Homebrew staging evidence and current inactive-manager state still match.")
    }
}

public enum ManagedOwnershipKind: String, Codable, Hashable, Sendable {
    case fileProvider = "FileProvider"
    case iCloud = "iCloud or CloudDocs"
    case cloudStorage = "CloudStorage provider"
    case providerState = "DriveFS, Dropbox, or OneDrive state"
    case systemService = "System service state"
    case unmanaged = "No managed ownership detected"
}

public struct ManagedResourceClassification: Codable, Hashable, Sendable {
    public var kind: ManagedOwnershipKind
    public var protection: ProtectionDecision
    public var reason: String
}

public enum ManagedResourceClassifier {
    public static func classify(path: String) -> ManagedResourceClassification {
        let normalized = SafetyEngine.lexicalNormalize(path)
        let components = normalized.lowercased().split(separator: "/").map(String.init)
        let joined = components.joined(separator: "/")
        let match: (ManagedOwnershipKind, String)?
        if joined.contains("fileprovider") || joined.contains("fpck") { match = (.fileProvider, "FileProvider/FPCK-managed state is protected regardless of size or age.") }
        else if joined.contains("mobile documents") || joined.contains("clouddocs") { match = (.iCloud, "iCloud/CloudDocs-managed state is protected.") }
        else if joined.contains("cloudstorage") { match = (.cloudStorage, "CloudStorage provider-managed state is protected.") }
        else if joined.contains("drivefs") || components.contains(where: { $0 == "dropbox" || $0 == "onedrive" }) { match = (.providerState, "Cloud provider coordination state is protected.") }
        else if joined.contains("library/daemon") || joined.contains("system/library") { match = (.systemService, "System service state is protected.") }
        else { match = nil }
        guard let match else { return ManagedResourceClassification(kind: .unmanaged, protection: .review, reason: "No managed ownership marker was detected; separate authority is still required.") }
        return ManagedResourceClassification(kind: match.0, protection: .protected, reason: match.1)
    }
}
