import Foundation

public enum CapacityTrigger: String, Codable, CaseIterable, Sendable {
    case applicationLaunch = "Application launch"
    case popoverOpening = "Menu-bar popover opening"
    case manualRefresh = "Manual Refresh Capacity"
    case periodic = "Five-minute periodic sample"
    case wakeFromSleep = "Wake from sleep"
    case quickScanCompletion = "Quick Scan completion"
    case cleanupCompletion = "Approved cleanup completion"
    case syntheticTest = "Synthetic test"
}

public enum CapacityResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneHour = "1h", sixHours = "6h", day = "24h", week = "7d", month = "30d", ninetyDays = "90d", sixMonths = "6m", year = "1y", twoYears = "2y"
    public var id: String { rawValue }
    public var interval: TimeInterval {
        switch self {
        case .oneHour: return 3_600
        case .sixHours: return 21_600
        case .day: return 86_400
        case .week: return 604_800
        case .month: return 2_592_000
        case .ninetyDays: return 7_776_000
        case .sixMonths: return 15_552_000
        case .year: return 31_536_000
        case .twoYears: return 63_072_000
        }
    }
}

public struct CapacitySample: Identifiable, Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public var id: UUID
    public var timestamp: Date
    public var totalBytes: Int64?
    public var immediatelyFreeBytes: Int64?
    public var availableForWorkBytes: Int64?
    public var opportunisticBytes: Int64?
    public var potentiallyPurgeableBytes: Int64?
    public var state: StorageMeasurementState
    public var source: String
    public var trigger: CapacityTrigger
    public var schemaVersion: Int

    public init(id: UUID = UUID(), timestamp: Date = Date(), totalBytes: Int64?, immediatelyFreeBytes: Int64?, availableForWorkBytes: Int64?, opportunisticBytes: Int64?, potentiallyPurgeableBytes: Int64?, state: StorageMeasurementState, source: String, trigger: CapacityTrigger, schemaVersion: Int = CapacitySample.schemaVersion) {
        self.id = id; self.timestamp = timestamp; self.totalBytes = totalBytes; self.immediatelyFreeBytes = immediatelyFreeBytes
        self.availableForWorkBytes = availableForWorkBytes; self.opportunisticBytes = opportunisticBytes; self.potentiallyPurgeableBytes = potentiallyPurgeableBytes
        self.state = state; self.source = source; self.trigger = trigger; self.schemaVersion = schemaVersion
    }

    public init(status: DiskStatus, trigger: CapacityTrigger) {
        self.init(timestamp: status.measuredAt ?? Date(), totalBytes: status.totalBytes, immediatelyFreeBytes: status.immediatelyFreeBytes, availableForWorkBytes: status.availableForWorkBytes, opportunisticBytes: status.opportunisticBytes, potentiallyPurgeableBytes: status.potentiallyPurgeableBytes, state: status.state, source: status.source, trigger: trigger)
    }

    public var isValid: Bool { availableForWorkBytes != nil && immediatelyFreeBytes != nil && state != .failed }
}

public struct CapacityAggregate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var intervalStart: Date
    public var intervalEnd: Date
    public var firstAvailableForWorkBytes: Int64?
    public var lastAvailableForWorkBytes: Int64?
    public var minimumAvailableForWorkBytes: Int64?
    public var maximumAvailableForWorkBytes: Int64?
    public var averageAvailableForWorkBytes: Int64?
    public var firstImmediatelyFreeBytes: Int64?
    public var lastImmediatelyFreeBytes: Int64?
    public var minimumImmediatelyFreeBytes: Int64?
    public var maximumImmediatelyFreeBytes: Int64?
    public var averageImmediatelyFreeBytes: Int64?
    public var validSampleCount: Int
    public var failedSampleCount: Int
    public var partialOrDisputedSampleCount: Int
    public var hasMaterialGap: Bool
    public var resolution: String

    public init(intervalStart: Date, intervalEnd: Date, samples: [CapacitySample], resolution: String, hasMaterialGap: Bool) {
        let valid = samples.filter(\.isValid).sorted { $0.timestamp < $1.timestamp }
        func values(_ keyPath: KeyPath<CapacitySample, Int64?>) -> [Int64] { valid.compactMap { $0[keyPath: keyPath] } }
        let available = values(\.availableForWorkBytes), immediate = values(\.immediatelyFreeBytes)
        id = UUID(); self.intervalStart = intervalStart; self.intervalEnd = intervalEnd
        firstAvailableForWorkBytes = available.first; lastAvailableForWorkBytes = available.last; minimumAvailableForWorkBytes = available.min(); maximumAvailableForWorkBytes = available.max(); averageAvailableForWorkBytes = available.isEmpty ? nil : available.reduce(0, +) / Int64(available.count)
        firstImmediatelyFreeBytes = immediate.first; lastImmediatelyFreeBytes = immediate.last; minimumImmediatelyFreeBytes = immediate.min(); maximumImmediatelyFreeBytes = immediate.max(); averageImmediatelyFreeBytes = immediate.isEmpty ? nil : immediate.reduce(0, +) / Int64(immediate.count)
        validSampleCount = valid.count; failedSampleCount = samples.filter { $0.state == .failed }.count
        partialOrDisputedSampleCount = samples.filter { $0.state == .partial || $0.state == .disputed }.count
        self.hasMaterialGap = hasMaterialGap; self.resolution = resolution
    }
}

public enum CapacityHistoryRecord: Identifiable, Hashable, Sendable {
    case raw(CapacitySample)
    case aggregate(CapacityAggregate)
    public var id: UUID { switch self { case .raw(let sample): return sample.id; case .aggregate(let aggregate): return aggregate.id } }
    public var start: Date { switch self { case .raw(let sample): return sample.timestamp; case .aggregate(let aggregate): return aggregate.intervalStart } }
    public var end: Date { switch self { case .raw(let sample): return sample.timestamp; case .aggregate(let aggregate): return aggregate.intervalEnd } }
    public var availableForWorkBytes: Int64? { switch self { case .raw(let sample): return sample.availableForWorkBytes; case .aggregate(let aggregate): return aggregate.lastAvailableForWorkBytes } }
    public var immediatelyFreeBytes: Int64? { switch self { case .raw(let sample): return sample.immediatelyFreeBytes; case .aggregate(let aggregate): return aggregate.lastImmediatelyFreeBytes } }
    public var state: StorageMeasurementState { switch self { case .raw(let sample): return sample.state; case .aggregate(let aggregate): return aggregate.failedSampleCount > 0 ? .partial : (aggregate.partialOrDisputedSampleCount > 0 ? .disputed : .cached) } }
    public var trigger: CapacityTrigger? { if case .raw(let sample) = self { return sample.trigger }; return nil }
    public var isAggregate: Bool { if case .aggregate = self { return true }; return false }
    public var minimumAvailableForWorkBytes: Int64? { if case .aggregate(let aggregate) = self { return aggregate.minimumAvailableForWorkBytes }; return availableForWorkBytes }
    public var maximumAvailableForWorkBytes: Int64? { if case .aggregate(let aggregate) = self { return aggregate.maximumAvailableForWorkBytes }; return availableForWorkBytes }
    public var minimumImmediatelyFreeBytes: Int64? { if case .aggregate(let aggregate) = self { return aggregate.minimumImmediatelyFreeBytes }; return immediatelyFreeBytes }
    public var maximumImmediatelyFreeBytes: Int64? { if case .aggregate(let aggregate) = self { return aggregate.maximumImmediatelyFreeBytes }; return immediatelyFreeBytes }
}

public enum CapacityMetric: String, Codable, CaseIterable, Sendable { case availableForWork = "Available for work", immediatelyFree = "Immediately free" }
public struct CapacityChartPoint: Hashable, Sendable {
    public var recordID: UUID; public var timestamp: Date; public var metric: CapacityMetric; public var value: Int64; public var isAggregate: Bool
    public init(recordID: UUID, timestamp: Date, metric: CapacityMetric, value: Int64, isAggregate: Bool) { self.recordID = recordID; self.timestamp = timestamp; self.metric = metric; self.value = value; self.isAggregate = isAggregate }
}
public enum CapacityChartSeries {
    public static func points(records: [CapacityHistoryRecord]) -> [CapacityChartPoint] {
        records.flatMap { record in
            var result: [CapacityChartPoint] = []
            if let value = record.availableForWorkBytes { result.append(CapacityChartPoint(recordID: record.id, timestamp: record.end, metric: .availableForWork, value: value, isAggregate: record.isAggregate)) }
            if let value = record.immediatelyFreeBytes { result.append(CapacityChartPoint(recordID: record.id, timestamp: record.end, metric: .immediatelyFree, value: value, isAggregate: record.isAggregate)) }
            return result
        }
    }
}

public struct CapacityHistorySummary: Sendable {
    public var rawSampleCount: Int
    public var aggregateCount: Int
    public var oldest: Date?
    public var newest: Date?
    public var bytes: Int64
    public var schemaVersion: Int
    public var growthSuspended: Bool
    public init(rawSampleCount: Int, aggregateCount: Int, oldest: Date?, newest: Date?, bytes: Int64, schemaVersion: Int, growthSuspended: Bool) {
        self.rawSampleCount = rawSampleCount; self.aggregateCount = aggregateCount; self.oldest = oldest; self.newest = newest; self.bytes = bytes; self.schemaVersion = schemaVersion; self.growthSuspended = growthSuspended
    }
}

public struct CapacityHistoryExportRow: Codable, Sendable {
    public var timestamp: Date
    public var intervalStart: Date
    public var intervalEnd: Date
    public var availableForWorkBytes: Int64?
    public var immediatelyFreeBytes: Int64?
    public var state: String
    public var trigger: String
    public var resolution: String
    public init(record: CapacityHistoryRecord) {
        timestamp = record.end; intervalStart = record.start; intervalEnd = record.end
        availableForWorkBytes = record.availableForWorkBytes; immediatelyFreeBytes = record.immediatelyFreeBytes
        state = record.state.rawValue; trigger = record.trigger?.rawValue ?? "aggregate"; resolution = record.isAggregate ? "aggregate" : "raw"
    }
}

public struct CapacityEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: String
    public var detail: String
    public init(id: UUID = UUID(), timestamp: Date = Date(), kind: String, detail: String) { self.id = id; self.timestamp = timestamp; self.kind = kind; self.detail = detail }
}

public final class CapacityEventStore: @unchecked Sendable {
    private let lock = NSLock(); private let url: URL; private let encoder = JSONEncoder(); private let decoder = JSONDecoder()
    public init(home: String = NSHomeDirectory()) { url = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/DexCleaner/CapacityHistory/events-v1.ndjson"); encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601 }
    public func append(_ event: CapacityEvent) throws { lock.lock(); defer { lock.unlock() }; try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }; let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: encoder.encode(event) + Data([0x0A])); try handle.synchronize() }
    public func all() -> [CapacityEvent] { lock.lock(); defer { lock.unlock() }; guard let text = try? String(contentsOf: url) else { return [] }; return text.split(separator: "\n").compactMap { try? decoder.decode(CapacityEvent.self, from: Data($0.utf8)) }.sorted { $0.timestamp < $1.timestamp } }
}

public struct CapacityRangeStatistics: Sendable {
    public var records: [CapacityHistoryRecord]
    public var start: Date
    public var end: Date
    public var validCount: Int
    public var failedOrDisputedCount: Int
    public var expectedCount: Int
    public var coveragePercent: Double
    public var longestGap: TimeInterval
    public var containsGap: Bool
    public var netChange: Int64?
    public var minimum: Int64?
    public var maximum: Int64?
    public var average: Int64?
    public init(records: [CapacityHistoryRecord], start: Date, end: Date, validCount: Int, failedOrDisputedCount: Int, expectedCount: Int, coveragePercent: Double, longestGap: TimeInterval, containsGap: Bool, netChange: Int64?, minimum: Int64?, maximum: Int64?, average: Int64?) {
        self.records = records; self.start = start; self.end = end; self.validCount = validCount; self.failedOrDisputedCount = failedOrDisputedCount; self.expectedCount = expectedCount; self.coveragePercent = coveragePercent; self.longestGap = longestGap; self.containsGap = containsGap; self.netChange = netChange; self.minimum = minimum; self.maximum = maximum; self.average = average
    }
}

public final class CapacityHistoryStore: @unchecked Sendable {
    public static let maximumBytes: Int64 = 64 * 1_024 * 1_024
    private let lock = NSLock()
    private let directory: URL
    private let rawURL: URL
    private let hourlyURL: URL
    private let dailyURL: URL
    private let stateURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(home: String = NSHomeDirectory(), directory: URL? = nil) {
        self.directory = directory ?? URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/DexCleaner/CapacityHistory", isDirectory: true)
        rawURL = self.directory.appendingPathComponent("capacity-raw-v1.ndjson")
        hourlyURL = self.directory.appendingPathComponent("capacity-hourly-v1.ndjson")
        dailyURL = self.directory.appendingPathComponent("capacity-daily-v1.ndjson")
        stateURL = self.directory.appendingPathComponent("capacity-history-state-v1.json")
        encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
    }

    public func record(_ sample: CapacitySample) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !growthSuspendedLocked() else { throw NSError(domain: "DexCleaner.CapacityHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Capacity history growth is suspended because the local size guard was reached."]) }
        let data = try encoder.encode(sample) + Data([0x0A])
        if currentBytesLocked() + Int64(data.count) > Self.maximumBytes {
            try writeStateLocked(growthSuspended: true)
            throw NSError(domain: "DexCleaner.CapacityHistory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Capacity history size guard reached; valid history was preserved."])
        }
        if !FileManager.default.fileExists(atPath: rawURL.path) { FileManager.default.createFile(atPath: rawURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: rawURL); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize()
    }

    public func records(range: CapacityResolution, now: Date = Date()) -> [CapacityHistoryRecord] {
        lock.lock(); defer { lock.unlock() }
        let start = now.addingTimeInterval(-range.interval)
        let file: URL
        if range.interval <= CapacityResolution.month.interval { file = rawURL }
        else if range.interval <= CapacityResolution.year.interval { file = hourlyURL }
        else { file = dailyURL }
        if file == rawURL { return readLinesLocked(rawURL, as: CapacitySample.self).filter { $0.timestamp >= start && $0.timestamp <= now }.map(CapacityHistoryRecord.raw) }
        return readLinesLocked(file, as: CapacityAggregate.self).filter { $0.intervalEnd >= start && $0.intervalStart <= now }.map(CapacityHistoryRecord.aggregate)
    }

    public func statistics(range: CapacityResolution, now: Date = Date()) -> CapacityRangeStatistics {
        let start = now.addingTimeInterval(-range.interval), values = records(range: range, now: now)
        let valid = values.compactMap(\.availableForWorkBytes), times = values.map(\.start).sorted()
        let gaps = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }
        let longest = gaps.max() ?? 0, expected = max(1, Int(range.interval / 300))
        let coverage = min(100, Double(values.count) / Double(expected) * 100)
        return CapacityRangeStatistics(records: values, start: start, end: now, validCount: valid.count, failedOrDisputedCount: values.filter { $0.state == .failed || $0.state == .disputed || $0.state == .partial }.count, expectedCount: expected, coveragePercent: coverage, longestGap: longest, containsGap: Self.isMaterialGap(longest), netChange: valid.count > 1 ? valid.last! - valid.first! : nil, minimum: valid.min(), maximum: valid.max(), average: valid.isEmpty ? nil : valid.reduce(0, +) / Int64(valid.count))
    }

    /// Five-minute sampling allows ordinary scheduler drift; gaps beyond two cadences plus one minute remain honest evidence of suspension, sleep, or absence.
    public static func isMaterialGap(_ interval: TimeInterval, cadence: TimeInterval = 300) -> Bool { interval > cadence * 2 + 60 }

    public func summary() -> CapacityHistorySummary {
        lock.lock(); defer { lock.unlock() }
        let raw = readLinesLocked(rawURL, as: CapacitySample.self), hourly = readLinesLocked(hourlyURL, as: CapacityAggregate.self), daily = readLinesLocked(dailyURL, as: CapacityAggregate.self)
        let dates = raw.map(\.timestamp) + hourly.map(\.intervalStart) + daily.map(\.intervalStart)
        return CapacityHistorySummary(rawSampleCount: raw.count, aggregateCount: hourly.count + daily.count, oldest: dates.min(), newest: dates.max(), bytes: currentBytesLocked(), schemaVersion: CapacitySample.schemaVersion, growthSuspended: growthSuspendedLocked())
    }

    public func exportData(range: CapacityResolution, format: String, now: Date = Date()) throws -> Data {
        let rows = records(range: range, now: now).map(CapacityHistoryExportRow.init)
        if format == "json" {
            let exportEncoder = JSONEncoder(); exportEncoder.dateEncodingStrategy = .iso8601; exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try exportEncoder.encode(rows)
        }
        let header = "timestamp,interval_start,interval_end,available_for_work_bytes,immediately_free_bytes,state,trigger,resolution\n"
        let body = rows.map { row in
            [row.timestamp.ISO8601Format(), row.intervalStart.ISO8601Format(), row.intervalEnd.ISO8601Format(), row.availableForWorkBytes.map(String.init) ?? "", row.immediatelyFreeBytes.map(String.init) ?? "", row.state, row.trigger, row.resolution]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",")
        }.joined(separator: "\n")
        return Data((header + body + (body.isEmpty ? "" : "\n")).utf8)
    }

    /// Compacts only aged raw records after replacement aggregates have been written and decoded successfully.
    public func compact(now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        let raw = readLinesLocked(rawURL, as: CapacitySample.self).sorted { $0.timestamp < $1.timestamp }
        let rawCutoff = now.addingTimeInterval(-CapacityResolution.month.interval)
        let dailyCutoff = now.addingTimeInterval(-CapacityResolution.year.interval)
        let hourlySource = raw.filter { $0.timestamp < rawCutoff }
        let dailySource = readLinesLocked(hourlyURL, as: CapacityAggregate.self).filter { $0.intervalEnd < dailyCutoff }
        let hourly = aggregateLocked(hourlySource, bucket: 3_600, resolution: "hourly")
        let daily = aggregateFromHourlyLocked(dailySource, bucket: 86_400)
        try replaceLocked(hourly, at: hourlyURL)
        if !daily.isEmpty { try replaceLocked(daily, at: dailyURL) }
        let retainedRaw = raw.filter { $0.timestamp >= rawCutoff }
        try replaceLocked(retainedRaw, at: rawURL)
        try writeStateLocked(growthSuspended: currentBytesLocked() > Self.maximumBytes)
    }

    private func aggregateLocked(_ samples: [CapacitySample], bucket: TimeInterval, resolution: String) -> [CapacityAggregate] {
        let grouped = Dictionary(grouping: samples) { Int(floor($0.timestamp.timeIntervalSince1970 / bucket)) }
        return grouped.keys.sorted().compactMap { key in
            let values = grouped[key] ?? [], start = Date(timeIntervalSince1970: Double(key) * bucket), end = start.addingTimeInterval(bucket)
            return CapacityAggregate(intervalStart: start, intervalEnd: end, samples: values, resolution: resolution, hasMaterialGap: gapExists(values.map(\.timestamp), expected: 300))
        }
    }

    private func aggregateFromHourlyLocked(_ aggregates: [CapacityAggregate], bucket: TimeInterval) -> [CapacityAggregate] {
        let synthetic = aggregates.map { CapacitySample(timestamp: $0.intervalEnd, totalBytes: nil, immediatelyFreeBytes: $0.lastImmediatelyFreeBytes, availableForWorkBytes: $0.lastAvailableForWorkBytes, opportunisticBytes: nil, potentiallyPurgeableBytes: nil, state: $0.failedSampleCount > 0 ? .failed : .cached, source: "Verified hourly aggregate", trigger: .syntheticTest) }
        return aggregateLocked(synthetic, bucket: bucket, resolution: "daily")
    }

    private func replaceLocked<T: Encodable>(_ values: [T], at url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let payload = try values.map { try encoder.encode($0) }.reduce(Data()) { $0 + $1 + Data([0x0A]) }
        try payload.write(to: temporary, options: .atomic)
        guard (try? Data(contentsOf: temporary)) != nil else { throw NSError(domain: "DexCleaner.CapacityHistory", code: 3) }
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = directory.appendingPathComponent(".\(url.lastPathComponent).previous.\(UUID().uuidString)")
            try FileManager.default.moveItem(at: url, to: backup)
            do { try FileManager.default.moveItem(at: temporary, to: url) } catch { try? FileManager.default.moveItem(at: backup, to: url); throw error }
        } else { try FileManager.default.moveItem(at: temporary, to: url) }
    }

    private func readLinesLocked<T: Decodable>(_ url: URL, as: T.Type) -> [T] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
    }
    private func currentBytesLocked() -> Int64 { [rawURL, hourlyURL, dailyURL, stateURL].reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? NSNumber)?.int64Value ?? 0) } }
    private func gapExists(_ dates: [Date], expected: TimeInterval) -> Bool { zip(dates.sorted(), dates.sorted().dropFirst()).contains { $1.timeIntervalSince($0) > expected * 3 } }
    private func growthSuspendedLocked() -> Bool { (try? decoder.decode([String: Bool].self, from: Data(contentsOf: stateURL)))?["growthSuspended"] ?? false }
    private func writeStateLocked(growthSuspended: Bool) throws { try encoder.encode(["growthSuspended": growthSuspended]).write(to: stateURL, options: .atomic) }
}

public struct CapacitySamplingGate: Sendable {
    public static let coalescingInterval: TimeInterval = 60
    public private(set) var lastSampleAt: Date?
    public init(lastSampleAt: Date? = nil) { self.lastSampleAt = lastSampleAt }
    public mutating func accepts(_ now: Date = Date()) -> Bool { guard let lastSampleAt, now.timeIntervalSince(lastSampleAt) < Self.coalescingInterval else { lastSampleAt = now; return true }; return false }
}

public struct StorageAlertConfiguration: Codable, Sendable {
    public var warningBytes: Int64 = 10_000_000_000
    public var recoveryBytes: Int64 = 12_000_000_000
    public var criticalBytes: Int64 = 5_000_000_000
    public var minimumNotificationInterval: TimeInterval = 3_600
    public init(warningBytes: Int64 = 10_000_000_000, recoveryBytes: Int64 = 12_000_000_000, criticalBytes: Int64 = 5_000_000_000, minimumNotificationInterval: TimeInterval = 3_600) {
        self.warningBytes = warningBytes; self.recoveryBytes = recoveryBytes; self.criticalBytes = criticalBytes; self.minimumNotificationInterval = minimumNotificationInterval
    }
    public func isValid() -> Bool { criticalBytes > 0 && warningBytes > criticalBytes && recoveryBytes > warningBytes }
}

public struct StorageAlertState: Codable, Sendable {
    public var activeSince: Date?
    public var episodeStartedImmediatelyFreeBytes: Int64?
    public var criticalSent = false
    public var lastNotificationAt: Date?
    public var snoozedUntil: Date?
    public var mutedUntilRecovery = false
    public init() {}
}

public enum StorageAlertEvent: String, Codable, Sendable { case warningCrossed, criticalCrossed, recovered, none }
public struct StorageAlertDecision: Sendable { public var event: StorageAlertEvent; public var shouldNotify: Bool; public var state: StorageAlertState }

public final class StorageAlertStateStore: @unchecked Sendable {
    private let url: URL; private let configurationURL: URL; private let encoder = JSONEncoder(); private let decoder = JSONDecoder(); private let lock = NSLock()
    public init(home: String = NSHomeDirectory()) {
        let directory = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/DexCleaner/StorageAlerts")
        url = directory.appendingPathComponent("alert-state-v1.json")
        configurationURL = directory.appendingPathComponent("alert-configuration-v1.json")
        encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
    }
    public func load() -> StorageAlertState { lock.lock(); defer { lock.unlock() }; return (try? decoder.decode(StorageAlertState.self, from: Data(contentsOf: url))) ?? StorageAlertState() }
    public func save(_ state: StorageAlertState) { lock.lock(); defer { lock.unlock() }; try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try? encoder.encode(state).write(to: url, options: .atomic) }
    public func loadConfiguration() -> StorageAlertConfiguration { lock.lock(); defer { lock.unlock() }; return (try? decoder.decode(StorageAlertConfiguration.self, from: Data(contentsOf: configurationURL))).flatMap { $0.isValid() ? $0 : nil } ?? StorageAlertConfiguration() }
    public func saveConfiguration(_ configuration: StorageAlertConfiguration) { guard configuration.isValid() else { return }; lock.lock(); defer { lock.unlock() }; try? FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true); try? encoder.encode(configuration).write(to: configurationURL, options: .atomic) }
}

public enum StorageAlertEngine {
    public static func evaluate(immediatelyFreeBytes: Int64?, at now: Date = Date(), configuration: StorageAlertConfiguration, state: StorageAlertState) -> StorageAlertDecision {
        guard configuration.isValid(), let immediatelyFreeBytes else { return StorageAlertDecision(event: .none, shouldNotify: false, state: state) }
        var next = state
        if immediatelyFreeBytes >= configuration.recoveryBytes, next.activeSince != nil { next.activeSince = nil; next.episodeStartedImmediatelyFreeBytes = nil; next.criticalSent = false; next.mutedUntilRecovery = false; next.snoozedUntil = nil; return StorageAlertDecision(event: .recovered, shouldNotify: false, state: next) }
        guard immediatelyFreeBytes < configuration.warningBytes else { return StorageAlertDecision(event: .none, shouldNotify: false, state: next) }
        let notificationAllowed = !next.mutedUntilRecovery && (next.snoozedUntil.map { $0 <= now } ?? true) && (next.lastNotificationAt.map { now.timeIntervalSince($0) >= configuration.minimumNotificationInterval } ?? true)
        if next.activeSince == nil { next.activeSince = now; next.episodeStartedImmediatelyFreeBytes = immediatelyFreeBytes; if notificationAllowed { next.lastNotificationAt = now }; return StorageAlertDecision(event: .warningCrossed, shouldNotify: notificationAllowed, state: next) }
        if immediatelyFreeBytes < configuration.criticalBytes && !next.criticalSent { next.criticalSent = true; if notificationAllowed { next.lastNotificationAt = now }; return StorageAlertDecision(event: .criticalCrossed, shouldNotify: notificationAllowed, state: next) }
        return StorageAlertDecision(event: .none, shouldNotify: false, state: next)
    }
}

public enum CapacityForecast {
    public static func estimate(samples: [CapacitySample], now: Date = Date()) -> String? {
        let valid = samples.filter { $0.isValid }.sorted { $0.timestamp < $1.timestamp }
        guard valid.count >= 6, let first = valid.first, let last = valid.last, let firstValue = first.immediatelyFreeBytes, let lastValue = last.immediatelyFreeBytes else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp), loss = firstValue - lastValue
        guard elapsed >= 3_600, loss > 0 else { return nil }
        let gaps = zip(valid, valid.dropFirst()).map { $1.timestamp.timeIntervalSince($0.timestamp) }
        guard (gaps.max() ?? 0) < 1_800 else { return nil }
        let rate = Double(loss) / elapsed, remaining = Double(lastValue - 10_000_000_000)
        guard remaining > 0 else { return "Immediately free is already below the 10 GB warning threshold." }
        let hours = remaining / rate / 3_600
        guard hours.isFinite && hours > 0 else { return nil }
        return "At the recent rate, Immediately free may reach 10 GB in approximately \(Int(hours.rounded())) hours. Storage behavior is volatile."
    }
}
