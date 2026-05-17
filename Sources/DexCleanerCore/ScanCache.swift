import Foundation

public struct ScanCacheRecord: Codable, Hashable, Sendable {
    public var path: String
    public var sizeBytes: Int64
    public var modificationTime: TimeInterval
    public var scannedAt: Date
}

public final class ScanCache: @unchecked Sendable {
    public static let shared = ScanCache()

    private let lock = NSLock()
    private var records: [String: ScanCacheRecord] = [:]
    private let cacheURL: URL

    public init(home: String = NSHomeDirectory()) {
        let dir = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/DexCleaner", isDirectory: true)
        self.cacheURL = dir.appendingPathComponent("scan-cache.json")
        if let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([String: ScanCacheRecord].self, from: data) {
            self.records = decoded
        }
    }

    public func cachedSize(path: String) -> Int64? {
        let normalized = SafetyEngine.lexicalNormalize(path)
        guard let modificationTime = Self.modificationTime(path: normalized) else { return nil }
        lock.lock()
        let record = records[normalized]
        lock.unlock()
        guard let record, record.modificationTime == modificationTime else { return nil }
        return record.sizeBytes
    }

    public func store(path: String, sizeBytes: Int64) {
        let normalized = SafetyEngine.lexicalNormalize(path)
        guard let modificationTime = Self.modificationTime(path: normalized) else { return }
        let record = ScanCacheRecord(path: normalized, sizeBytes: sizeBytes, modificationTime: modificationTime, scannedAt: Date())
        lock.lock()
        records[normalized] = record
        lock.unlock()
    }

    public func save() {
        lock.lock()
        let snapshot = records
        lock.unlock()
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache is an optimization only. Failure should not affect scanning.
        }
    }

    private static func modificationTime(path: String) -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path), let date = attrs[.modificationDate] as? Date else { return nil }
        return date.timeIntervalSince1970
    }
}
