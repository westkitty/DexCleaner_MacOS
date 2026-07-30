import Foundation

public enum StorageDriverClassification: String, Codable, CaseIterable, Sendable {
    case safeCacheCandidate = "Safe cache candidate"
    case reviewInApplication = "Review in application"
    case reviewProject = "Review project"
    case reviewCloudSettings = "Review cloud settings"
    case reviewLocalModel = "Review local model"
    case protectedApplicationState = "Protected application state"
    case systemManaged = "System-managed"
    case unresolved = "Unresolved"
}

public enum DriverMeasurementState: String, Codable, Sendable { case complete = "Complete", partial = "Partial", failed = "Failed", unavailable = "Unavailable" }

public struct StorageDriver: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var classification: StorageDriverClassification
    public var isWatch: Bool
    public init(id: UUID = UUID(), name: String, path: String, classification: StorageDriverClassification, isWatch: Bool = false) { self.id = id; self.name = name; self.path = path; self.classification = classification; self.isWatch = isWatch }
}

public struct DriverSnapshot: Identifiable, Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public var id: UUID
    public var driverID: UUID
    public var timestamp: Date
    public var bytes: Int64?
    public var state: DriverMeasurementState
    public var duration: TimeInterval
    public var filesystemNumber: UInt64?
    public var schemaVersion: Int
    public init(id: UUID = UUID(), driverID: UUID, timestamp: Date = Date(), bytes: Int64?, state: DriverMeasurementState, duration: TimeInterval, filesystemNumber: UInt64?, schemaVersion: Int = DriverSnapshot.schemaVersion) { self.id = id; self.driverID = driverID; self.timestamp = timestamp; self.bytes = bytes; self.state = state; self.duration = duration; self.filesystemNumber = filesystemNumber; self.schemaVersion = schemaVersion }
}

public struct DriverComparison: Sendable {
    public var capacityChange: Int64?
    public var changes: [(StorageDriver, Int64?)]
    public var unresolvedRemainder: Int64?
    public var confidence: String
}

public final class StorageDriverStore: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private let driversURL: URL
    private let snapshotsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(home: String = NSHomeDirectory(), directory: URL? = nil) {
        self.directory = directory ?? URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/DexCleaner/StorageDrivers", isDirectory: true)
        driversURL = self.directory.appendingPathComponent("watchlist-v1.json")
        snapshotsURL = self.directory.appendingPathComponent("driver-snapshots-v1.ndjson")
        encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
    }
    public func watchlist() -> [StorageDriver] { lock.lock(); defer { lock.unlock() }; return (try? decoder.decode([StorageDriver].self, from: Data(contentsOf: driversURL))) ?? [] }
    public func addWatch(name: String, path: String, classification: StorageDriverClassification = .reviewProject) throws -> StorageDriver {
        lock.lock(); defer { lock.unlock() }
        let normalized = SafetyEngine.lexicalNormalize(path)
        guard normalized.hasPrefix("/") else { throw NSError(domain: "DexCleaner.Driver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Watchlist paths must be absolute directories."]) }
        var watches = (try? decoder.decode([StorageDriver].self, from: Data(contentsOf: driversURL))) ?? []
        if let existing = watches.first(where: { $0.path == normalized }) { return existing }
        let watch = StorageDriver(name: name, path: normalized, classification: classification, isWatch: true); watches.append(watch)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try encoder.encode(watches).write(to: driversURL, options: .atomic); return watch
    }
    public func removeWatch(_ id: UUID) throws { lock.lock(); defer { lock.unlock() }; let watches = watchlistLocked().filter { $0.id != id }; try encoder.encode(watches).write(to: driversURL, options: .atomic) }
    public func append(_ snapshot: DriverSnapshot) throws { lock.lock(); defer { lock.unlock() }; try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); let data = try encoder.encode(snapshot) + Data([0x0A]); if !FileManager.default.fileExists(atPath: snapshotsURL.path) { FileManager.default.createFile(atPath: snapshotsURL.path, contents: nil) }; let handle = try FileHandle(forWritingTo: snapshotsURL); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize() }
    public func snapshots(for driverID: UUID, since: Date = .distantPast) -> [DriverSnapshot] { lock.lock(); defer { lock.unlock() }; guard let text = try? String(contentsOf: snapshotsURL) else { return [] }; return text.split(separator: "\n").compactMap { try? decoder.decode(DriverSnapshot.self, from: Data($0.utf8)) }.filter { $0.driverID == driverID && $0.timestamp >= since }.sorted { $0.timestamp < $1.timestamp } }
    private func watchlistLocked() -> [StorageDriver] { (try? decoder.decode([StorageDriver].self, from: Data(contentsOf: driversURL))) ?? [] }
}

public enum StorageDriverCatalog {
    public static func defaults(home: String = NSHomeDirectory()) -> [StorageDriver] {
        [
            StorageDriver(name: "Applications", path: "/Applications", classification: .reviewInApplication),
            StorageDriver(name: "Documents", path: "\(home)/Documents", classification: .reviewProject),
            StorageDriver(name: "Downloads", path: "\(home)/Downloads", classification: .reviewProject),
            StorageDriver(name: "Movies", path: "\(home)/Movies", classification: .reviewProject),
            StorageDriver(name: "Music", path: "\(home)/Music", classification: .reviewProject),
            StorageDriver(name: "Pictures", path: "\(home)/Pictures", classification: .reviewProject),
            StorageDriver(name: "Application Support", path: "\(home)/Library/Application Support", classification: .protectedApplicationState),
            StorageDriver(name: "Caches", path: "\(home)/Library/Caches", classification: .safeCacheCandidate),
            StorageDriver(name: "Developer data", path: "\(home)/Library/Developer", classification: .reviewProject),
            StorageDriver(name: "Local models", path: "\(home)/.ollama", classification: .reviewLocalModel),
            StorageDriver(name: "Cloud local state", path: "\(home)/Library/CloudStorage", classification: .reviewCloudSettings),
            StorageDriver(name: "Trash", path: "\(home)/.Trash", classification: .reviewInApplication)
        ]
    }
}

public enum StorageDriverAnalytics {
    public static func shouldAutomaticallyMeasure(lastSnapshot: Date?, now: Date = Date()) -> Bool { lastSnapshot.map { now.timeIntervalSince($0) >= 86_400 } ?? true }
    public static func significantDrop(samples: [CapacitySample], now: Date = Date()) -> String? {
        let valid = samples.filter(\.isValid).sorted { $0.timestamp < $1.timestamp }
        guard let newest = valid.last?.availableForWorkBytes else { return nil }
        if let sixHour = valid.last(where: { now.timeIntervalSince($0.timestamp) >= 21_600 })?.availableForWorkBytes, sixHour - newest >= 2_000_000_000 { return "Available for work declined by at least 2 GB within six hours." }
        if let day = valid.last(where: { now.timeIntervalSince($0.timestamp) >= 86_400 })?.availableForWorkBytes, day - newest >= 5_000_000_000 { return "Available for work declined by at least 5 GB within 24 hours." }
        return nil
    }
    public static func compare(drivers: [StorageDriver], newest: [UUID: DriverSnapshot], earlier: [UUID: DriverSnapshot], capacityChange: Int64?) -> DriverComparison {
        let changes = drivers.map { driver -> (StorageDriver, Int64?) in guard let now = newest[driver.id]?.bytes, let before = earlier[driver.id]?.bytes else { return (driver, nil) }; return (driver, now - before) }.sorted { ($0.1 ?? Int64.min) > ($1.1 ?? Int64.min) }
        let measured = changes.compactMap(\.1).reduce(0, +)
        return DriverComparison(capacityChange: capacityChange, changes: changes, unresolvedRemainder: capacityChange.map { $0 - measured }, confidence: changes.contains(where: { $0.1 == nil }) ? "Measurement incomplete" : "Measured change; causation is not inferred")
    }
}

public enum StorageDriverMeasurer {
    /// Read-only, bounded physical-allocation measurement. Logical placeholder bytes are never labeled local storage.
    public static func measure(_ driver: StorageDriver, maximumEntries: Int = 100_000) -> DriverSnapshot {
        let started = Date(), root = URL(fileURLWithPath: driver.path)
        guard let rootAttributes = try? FileManager.default.attributesOfItem(atPath: root.path) else { return DriverSnapshot(driverID: driver.id, bytes: nil, state: .unavailable, duration: Date().timeIntervalSince(started), filesystemNumber: nil) }
        let rootVolume = (rootAttributes[.systemNumber] as? NSNumber)?.uint64Value
        let measurement = FocusedAllocationMeasurer.measure(root: root, limit: maximumEntries, deadline: 90)
        let state: DriverMeasurementState
        switch measurement.complete { case .complete: state = .complete; case .partial, .cancelled: state = .partial; case .failed: state = .failed; case .unavailable: state = .unavailable }
        return DriverSnapshot(driverID: driver.id, bytes: state == .unavailable ? nil : measurement.allocatedBytes, state: state, duration: Date().timeIntervalSince(started), filesystemNumber: rootVolume)
    }
}
