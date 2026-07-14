import Foundation

public struct ScanCacheRecord: Codable, Hashable, Sendable {
    public var path: String
    public var sizeBytes: Int64
    public var modificationTime: TimeInterval
    public var scannedAt: Date
}

public final class ScanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: ScanCacheRecord] = [:]
    private let cacheURL: URL
    private let maximumAge: TimeInterval

    public init(home: String = NSHomeDirectory(), maximumAge: TimeInterval = 15 * 60) {
        self.maximumAge = maximumAge
        let dir = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/DexCleaner", isDirectory: true)
        self.cacheURL = dir.appendingPathComponent("scan-cache.json")
        if let data = try? Data(contentsOf: cacheURL), let decoded = try? JSONDecoder().decode([String: ScanCacheRecord].self, from: data) {
            self.records = decoded
        }
    }

    public func cachedRecord(path: String, now: Date = Date()) -> ScanCacheRecord? {
        let normalized = SafetyEngine.lexicalNormalize(path)
        guard let modificationTime = Self.modificationTime(path: normalized) else { return nil }
        lock.lock(); let record = records[normalized]; lock.unlock()
        guard let record,
              record.modificationTime == modificationTime,
              now.timeIntervalSince(record.scannedAt) <= maximumAge else { return nil }
        return record
    }

    public func store(path: String, sizeBytes: Int64, scannedAt: Date = Date()) {
        let normalized = SafetyEngine.lexicalNormalize(path)
        guard let modificationTime = Self.modificationTime(path: normalized) else { return }
        let record = ScanCacheRecord(path: normalized, sizeBytes: sizeBytes, modificationTime: modificationTime, scannedAt: scannedAt)
        lock.lock(); records[normalized] = record; lock.unlock()
    }

    public func invalidate(path: String) {
        let normalized = SafetyEngine.lexicalNormalize(path)
        lock.lock(); records.removeValue(forKey: normalized); lock.unlock()
    }

    public func invalidateTreeAndAncestors(path: String, upTo root: String) {
        let target = SafetyEngine.lexicalNormalize(path)
        let normalizedRoot = SafetyEngine.lexicalNormalize(root)
        lock.lock()
        records = records.filter { key, _ in
            let insideRoot = key == normalizedRoot || key.hasPrefix(normalizedRoot + "/")
            guard insideRoot else { return true }
            let isTargetOrDescendant = key == target || key.hasPrefix(target + "/")
            let isAncestor = target.hasPrefix(key + "/")
            return !isTargetOrDescendant && !isAncestor
        }
        lock.unlock()
    }

    public func pruneExpired(now: Date = Date()) {
        lock.lock()
        records = records.filter { now.timeIntervalSince($0.value.scannedAt) <= maximumAge }
        lock.unlock()
    }

    public func save() {
        pruneExpired()
        lock.lock(); let snapshot = records; lock.unlock()
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: cacheURL, options: .atomic)
        } catch {
            // Cache failure never changes cleanup authority.
        }
    }

    private static func modificationTime(path: String) -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path), let date = attrs[.modificationDate] as? Date else { return nil }
        return date.timeIntervalSince1970
    }
}
