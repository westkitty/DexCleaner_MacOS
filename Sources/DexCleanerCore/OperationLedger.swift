import Foundation

public struct OperationLedgerEntry: Codable, Sendable {
    public var timestamp: Date
    public var mode: ReportMode
    public var planID: UUID?
    public var manifestVersion: String
    public var manifestChecksum: String
    public var results: [CleanupResult]
    public var movedToTrashBytes: Int64

    public init(timestamp: Date = Date(), mode: ReportMode, planID: UUID?, manifestVersion: String, manifestChecksum: String, results: [CleanupResult], movedToTrashBytes: Int64) {
        self.timestamp = timestamp
        self.mode = mode
        self.planID = planID
        self.manifestVersion = manifestVersion
        self.manifestChecksum = manifestChecksum
        self.results = results
        self.movedToTrashBytes = movedToTrashBytes
    }
}

public enum OperationLedger {
    public static func append(_ entry: OperationLedgerEntry, home: String = NSHomeDirectory()) throws -> URL {
        let directory = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/DexCleaner", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("operation-ledger.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
        return url
    }
}
