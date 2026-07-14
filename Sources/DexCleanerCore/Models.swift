import Foundation

public enum MeasurementSource: String, Codable, Sendable {
    case fresh = "Fresh measurement"
    case cache = "Cached measurement"
    case notMeasured = "Not measured"
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
        owningProcessRunning: Bool = false
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

    public init(id: UUID = UUID(), path: String, status: String, detail: String) {
        self.id = id
        self.path = path
        self.status = status
        self.detail = detail
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

    public init(id: UUID = UUID(), scanItemID: UUID, manifestID: String, path: String, displayName: String, sizeBytes: Int64, identity: FileIdentity, safetyReason: String) {
        self.id = id
        self.scanItemID = scanItemID
        self.manifestID = manifestID
        self.path = path
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.identity = identity
        self.safetyReason = safetyReason
    }
}

public struct CleanupPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let manifestVersion: String
    public let manifestChecksum: String
    public let items: [CleanupPlanItem]

    public init(id: UUID = UUID(), createdAt: Date = Date(), manifestVersion: String, manifestChecksum: String, items: [CleanupPlanItem]) {
        self.id = id
        self.createdAt = createdAt
        self.manifestVersion = manifestVersion
        self.manifestChecksum = manifestChecksum
        self.items = items
    }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
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

    public init(filesystem: String = "Unknown", size: String = "Unknown", used: String = "Unknown", available: String = "Unknown", capacity: String = "Unknown") {
        self.filesystem = filesystem
        self.size = size
        self.used = used
        self.available = available
        self.capacity = capacity
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
        movedToTrashBytes: Int64 = 0
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
    }
}
