import Foundation

public enum MeasurementSource: String, Codable, Sendable {
    case fresh = "Fresh measurement"
    case cache = "Cached measurement"
    case notMeasured = "Not measured"
}

public enum StorageMeasurementState: String, Codable, Sendable {
    case fresh = "Fresh"
    case cached = "Cached"
    case partial = "Partial"
    case disputed = "Disputed"
    case failed = "Failed"
}

public enum ScanCompleteness: String, Codable, Sendable {
    case complete = "Complete"
    case partial = "Partial"
    case cancelled = "Cancelled"
    case failed = "Failed"
    case notRun = "Not run"
}

public enum ScanIssueKind: String, Codable, Sendable {
    case permission = "Permission limited"
    case timeout = "Timed out"
    case commandFailure = "Command failed"
    case manifest = "Manifest unavailable"
    case cancellation = "Cancelled"
    case filesystem = "Filesystem changed"
    case measurement = "Measurement disagreement"
}

public struct ScanIssue: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: ScanIssueKind
    public var area: String
    public var detail: String

    public init(id: UUID = UUID(), kind: ScanIssueKind, area: String, detail: String) {
        self.id = id
        self.kind = kind
        self.area = area
        self.detail = detail
    }
}

public struct FileIdentity: Hashable, Codable, Sendable {
    public var fileNumber: UInt64?
    public var systemNumber: UInt64?
    public var fileType: String
    public var sizeBytes: Int64
    public var modificationTime: TimeInterval?

    public init(fileNumber: UInt64?, systemNumber: UInt64?, fileType: String, sizeBytes: Int64, modificationTime: TimeInterval?) {
        self.fileNumber = fileNumber
        self.systemNumber = systemNumber
        self.fileType = fileType
        self.sizeBytes = sizeBytes
        self.modificationTime = modificationTime
    }

    public static func capture(path: String) -> FileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let system = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        let type = (attributes[.type] as? FileAttributeType)?.rawValue ?? "unknown"
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
        return FileIdentity(fileNumber: number, systemNumber: system, fileType: type, sizeBytes: size, modificationTime: modified)
    }
}

public struct ScanItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var manifestID: String?
    public var path: String
    public var displayName: String
    public var group: String
    public var category: CleanupCategory
    public var risk: RiskLevel
    public var sizeBytes: Int64
    public var explanation: String
    public var recoveryNote: String
    public var action: CleanupAction
    public var isSelected: Bool
    public var measuredAt: Date?
    public var measurementSource: MeasurementSource
    public var owningProcessRunning: Bool
    public var evidence: CandidateEvidenceBundle?

    public init(
        id: UUID = UUID(),
        manifestID: String? = nil,
        path: String,
        displayName: String,
        group: String = "Ungrouped",
        category: CleanupCategory,
        risk: RiskLevel,
        sizeBytes: Int64,
        explanation: String,
        recoveryNote: String = "No automatic recovery note provided.",
        action: CleanupAction,
        isSelected: Bool,
        measuredAt: Date? = nil,
        measurementSource: MeasurementSource = .notMeasured,
        owningProcessRunning: Bool = false,
        evidence: CandidateEvidenceBundle? = nil
    ) {
        self.id = id
        self.manifestID = manifestID
        self.path = path
        self.displayName = displayName
        self.group = group
        self.category = category
        self.risk = risk
        self.sizeBytes = sizeBytes
        self.explanation = explanation
        self.recoveryNote = recoveryNote
        self.action = action
        self.isSelected = isSelected
        self.measuredAt = measuredAt
        self.measurementSource = measurementSource
        self.owningProcessRunning = owningProcessRunning
        self.evidence = evidence
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var isCleanable: Bool {
        action == .moveToTrash && risk.allowsSelection
    }
}

public enum CleanupCategory: String, CaseIterable, Codable, Sendable {
    case exactCache = "Exact cache"
    case packageCache = "Package manager cache"
    case developerCache = "Developer cache"
    case gitTemporaryPack = "Git temporary pack"
    case storageMap = "Storage map"
    case extensionBreakdown = "Extension breakdown"
    case permissionDiagnostic = "Permission diagnostic"
    case cloudStorage = "Cloud storage"
    case auditOnly = "Audit only"
    case protected = "Protected"
}

public enum RiskLevel: String, CaseIterable, Codable, Sendable {
    case safe = "Safe"
    case caution = "Caution"
    case auditOnly = "Audit only"
    case forbidden = "Forbidden"
    case protected = "Protected"

    public var allowsSelection: Bool { self == .safe }

    public var sortRank: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .auditOnly: return 2
        case .forbidden: return 3
        case .protected: return 4
        }
    }
}

public enum CleanupAction: String, Codable, Sendable {
    case moveToTrash = "Move exact path to Trash"
    case dryRunOnly = "Dry run only"
    case auditOnly = "Audit only"
}

public enum ReportMode: String, Codable, Sendable {
    case scan = "Scan"
    case dryRun = "Dry run preview"
    case cleanup = "Cleanup"
}

public enum ReportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case markdown = "Markdown"
    case json = "JSON"
    public var id: String { rawValue }
}

public enum PathRedactionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "Full paths"
    case homeRelative = "Redact home path"
    public var id: String { rawValue }
}

public struct CleanupResult: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var path: String
    public var status: String
    public var detail: String
    public var resultingPath: String?

    public init(id: UUID = UUID(), path: String, status: String, detail: String, resultingPath: String? = nil) {
        self.id = id
        self.path = path
        self.status = status
        self.detail = detail
        self.resultingPath = resultingPath
    }
}

public struct CleanupPlanItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let scanItemID: UUID
    public let manifestID: String
    public let path: String
    public let displayName: String
    public let sizeBytes: Int64
    public let identity: FileIdentity
    public let safetyReason: String
    public let risk: RiskLevel
    public let action: CleanupAction
    public let evidence: CandidateEvidenceBundle?

    public init(
        id: UUID = UUID(),
        scanItemID: UUID,
        manifestID: String,
        path: String,
        displayName: String,
        sizeBytes: Int64,
        identity: FileIdentity,
        safetyReason: String,
        risk: RiskLevel = .safe,
        action: CleanupAction = .moveToTrash,
        evidence: CandidateEvidenceBundle? = nil
    ) {
        self.id = id
        self.scanItemID = scanItemID
        self.manifestID = manifestID
        self.path = path
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.identity = identity
        self.safetyReason = safetyReason
        self.risk = risk
        self.action = action
        self.evidence = evidence
    }
}

public struct CleanupPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let manifestVersion: String
    public let manifestChecksum: String
    public let selectionSignature: String
    public let evidenceSignature: String?
    public let sourceScanID: UUID?
    public let sourceScanAt: Date?
    public let campaignID: UUID?
    public let items: [CleanupPlanItem]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        manifestVersion: String,
        manifestChecksum: String,
        selectionSignature: String? = nil,
        evidenceSignature: String? = nil,
        sourceScanID: UUID? = nil,
        sourceScanAt: Date? = nil,
        campaignID: UUID? = nil,
        items: [CleanupPlanItem]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.manifestVersion = manifestVersion
        self.manifestChecksum = manifestChecksum
        self.selectionSignature = selectionSignature ?? Self.signature(for: items)
        self.evidenceSignature = evidenceSignature ?? Self.evidenceSignature(for: items)
        self.sourceScanID = sourceScanID
        self.sourceScanAt = sourceScanAt
        self.campaignID = campaignID
        self.items = items
    }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var expiresAt: Date { createdAt.addingTimeInterval(PreviewAuthorization.maximumPlanAge) }

    public static func signature(for items: [ScanItem]) -> String {
        items.map {
            [
                $0.id.uuidString,
                $0.manifestID ?? "none",
                SafetyEngine.lexicalNormalize($0.path),
                String($0.sizeBytes),
                $0.risk.rawValue,
                $0.action.rawValue
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: "\n")
    }

    public static func signature(for items: [CleanupPlanItem]) -> String {
        items.map {
            [
                $0.scanItemID.uuidString,
                $0.manifestID,
                SafetyEngine.lexicalNormalize($0.path),
                String($0.sizeBytes),
                $0.risk.rawValue,
                $0.action.rawValue
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: "\n")
    }

    public static func evidenceSignature(for items: [CleanupPlanItem]) -> String? {
        let fingerprints = items.compactMap { $0.evidence?.fingerprint }.sorted()
        guard fingerprints.count == items.count, !fingerprints.isEmpty else { return nil }
        return StableFingerprint.fnv1a(fingerprints.joined(separator: "\n"))
    }
}

public struct PreviewOutcome: Sendable {
    public var results: [CleanupResult]
    public var plan: CleanupPlan?

    public init(results: [CleanupResult], plan: CleanupPlan?) {
        self.results = results
        self.plan = plan
    }
}

public struct DiskStatus: Hashable, Codable, Sendable {
    public var filesystem: String
    public var size: String
    public var used: String
    public var available: String
    public var capacity: String
    public var totalBytes: Int64?
    public var immediatelyFreeBytes: Int64?
    public var availableForWorkBytes: Int64?
    public var opportunisticBytes: Int64?
    public var potentiallyPurgeableBytes: Int64?
    public var usedEstimateBytes: Int64?
    public var state: StorageMeasurementState
    public var measuredAt: Date?
    public var source: String
    public var detail: String

    public init(
        filesystem: String = "Unknown",
        size: String = "Unknown",
        used: String = "Unknown",
        available: String = "Unknown",
        capacity: String = "Unknown",
        totalBytes: Int64? = nil,
        immediatelyFreeBytes: Int64? = nil,
        availableForWorkBytes: Int64? = nil,
        opportunisticBytes: Int64? = nil,
        potentiallyPurgeableBytes: Int64? = nil,
        usedEstimateBytes: Int64? = nil,
        state: StorageMeasurementState = .failed,
        measuredAt: Date? = nil,
        source: String = "Unavailable",
        detail: String = "No storage measurement is available."
    ) {
        self.filesystem = filesystem
        self.size = size
        self.used = used
        self.available = available
        self.capacity = capacity
        self.totalBytes = totalBytes
        self.immediatelyFreeBytes = immediatelyFreeBytes
        self.availableForWorkBytes = availableForWorkBytes
        self.opportunisticBytes = opportunisticBytes
        self.potentiallyPurgeableBytes = potentiallyPurgeableBytes
        self.usedEstimateBytes = usedEstimateBytes
        self.state = state
        self.measuredAt = measuredAt
        self.source = source
        self.detail = detail
    }
}

public struct StorageSummaryItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var label: String
    public var bytes: Int64
    public var detail: String

    public init(id: UUID = UUID(), label: String, bytes: Int64, detail: String) {
        self.id = id
        self.label = label
        self.bytes = bytes
        self.detail = detail
    }

    public var formattedSize: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

public struct PermissionDiagnostic: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var status: String
    public var detail: String
    public var remediation: String

    public init(id: UUID = UUID(), title: String, status: String, detail: String, remediation: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.remediation = remediation
    }
}

public struct ScanSnapshot: Sendable {
    public var timestamp: Date
    public var diskStatus: DiskStatus
    public var items: [ScanItem]
    public var storageSummaries: [StorageSummaryItem]
    public var permissionDiagnostics: [PermissionDiagnostic]
    public var warnings: [String]
    public var issues: [ScanIssue]
    public var completeness: ScanCompleteness
    public var scanDurationSeconds: TimeInterval
    public var policyVersion: String
    public var manifestChecksum: String
    public var appVersion: String
    public var accessStatus: String

    public init(
        timestamp: Date,
        diskStatus: DiskStatus,
        items: [ScanItem],
        storageSummaries: [StorageSummaryItem] = [],
        permissionDiagnostics: [PermissionDiagnostic] = [],
        warnings: [String] = [],
        issues: [ScanIssue] = [],
        completeness: ScanCompleteness,
        scanDurationSeconds: TimeInterval,
        policyVersion: String,
        manifestChecksum: String,
        appVersion: String,
        accessStatus: String
    ) {
        self.timestamp = timestamp
        self.diskStatus = diskStatus
        self.items = items
        self.storageSummaries = storageSummaries
        self.permissionDiagnostics = permissionDiagnostics
        self.warnings = warnings
        self.issues = issues
        self.completeness = completeness
        self.scanDurationSeconds = scanDurationSeconds
        self.policyVersion = policyVersion
        self.manifestChecksum = manifestChecksum
        self.appVersion = appVersion
        self.accessStatus = accessStatus
    }
}

public struct ScanReport: Codable, Sendable {
    public var mode: ReportMode
    public var timestamp: Date
    public var diskStatus: DiskStatus
    public var items: [ScanItem]
    public var results: [CleanupResult]
    public var storageSummaries: [StorageSummaryItem]
    public var permissionDiagnostics: [PermissionDiagnostic]
    public var warnings: [String]
    public var issues: [ScanIssue]
    public var completeness: ScanCompleteness
    public var scanDurationSeconds: TimeInterval
    public var policyVersion: String
    public var manifestChecksum: String
    public var appVersion: String
    public var accessStatus: String
    public var cleanupPlan: CleanupPlan?
    public var movedToTrashBytes: Int64
    public var schemaVersion: String?
    public var evidenceBundles: [CandidateEvidenceBundle]?
    public var ruleProvenance: [RuleProvenance]?
    public var scanID: UUID?
    public var campaignID: UUID?
    public var stopRecommendation: StopRecommendation?

    public init(
        mode: ReportMode = .scan,
        timestamp: Date,
        diskStatus: DiskStatus,
        items: [ScanItem],
        results: [CleanupResult],
        storageSummaries: [StorageSummaryItem] = [],
        permissionDiagnostics: [PermissionDiagnostic] = [],
        warnings: [String] = [],
        issues: [ScanIssue] = [],
        completeness: ScanCompleteness = .notRun,
        scanDurationSeconds: TimeInterval,
        policyVersion: String,
        manifestChecksum: String = "unavailable",
        appVersion: String,
        accessStatus: String,
        cleanupPlan: CleanupPlan? = nil,
        movedToTrashBytes: Int64 = 0,
        schemaVersion: String? = ReportSchema.currentVersion,
        evidenceBundles: [CandidateEvidenceBundle]? = nil,
        ruleProvenance: [RuleProvenance]? = nil,
        scanID: UUID? = UUID(),
        campaignID: UUID? = nil,
        stopRecommendation: StopRecommendation? = nil
    ) {
        self.mode = mode
        self.timestamp = timestamp
        self.diskStatus = diskStatus
        self.items = items
        self.results = results
        self.storageSummaries = storageSummaries
        self.permissionDiagnostics = permissionDiagnostics
        self.warnings = warnings
        self.issues = issues
        self.completeness = completeness
        self.scanDurationSeconds = scanDurationSeconds
        self.policyVersion = policyVersion
        self.manifestChecksum = manifestChecksum
        self.appVersion = appVersion
        self.accessStatus = accessStatus
        self.cleanupPlan = cleanupPlan
        self.movedToTrashBytes = movedToTrashBytes
        self.schemaVersion = schemaVersion
        let derivedEvidence = items.compactMap(\.evidence) + (cleanupPlan?.items.compactMap(\.evidence) ?? [])
        self.evidenceBundles = evidenceBundles ?? (derivedEvidence.isEmpty ? nil : derivedEvidence)
        let derivedProvenance = self.evidenceBundles?.map(\.provenance)
        self.ruleProvenance = ruleProvenance ?? derivedProvenance.map { Array(Set($0)).sorted { $0.ruleID < $1.ruleID } }
        self.scanID = scanID
        self.campaignID = campaignID
        self.stopRecommendation = stopRecommendation
    }
}
