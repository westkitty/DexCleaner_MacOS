import Foundation

public enum OperationLedgerState: String, Codable, Hashable, Sendable {
    case preview
    case pending
    case completed
    case reconciled
    case unresolved
    case failed
}

public struct OperationLedgerTarget: Codable, Sendable {
    public var manifestID: String
    public var path: String
    public var identity: FileIdentity
    public var measuredSizeBytes: Int64

    public init(manifestID: String, path: String, identity: FileIdentity, measuredSizeBytes: Int64) {
        self.manifestID = manifestID
        self.path = path
        self.identity = identity
        self.measuredSizeBytes = measuredSizeBytes
    }
}

public struct OperationLedgerEntry: Codable, Sendable {
    public var operationID: UUID
    public var timestamp: Date
    public var state: OperationLedgerState
    public var mode: ReportMode
    public var planID: UUID?
    public var manifestVersion: String
    public var manifestChecksum: String
    public var targets: [OperationLedgerTarget]
    public var results: [CleanupResult]
    public var movedToTrashBytes: Int64

    public init(
        operationID: UUID = UUID(),
        timestamp: Date = Date(),
        state: OperationLedgerState? = nil,
        mode: ReportMode,
        planID: UUID?,
        manifestVersion: String,
        manifestChecksum: String,
        targets: [OperationLedgerTarget] = [],
        results: [CleanupResult],
        movedToTrashBytes: Int64
    ) {
        self.operationID = operationID
        self.timestamp = timestamp
        self.state = state ?? (mode == .dryRun ? .preview : .completed)
        self.mode = mode
        self.planID = planID
        self.manifestVersion = manifestVersion
        self.manifestChecksum = manifestChecksum
        self.targets = targets
        self.results = results
        self.movedToTrashBytes = movedToTrashBytes
    }
}

public enum OperationLedger {
    private static let writeLock = NSLock()

    public static func append(_ entry: OperationLedgerEntry, home: String = NSHomeDirectory()) throws -> URL {
        let url = ledgerURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry) + Data("\n".utf8)

        writeLock.lock()
        defer { writeLock.unlock() }
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        return url
    }

    public static func begin(plan: CleanupPlan, home: String = NSHomeDirectory()) throws -> OperationLedgerEntry {
        let entry = OperationLedgerEntry(
            state: .pending,
            mode: .cleanup,
            planID: plan.id,
            manifestVersion: plan.manifestVersion,
            manifestChecksum: plan.manifestChecksum,
            targets: plan.items.map {
                OperationLedgerTarget(
                    manifestID: $0.manifestID,
                    path: $0.path,
                    identity: $0.identity,
                    measuredSizeBytes: $0.sizeBytes
                )
            },
            results: [],
            movedToTrashBytes: 0
        )
        _ = try append(entry, home: home)
        return entry
    }

    @discardableResult
    public static func finish(
        pending: OperationLedgerEntry,
        results: [CleanupResult],
        movedToTrashBytes: Int64,
        home: String = NSHomeDirectory()
    ) throws -> URL {
        let terminalState: OperationLedgerState = results.contains(where: { $0.status == "Failed" || $0.status == "Blocked" })
            ? .failed
            : .completed
        return try append(OperationLedgerEntry(
            operationID: pending.operationID,
            state: terminalState,
            mode: .cleanup,
            planID: pending.planID,
            manifestVersion: pending.manifestVersion,
            manifestChecksum: pending.manifestChecksum,
            targets: pending.targets,
            results: results,
            movedToTrashBytes: movedToTrashBytes
        ), home: home)
    }

    public static func reconcilePendingOperations(home: String = NSHomeDirectory()) throws -> [OperationLedgerEntry] {
        let entries = try readEntries(home: home)
        let terminalStates: Set<OperationLedgerState> = [.completed, .reconciled, .unresolved, .failed]
        let terminalIDs = Set(entries.filter { terminalStates.contains($0.state) }.map(\.operationID))
        let pending = entries.filter { $0.state == .pending && !terminalIDs.contains($0.operationID) }

        return try pending.map { entry in
            var unresolved = false
            let results = entry.targets.map { target -> CleanupResult in
                if let current = FileIdentity.capture(path: target.path), current == target.identity {
                    return CleanupResult(
                        path: target.path,
                        status: "Reconciled",
                        detail: "The original target still exists with its previewed identity. No retry was performed."
                    )
                }
                unresolved = true
                return CleanupResult(
                    path: target.path,
                    status: "Unresolved",
                    detail: "The original target is absent or changed. Trash state requires review; no automatic retry was performed."
                )
            }
            let reconciled = OperationLedgerEntry(
                operationID: entry.operationID,
                state: unresolved ? .unresolved : .reconciled,
                mode: .cleanup,
                planID: entry.planID,
                manifestVersion: entry.manifestVersion,
                manifestChecksum: entry.manifestChecksum,
                targets: entry.targets,
                results: results,
                movedToTrashBytes: 0
            )
            _ = try append(reconciled, home: home)
            return reconciled
        }
    }

    public static func readEntries(home: String = NSHomeDirectory()) throws -> [OperationLedgerEntry] {
        let url = ledgerURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(OperationLedgerEntry.self, from: Data($0)) }
    }

    public static func ledgerURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/DexCleaner", isDirectory: true)
            .appendingPathComponent("operation-ledger.jsonl")
    }
}
