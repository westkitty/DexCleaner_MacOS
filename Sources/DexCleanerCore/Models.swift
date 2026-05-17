import Foundation

public struct ScanItem: Identifiable, Hashable, Sendable {
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
        isSelected: Bool
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

    public var allowsSelection: Bool {
        self == .safe
    }

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

public struct CleanupResult: Identifiable, Hashable, Sendable {
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

public struct DiskStatus: Hashable, Sendable {
    public var filesystem: String
    public var size: String
    public var used: String
    public var available: String
    public var capacity: String

    public init(
        filesystem: String = "Unknown",
        size: String = "Unknown",
        used: String = "Unknown",
        available: String = "Unknown",
        capacity: String = "Unknown"
    ) {
        self.filesystem = filesystem
        self.size = size
        self.used = used
        self.available = available
        self.capacity = capacity
    }
}

public struct StorageSummaryItem: Identifiable, Hashable, Sendable, Codable {
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

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct PermissionDiagnostic: Identifiable, Hashable, Sendable, Codable {
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
    public var scanDurationSeconds: TimeInterval
    public var policyVersion: String
    public var appVersion: String
    public var fullDiskAccessStatus: String
    public var cancelled: Bool

    public init(
        timestamp: Date,
        diskStatus: DiskStatus,
        items: [ScanItem],
        storageSummaries: [StorageSummaryItem] = [],
        permissionDiagnostics: [PermissionDiagnostic] = [],
        warnings: [String] = [],
        scanDurationSeconds: TimeInterval,
        policyVersion: String,
        appVersion: String,
        fullDiskAccessStatus: String,
        cancelled: Bool
    ) {
        self.timestamp = timestamp
        self.diskStatus = diskStatus
        self.items = items
        self.storageSummaries = storageSummaries
        self.permissionDiagnostics = permissionDiagnostics
        self.warnings = warnings
        self.scanDurationSeconds = scanDurationSeconds
        self.policyVersion = policyVersion
        self.appVersion = appVersion
        self.fullDiskAccessStatus = fullDiskAccessStatus
        self.cancelled = cancelled
    }
}

public struct ScanReport: Sendable {
    public var mode: ReportMode
    public var timestamp: Date
    public var diskStatus: DiskStatus
    public var items: [ScanItem]
    public var results: [CleanupResult]
    public var storageSummaries: [StorageSummaryItem]
    public var permissionDiagnostics: [PermissionDiagnostic]
    public var warnings: [String]
    public var scanDurationSeconds: TimeInterval
    public var policyVersion: String
    public var appVersion: String
    public var fullDiskAccessStatus: String

    public init(
        mode: ReportMode = .scan,
        timestamp: Date,
        diskStatus: DiskStatus,
        items: [ScanItem],
        results: [CleanupResult],
        storageSummaries: [StorageSummaryItem] = [],
        permissionDiagnostics: [PermissionDiagnostic] = [],
        warnings: [String] = [],
        scanDurationSeconds: TimeInterval,
        policyVersion: String,
        appVersion: String,
        fullDiskAccessStatus: String
    ) {
        self.mode = mode
        self.timestamp = timestamp
        self.diskStatus = diskStatus
        self.items = items
        self.results = results
        self.storageSummaries = storageSummaries
        self.permissionDiagnostics = permissionDiagnostics
        self.warnings = warnings
        self.scanDurationSeconds = scanDurationSeconds
        self.policyVersion = policyVersion
        self.appVersion = appVersion
        self.fullDiskAccessStatus = fullDiskAccessStatus
    }
}
