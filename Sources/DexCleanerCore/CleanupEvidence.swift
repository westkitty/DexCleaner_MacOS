import Foundation

public enum EvidenceSchema {
    public static let currentVersion = "1.0.0"
}

public enum ReportSchema {
    public static let currentVersion = "2.0.0"
}

public enum EvidenceCompletenessState: String, Codable, Hashable, Sendable {
    case complete = "Complete"
    case partial = "Partial"
    case unavailable = "Unavailable"
}

public enum CandidateEvidenceKind: String, Codable, Hashable, Sendable {
    case identity = "Filesystem identity"
    case authority = "Cleanup authority"
    case ownership = "Ownership"
    case rebuildability = "Rebuildability"
    case protection = "Protection"
    case activeUse = "Active use"
    case measurement = "Measurement"
}

public enum OwnershipDecision: String, Codable, Hashable, Sendable {
    case userScoped = "User scoped"
    case managed = "System or provider managed"
    case shared = "Shared"
    case unknown = "Unknown"
}

public enum ProtectionDecision: String, Codable, Hashable, Sendable {
    case actionable = "Actionable"
    case review = "Review required"
    case protected = "Protected"
    case unknown = "Unknown"
}

public enum RebuildabilityDecision: String, Codable, Hashable, Sendable {
    case proven = "Proven rebuildable"
    case restorable = "Proven restorable"
    case notRebuildable = "Not rebuildable"
    case unknown = "Unknown"
}

public enum RuleSourceKind: String, Codable, Hashable, Sendable {
    case declarativeManifest = "Declarative manifest"
    case dedicatedAdapter = "Dedicated adapter"
}

public struct RuleProvenance: Codable, Hashable, Sendable {
    public var ruleID: String
    public var ruleVersion: String
    public var sourceKind: RuleSourceKind
    public var sourceVersion: String
    public var sourceChecksum: String

    public init(ruleID: String, ruleVersion: String, sourceKind: RuleSourceKind, sourceVersion: String, sourceChecksum: String) {
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.sourceKind = sourceKind
        self.sourceVersion = sourceVersion
        self.sourceChecksum = sourceChecksum
    }

    public var isComplete: Bool {
        !ruleID.isEmpty && !ruleVersion.isEmpty && !sourceVersion.isEmpty && !sourceChecksum.isEmpty && sourceChecksum != "unavailable"
    }
}

public struct CandidateEvidenceRecord: Codable, Hashable, Sendable {
    public var kind: CandidateEvidenceKind
    public var source: String
    public var observedAt: Date
    public var completeness: EvidenceCompletenessState
    public var detail: String

    public init(kind: CandidateEvidenceKind, source: String, observedAt: Date, completeness: EvidenceCompletenessState, detail: String) {
        self.kind = kind
        self.source = source
        self.observedAt = observedAt
        self.completeness = completeness
        self.detail = detail
    }
}

public struct CandidateEvidenceBundle: Codable, Hashable, Sendable {
    public var schemaVersion: String
    public var candidateID: String
    public var path: String
    public var identity: FileIdentity
    public var ownership: OwnershipDecision
    public var protection: ProtectionDecision
    public var rebuildability: RebuildabilityDecision
    public var risk: RiskLevel
    public var records: [CandidateEvidenceRecord]
    public var provenance: RuleProvenance
    public var fingerprint: String
    public var redacted: Bool

    public init(
        schemaVersion: String = EvidenceSchema.currentVersion,
        candidateID: String,
        path: String,
        identity: FileIdentity,
        ownership: OwnershipDecision,
        protection: ProtectionDecision,
        rebuildability: RebuildabilityDecision,
        risk: RiskLevel,
        records: [CandidateEvidenceRecord],
        provenance: RuleProvenance,
        redacted: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.candidateID = candidateID
        self.path = path
        self.identity = identity
        self.ownership = ownership
        self.protection = protection
        self.rebuildability = rebuildability
        self.risk = risk
        self.records = records
        self.provenance = provenance
        self.redacted = redacted
        self.fingerprint = ""
        self.fingerprint = calculatedFingerprint
    }

    public var isActionable: Bool {
        actionabilityProblems.isEmpty
    }

    public var actionabilityProblems: [String] {
        var problems: [String] = []
        if redacted { problems.append("evidence is redacted") }
        if schemaVersion != EvidenceSchema.currentVersion { problems.append("evidence schema is unsupported") }
        if ownership != .userScoped { problems.append("ownership is not user-scoped") }
        if protection != .actionable { problems.append("protection decision is not actionable") }
        if rebuildability != .proven { problems.append("rebuildability is not proven") }
        if risk != .safe { problems.append("risk is not Safe") }
        if records.isEmpty { problems.append("evidence records are missing") }
        if records.contains(where: { $0.completeness != .complete }) { problems.append("evidence is incomplete") }
        if !provenance.isComplete { problems.append("rule provenance is incomplete") }
        if fingerprint != calculatedFingerprint { problems.append("evidence fingerprint does not match") }
        return problems
    }

    public var calculatedFingerprint: String {
        let fileNumberText = identity.fileNumber.map { String($0) } ?? "none"
        let systemNumberText = identity.systemNumber.map { String($0) } ?? "none"
        let modificationTimeText = identity.modificationTime.map { String($0) } ?? "none"
        let identityText = [
            fileNumberText,
            systemNumberText,
            identity.fileType,
            String(identity.sizeBytes),
            modificationTimeText
        ].joined(separator: "|")
        let evidenceText = records
            .map { [$0.kind.rawValue, $0.source, String($0.observedAt.timeIntervalSince1970), $0.completeness.rawValue, $0.detail].joined(separator: "|") }
            .sorted()
            .joined(separator: "\n")
        let canonical = [
            schemaVersion, candidateID, SafetyEngine.lexicalNormalize(path), identityText,
            ownership.rawValue, protection.rawValue, rebuildability.rawValue, risk.rawValue,
            provenance.ruleID, provenance.ruleVersion, provenance.sourceKind.rawValue,
            provenance.sourceVersion, provenance.sourceChecksum, evidenceText
        ].joined(separator: "\n")
        return StableFingerprint.fnv1a(canonical)
    }

    public func redactedCopy(home: String) -> CandidateEvidenceBundle {
        let normalizedHome = SafetyEngine.lexicalNormalize(home)
        func redact(_ value: String) -> String {
            value.replacingOccurrences(of: normalizedHome, with: "~").replacingOccurrences(of: home, with: "~")
        }
        var copy = self
        copy.path = redact(path)
        copy.records = records.map {
            var record = $0
            record.detail = redact(record.detail)
            return record
        }
        copy.redacted = true
        return copy
    }
}

public enum CandidateEvidenceFactory {
    public static func forCandidate(
        item: ScanItem,
        identity: FileIdentity,
        home: String,
        observedAt: Date = Date()
    ) -> CandidateEvidenceBundle? {
        if let evidence = item.evidence,
           evidence.provenance.sourceKind == .dedicatedAdapter,
           evidence.identity == identity,
           evidence.candidateID == item.manifestID,
           SafetyEngine.lexicalNormalize(evidence.path) == SafetyEngine.lexicalNormalize(item.path),
           evidence.isActionable {
            return evidence
        }
        return exactManifest(item: item, identity: identity, home: home, observedAt: observedAt)
    }

    public static func exactManifest(
        item: ScanItem,
        identity: FileIdentity,
        home: String,
        observedAt: Date = Date()
    ) -> CandidateEvidenceBundle? {
        guard let manifestID = item.manifestID,
              let entry = CleanupCatalog.entry(forManifestID: manifestID),
              SafetyEngine.lexicalNormalize(item.path) == CleanupCatalog.exactPath(for: entry, home: home) else { return nil }
        let records = [
            CandidateEvidenceRecord(kind: .identity, source: "FileManager attributes", observedAt: observedAt, completeness: .complete, detail: "Captured filesystem object identity for the exact candidate path."),
            CandidateEvidenceRecord(kind: .authority, source: "CleanupManifest.json", observedAt: observedAt, completeness: .complete, detail: "Manifest rule \(manifestID) matched the exact canonical path."),
            CandidateEvidenceRecord(kind: .ownership, source: "Home scope", observedAt: observedAt, completeness: .complete, detail: "Candidate is inside the current user's home and outside protected broad roots."),
            CandidateEvidenceRecord(kind: .rebuildability, source: "CleanupManifest.json", observedAt: observedAt, completeness: .complete, detail: entry.recoveryNote),
            CandidateEvidenceRecord(kind: .protection, source: "SafetyEngine", observedAt: observedAt, completeness: .complete, detail: "No protected fragment or symlink component was found.")
        ]
        return CandidateEvidenceBundle(
            candidateID: manifestID,
            path: item.path,
            identity: identity,
            ownership: .userScoped,
            protection: .actionable,
            rebuildability: .proven,
            risk: item.risk,
            records: records,
            provenance: CleanupCatalog.provenance(for: entry)
        )
    }
}

public enum StableFingerprint {
    public static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
