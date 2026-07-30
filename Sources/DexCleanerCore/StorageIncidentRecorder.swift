import Foundation
#if os(macOS)
import CoreServices
#endif

// MARK: - Truthful diagnostic model (separate from cleanup authority)

public enum RecorderStatus: String, Codable, Sendable { case armed = "Armed", recording = "Recording", investigating = "Investigating", partialCoverage = "Partial coverage", paused = "Paused", error = "Error" }
public enum EvidenceCompleteness: String, Codable, Sendable { case complete = "Complete", partial = "Partial", cancelled = "Cancelled", failed = "Failed", unavailable = "Unavailable" }
public enum IncidentTrigger: String, Codable, Sendable { case consecutive512MiB, oneHour1GiB, sixHours2GiB, below10GB, below5GB, below2GB, postWake512MiB, manual = "Investigate Now" }
public enum AssociationConfidence: String, Codable, Sendable { case confirmedWriter = "Confirmed writer", stronglyAssociated = "Strongly associated", possibleContributor = "Possible contributor", merelyActive = "Merely active", unknown = "Unknown" }
public enum DiagnosticClassification: String, Codable, Sendable { case cache, buildOutput, applicationState, cloudPlaceholder, providerCache, providerDatabase, systemManaged, project, trash, swap, unresolved }
public enum DiagnosticOperationState: String, Codable, Sendable { case idle = "Idle", preparing = "Preparing", running = "Running", waiting = "Waiting", cancelling = "Cancelling", cancelled = "Cancelled", partial = "Partial", failed = "Failed", complete = "Complete" }

public struct IncidentSettings: Codable, Sendable {
    public var consecutiveLoss: Int64 = 512 * 1_024 * 1_024
    public var hourlyLoss: Int64 = 1 * 1_024 * 1_024 * 1_024
    public var sixHourLoss: Int64 = 2 * 1_024 * 1_024 * 1_024
    public var warningBytes: Int64 = 10_000_000_000
    public var criticalBytes: Int64 = 5_000_000_000
    public var emergencyBytes: Int64 = 2_000_000_000
    public var stableSeconds: TimeInterval = 600
    public init() {}
}

public struct RecorderCapacitySample: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var monotonic: TimeInterval
    public var bootID: String
    public var sessionID: String
    public var volumeID: String
    public var immediatelyFreeBytes: Int64?
    public var availableForWorkBytes: Int64?
    public var purgeableBytes: Int64?
    public var trigger: String
    public var wakeState: String
    public var incidentID: UUID?
    public var state: StorageMeasurementState
    public var error: String?
    public init(status: DiskStatus, trigger: String, wakeState: String = "Active", incidentID: UUID? = nil, now: Date = Date()) {
        self.timestamp = now; self.monotonic = ProcessInfo.processInfo.systemUptime
        self.bootID = ProcessInfo.processInfo.globallyUniqueString; self.sessionID = NSUserName()
        self.volumeID = status.filesystem; self.immediatelyFreeBytes = status.immediatelyFreeBytes
        self.availableForWorkBytes = status.availableForWorkBytes; self.purgeableBytes = status.potentiallyPurgeableBytes
        self.trigger = trigger; self.wakeState = wakeState; self.incidentID = incidentID; self.state = status.state
        self.error = status.state == .failed ? status.detail : nil
    }
}

public struct FSEventEvidence: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID(); public var eventID: UInt64; public var timestamp: Date; public var path: String; public var flags: UInt32; public var volume: String; public var ancestor: String; public var incidentID: UUID?
    public init(eventID: UInt64, timestamp: Date = Date(), path: String, flags: UInt32, volume: String = "Startup volume", ancestor: String, incidentID: UUID? = nil) { self.eventID = eventID; self.timestamp = timestamp; self.path = path; self.flags = flags; self.volume = volume; self.ancestor = ancestor; self.incidentID = incidentID }
}

public struct PathMeasurement: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID(); public var path: String; public var classification: DiagnosticClassification; public var allocatedBytes: Int64; public var logicalBytes: Int64; public var sparse: Bool; public var mayShareContent: Bool; public var placeholderBytes: Int64; public var complete: EvidenceCompleteness; public var issue: String?; public var measuredAt: Date
    public init(path: String, classification: DiagnosticClassification = .unresolved, allocatedBytes: Int64 = 0, logicalBytes: Int64 = 0, sparse: Bool = false, mayShareContent: Bool = false, placeholderBytes: Int64 = 0, complete: EvidenceCompleteness = .complete, issue: String? = nil, measuredAt: Date = Date()) { self.path = path; self.classification = classification; self.allocatedBytes = allocatedBytes; self.logicalBytes = logicalBytes; self.sparse = sparse; self.mayShareContent = mayShareContent; self.placeholderBytes = placeholderBytes; self.complete = complete; self.issue = issue; self.measuredAt = measuredAt }
}

public struct FileGrowthEvidence: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID(); public var path: String; public var priorAllocatedBytes: Int64; public var currentAllocatedBytes: Int64; public var logicalBytes: Int64; public var createdAt: Date?; public var modifiedAt: Date?; public var kind: String; public var caveat: String?; public var completeness: EvidenceCompleteness
    public var deltaBytes: Int64 { currentAllocatedBytes - priorAllocatedBytes }
}

public struct ProcessEvidence: Codable, Identifiable, Hashable, Sendable { public var id: UUID = UUID(); public var name: String; public var executable: String; public var bundleID: String?; public var path: String?; public var confidence: AssociationConfidence; public var detail: String }
public struct ScheduledTaskEvidence: Codable, Identifiable, Hashable, Sendable { public var id: UUID = UUID(); public var label: String; public var program: String?; public var schedule: String?; public var path: String; public var confidence: AssociationConfidence; public var detail: String }

public struct CloudProviderEvidence: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID(); public var provider: String; public var accountLabel: String?; public var domainIdentifier: String?; public var root: String; public var state: String; public var logicalBytes: Int64; public var allocatedUserBytes: Int64; public var placeholderBytes: Int64; public var downloadedBytes: Int64; public var pinnedBytes: Int64; public var cacheBytes: Int64; public var databaseBytes: Int64; public var completeness: EvidenceCompleteness; public var safeAction: String
}

public struct SystemAccounting: Codable, Sendable { public var swapBytes: Int64 = 0; public var trashBytes: Int64 = 0; public var providerBytes: Int64 = 0; public var dexCleanerBytes: Int64?; public var purgeableDelta: Int64?; public var explainedBytes: Int64 = 0; public var unexplainedBytes: Int64 = 0; public var detail: String = "Unexplained allocation change is preserved when measured paths do not reconcile capacity loss."; public init() {} }
public struct FilesystemEventRecovery: Codable, Sendable { public var schemaVersion: Int = 1; public var outcome: FSEventsRecoveryOutcome; public var storedCheckpointEventID: UInt64?; public var requestedResumeEventID: UInt64?; public var firstReplayedEventID: UInt64?; public var newestRecoveredEventID: UInt64?; public var watchedVolumeIdentity: String?; public var watchedRoots: [String]; public var recoveryStartedAt: Date?; public var recoveryEndedAt: Date?; public var eventsReplayed: Int; public var duplicatesSuppressed: Int; public var userEventsDropped: Bool; public var kernelEventsDropped: Bool; public var rootChanged: Bool; public var volumeChanged: Bool; public var missingIntervalStart: Date?; public var missingIntervalEnd: Date?; public var fallbackBaselineAttempted: Bool; public var fallbackBaselineResult: String?; public var evidenceCompleteness: EvidenceCompleteness; public var detail: String; public init(outcome: FSEventsRecoveryOutcome = .freshBaselineRequired, storedCheckpointEventID: UInt64? = nil, requestedResumeEventID: UInt64? = nil, watchedVolumeIdentity: String? = nil, watchedRoots: [String] = [], recoveryStartedAt: Date? = nil, recoveryEndedAt: Date? = nil, eventsReplayed: Int = 0, duplicatesSuppressed: Int = 0, userEventsDropped: Bool = false, kernelEventsDropped: Bool = false, rootChanged: Bool = false, volumeChanged: Bool = false, missingIntervalStart: Date? = nil, missingIntervalEnd: Date? = nil, fallbackBaselineAttempted: Bool = false, fallbackBaselineResult: String? = nil, evidenceCompleteness: EvidenceCompleteness = .partial, detail: String = "FSEvents provides location evidence only; allocated-byte measurement is separate.") { self.outcome = outcome; self.storedCheckpointEventID = storedCheckpointEventID; self.requestedResumeEventID = requestedResumeEventID; self.watchedVolumeIdentity = watchedVolumeIdentity; self.watchedRoots = watchedRoots; self.recoveryStartedAt = recoveryStartedAt; self.recoveryEndedAt = recoveryEndedAt; self.eventsReplayed = eventsReplayed; self.duplicatesSuppressed = duplicatesSuppressed; self.userEventsDropped = userEventsDropped; self.kernelEventsDropped = kernelEventsDropped; self.rootChanged = rootChanged; self.volumeChanged = volumeChanged; self.missingIntervalStart = missingIntervalStart; self.missingIntervalEnd = missingIntervalEnd; self.fallbackBaselineAttempted = fallbackBaselineAttempted; self.fallbackBaselineResult = fallbackBaselineResult; self.evidenceCompleteness = evidenceCompleteness; self.detail = detail } }

public struct StorageIncident: Codable, Identifiable, Sendable {
    public var id: UUID; public var startedAt: Date; public var endedAt: Date?; public var trigger: IncidentTrigger; public var before: RecorderCapacitySample; public var after: RecorderCapacitySample?; public var completeness: EvidenceCompleteness; public var coverageGaps: [String]; public var measurements: [PathMeasurement]; public var newFiles: [FileGrowthEvidence]; public var expandedFiles: [FileGrowthEvidence]; public var processes: [ProcessEvidence]; public var tasks: [ScheduledTaskEvidence]; public var cloud: [CloudProviderEvidence]; public var filesystemEventRecovery: FilesystemEventRecovery?; public var repeatedPatterns: [RepeatedPattern]?; public var localCloudComparisons: [CopyComparisonResult]?; public var emergencyReserveActivity: EmergencyReserveStatus?; public var deepTraceEvidence: DeepTraceEvidence?; public var retentionControlState: String?; public var system: SystemAccounting; public var reportURLs: [URL]
    public init(id: UUID = UUID(), startedAt: Date = Date(), trigger: IncidentTrigger, before: RecorderCapacitySample, completeness: EvidenceCompleteness = .complete, coverageGaps: [String] = [], measurements: [PathMeasurement] = [], newFiles: [FileGrowthEvidence] = [], expandedFiles: [FileGrowthEvidence] = [], processes: [ProcessEvidence] = [], tasks: [ScheduledTaskEvidence] = [], cloud: [CloudProviderEvidence] = [], filesystemEventRecovery: FilesystemEventRecovery? = nil, repeatedPatterns: [RepeatedPattern]? = nil, localCloudComparisons: [CopyComparisonResult]? = nil, emergencyReserveActivity: EmergencyReserveStatus? = nil, deepTraceEvidence: DeepTraceEvidence? = nil, retentionControlState: String? = nil, system: SystemAccounting = SystemAccounting(), reportURLs: [URL] = []) { self.id = id; self.startedAt = startedAt; self.trigger = trigger; self.before = before; self.completeness = completeness; self.coverageGaps = coverageGaps; self.measurements = measurements; self.newFiles = newFiles; self.expandedFiles = expandedFiles; self.processes = processes; self.tasks = tasks; self.cloud = cloud; self.filesystemEventRecovery = filesystemEventRecovery; self.repeatedPatterns = repeatedPatterns; self.localCloudComparisons = localCloudComparisons; self.emergencyReserveActivity = emergencyReserveActivity; self.deepTraceEvidence = deepTraceEvidence; self.retentionControlState = retentionControlState; self.system = system; self.reportURLs = reportURLs }
    public var lossBytes: Int64 { max(0, (before.immediatelyFreeBytes ?? 0) - (after?.immediatelyFreeBytes ?? before.immediatelyFreeBytes ?? 0)) }
    public var explainedPercentage: Int { lossBytes == 0 ? 0 : min(100, Int((Double(system.explainedBytes) / Double(lossBytes)) * 100)) }
}

public struct DiagnosticOperation: Codable, Identifiable, Sendable {
    public var id: UUID
    public var type: String
    public var phase: String
    public var state: DiagnosticOperationState
    public var startedAt: Date
    public var endedAt: Date?
    public var processed: Int
    public var total: Int?
    public var bytes: Int64
    public var summary: String
    public var reportPath: String?
    public var currentSafePath: String?
    public var lastMeaningfulProgress: Date?
    public var cancellable: Bool?

    public init(id: UUID = UUID(), type: String, phase: String, state: DiagnosticOperationState, startedAt: Date, endedAt: Date?, processed: Int, total: Int?, bytes: Int64, summary: String, reportPath: String?, currentSafePath: String? = nil, lastMeaningfulProgress: Date? = nil, cancellable: Bool? = nil) {
        self.id = id
        self.type = type
        self.phase = phase
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.processed = processed
        self.total = total
        self.bytes = bytes
        self.summary = summary
        self.reportPath = reportPath
        self.currentSafePath = currentSafePath
        self.lastMeaningfulProgress = lastMeaningfulProgress
        self.cancellable = cancellable
    }

    public func elapsed(at now: Date = Date()) -> TimeInterval { max(0, (endedAt ?? now).timeIntervalSince(startedAt)) }
}

public enum IncidentTriggerEngine {
    public static func trigger(samples: [RecorderCapacitySample], preSleep: RecorderCapacitySample?, current: RecorderCapacitySample, settings: IncidentSettings = IncidentSettings()) -> IncidentTrigger? {
        guard let free = current.immediatelyFreeBytes else { return nil }
        if free < settings.emergencyBytes { return .below2GB }
        if free < settings.criticalBytes { return .below5GB }
        if free < settings.warningBytes { return .below10GB }
        let valid = samples.filter { $0.immediatelyFreeBytes != nil }.sorted { $0.timestamp < $1.timestamp }
        if let previous = valid.last, let previousFree = previous.immediatelyFreeBytes, previousFree - free >= settings.consecutiveLoss { return .consecutive512MiB }
        if let hour = valid.last(where: { current.timestamp.timeIntervalSince($0.timestamp) >= 3_600 }), let then = hour.immediatelyFreeBytes, then - free >= settings.hourlyLoss { return .oneHour1GiB }
        if let six = valid.last(where: { current.timestamp.timeIntervalSince($0.timestamp) >= 21_600 }), let then = six.immediatelyFreeBytes, then - free >= settings.sixHourLoss { return .sixHours2GiB }
        if let preSleep, let then = preSleep.immediatelyFreeBytes, then - free >= settings.consecutiveLoss { return .postWake512MiB }
        return nil
    }
}

public enum ChangedPathCoalescer {
    public static func ancestor(for path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        if let build = components.firstIndex(of: ".build") { return NSString.path(withComponents: Array(components.prefix(build + 1))) }
        if let support = components.firstIndex(of: "Application Support"), components.count > support + 1 { return NSString.path(withComponents: Array(components.prefix(support + 2))) }
        if let cache = components.firstIndex(of: "Caches"), components.count > cache + 1 { return NSString.path(withComponents: Array(components.prefix(cache + 2))) }
        if path.hasPrefix("/opt/homebrew"), components.count > 3 { return NSString.path(withComponents: Array(components.prefix(4))) }
        return NSString.path(withComponents: Array(components.prefix(min(5, components.count))))
    }
    public static func coalesce(_ paths: [String], limit: Int = 200) -> [String] { Array(Set(paths.map(ancestor(for:))).sorted().prefix(limit)) }
}

public enum FocusedAllocationMeasurer {
    /// Metadata-only, bounded, no symlink following and no filesystem crossing. Cloud placeholders are never opened.
    public static func measure(root: URL, limit: Int = 10_000, deadline: TimeInterval = 90, classification: DiagnosticClassification = .unresolved, isCancelled: @Sendable () -> Bool = { Task.isCancelled }) -> PathMeasurement {
        let start = Date(); let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: root.path) else { return PathMeasurement(path: root.path, classification: classification, complete: .unavailable, issue: "Path unavailable") }
        let rootFS = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isSparseKey, .mayShareFileContentKey, .isUbiquitousItemKey, .volumeIdentifierKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return PathMeasurement(path: root.path, classification: classification, complete: .unavailable, issue: "Cannot enumerate root") }
        var allocated: Int64 = 0, logical: Int64 = 0, placeholders: Int64 = 0, entries = 0, sparse = false, shared = false, partial = false
        while let url = enumerator.nextObject() as? URL {
            entries += 1
            if entries > limit || Date().timeIntervalSince(start) > deadline || isCancelled() { partial = true; break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { partial = true; continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if let system = (try? fm.attributesOfItem(atPath: url.path)[.systemNumber] as? NSNumber)?.uint64Value, rootFS != nil, system != rootFS { enumerator.skipDescendants(); partial = true; continue }
            guard values.isRegularFile == true else { continue }
            let fileLogical = Int64(values.fileSize ?? 0); logical += fileLogical
            let fileAllocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            // A ubiquitous item with no allocation is treated as a metadata-only placeholder.
            // This avoids the prior logical-size-as-local-size error without reading content.
            if values.isUbiquitousItem == true && fileAllocated == 0 && fileLogical > 0 { placeholders += fileLogical; continue }
            allocated += fileAllocated
            sparse = sparse || values.isSparse == true; shared = shared || values.mayShareFileContent == true
        }
        return PathMeasurement(path: root.path, classification: classification, allocatedBytes: allocated, logicalBytes: logical, sparse: sparse, mayShareContent: shared, placeholderBytes: placeholders, complete: partial ? .partial : .complete, issue: partial ? "Enumeration bound, cancellation, or inaccessible child limited the result." : nil)
    }
}

public enum DiagnosticCatalog {
    public static func roots(home: String = NSHomeDirectory()) -> [(String, DiagnosticClassification)] {
        [("\(home)/Library/Application Support", .applicationState), ("\(home)/Library/Caches", .cache), ("\(home)/Library/Developer", .buildOutput), ("\(home)/.cache", .cache), ("\(home)/.codex", .applicationState), ("\(home)/.gemini", .applicationState), ("\(home)/.antigravity", .applicationState), ("\(home)/.antigravity_archive", .applicationState), ("\(home)/.Trash", .trash), ("/private/var/vm", .swap), ("/opt/homebrew", .applicationState), ("\(home)/Library/Application Support/CloudDocs", .providerDatabase), ("\(home)/Library/Application Support/FileProvider", .providerDatabase), ("\(home)/Library/Application Support/Google/DriveFS", .providerCache), ("\(home)/Library/CloudStorage", .cloudPlaceholder)]
    }
}

// MARK: - Durable local store

public final class IncidentStore: @unchecked Sendable {
    public let directory: URL; private let lock = NSLock(); private let encoder = JSONEncoder(); private let decoder = JSONDecoder()
    public init(home: String = NSHomeDirectory()) { directory = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/DexCleaner/IncidentRecorder", isDirectory: true); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601 }
    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
    public func load<T: Codable>(_ type: T.Type, named name: String, fallback: T) -> T { lock.lock(); defer { lock.unlock() }; guard let data = try? Data(contentsOf: file(name)), let value = try? decoder.decode(T.self, from: data) else { return fallback }; return value }
    public func save<T: Codable>(_ value: T, named name: String) throws { lock.lock(); defer { lock.unlock() }; try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try encoder.encode(value).write(to: file(name), options: .atomic) }
    public func appendEvent(_ event: FSEventEvidence) throws { lock.lock(); defer { lock.unlock() }; try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); let data = try encoder.encode(event) + Data([10]); let url = file("events-v1.jsonl"); let retained = file("events-v1.previous.jsonl"); if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value, size + Int64(data.count) > 64 * 1_024 * 1_024 { if FileManager.default.fileExists(atPath: retained.path) { try FileManager.default.removeItem(at: retained) }; try FileManager.default.moveItem(at: url, to: retained) }; if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }; let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize() }
    public func readCheckpoint() -> (FSEventsCheckpoint?, Bool) { lock.lock(); defer { lock.unlock() }; let url = file("fsevents-checkpoint-v1.json"); guard FileManager.default.fileExists(atPath: url.path) else { return (nil, false) }; do { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; let value = try decoder.decode(FSEventsCheckpoint.self, from: Data(contentsOf: url)); guard value.schemaVersion == 1 else { throw NSError(domain: "DexCleaner", code: 1) }; return (value, false) } catch { return (nil, true) } }
    @discardableResult public func preserveCorruptCheckpoint(at date: Date = Date()) -> Bool { lock.lock(); defer { lock.unlock() }; let source = file("fsevents-checkpoint-v1.json"); guard FileManager.default.fileExists(atPath: source.path) else { return false }; let destination = file("fsevents-checkpoint-corrupt-\(Int(date.timeIntervalSince1970)).json"); do { try FileManager.default.copyItem(at: source, to: destination); return true } catch { return false } }
    public func loadCheckpoint() -> (FSEventsCheckpoint?, Bool) { let result = readCheckpoint(); if result.1 { _ = preserveCorruptCheckpoint() }; return result }
    public func saveCheckpoint(_ value: FSEventsCheckpoint) throws { try save(value, named: "fsevents-checkpoint-v1.json") }
    public func sizeBytes() -> Int64 { (try? FileManager.default.allocatedSize(ofDirectoryAt: directory)) ?? 0 }
}

public extension FileManager { func allocatedSize(ofDirectoryAt url: URL) throws -> Int64 { guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsPackageDescendants]) else { return 0 }; var total: Int64 = 0; for case let item as URL in enumerator { total += Int64((try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }; return total } }

// MARK: - Recorder, FSEvents, reports, reserve

public struct FSEventsStreamConfiguration: Sendable, Equatable {
    public var roots: [String]
    public var startingEventID: UInt64
    public var latency: TimeInterval
    public var flags: UInt32

    public init(roots: [String], startingEventID: UInt64, latency: TimeInterval = 1, flags: UInt32) {
        self.roots = roots
        self.startingEventID = startingEventID
        self.latency = latency
        self.flags = flags
    }
}

public protocol FSEventsStreamHandle: AnyObject, Sendable {
    func start() -> Bool
    func stop()
    func invalidate()
    func release()
}

public typealias FSEventsStreamDelivery = @Sendable ([FSEventEvidence]) -> Void
public typealias FSEventsStreamFactory = @Sendable (FSEventsStreamConfiguration, @escaping FSEventsStreamDelivery) -> (any FSEventsStreamHandle)?

#if os(macOS)
private final class NativeFSEventsCallbackBox: @unchecked Sendable {
    let delivery: FSEventsStreamDelivery
    init(delivery: @escaping FSEventsStreamDelivery) { self.delivery = delivery }
}

private final class NativeFSEventsStreamHandle: FSEventsStreamHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var nativeStream: FSEventStreamRef?
    private let callbackBox: NativeFSEventsCallbackBox
    private let queue = DispatchQueue(label: "DexCleaner.FSEvents.Native")
    private var started = false
    private var invalidated = false
    private var released = false

    init?(configuration: FSEventsStreamConfiguration, delivery: @escaping FSEventsStreamDelivery) {
        callbackBox = NativeFSEventsCallbackBox(delivery: delivery)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            guard let info else { return }
            let box = Unmanaged<NativeFSEventsCallbackBox>.fromOpaque(info).takeUnretainedValue()
            let pathArray = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let evidence = (0..<Int(count)).map { index in
                let path = index < pathArray.count ? pathArray[index] : ""
                return FSEventEvidence(
                    eventID: ids[index],
                    path: path,
                    flags: flags[index],
                    ancestor: ChangedPathCoalescer.ancestor(for: path)
                )
            }
            box.delivery(evidence)
        }
        nativeStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            configuration.roots as CFArray,
            FSEventStreamEventId(configuration.startingEventID),
            configuration.latency,
            configuration.flags
        )
        guard nativeStream != nil else { return nil }
    }

    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let nativeStream, !started, !invalidated, !released else { return false }
        FSEventStreamSetDispatchQueue(nativeStream, queue)
        started = FSEventStreamStart(nativeStream)
        return started
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let nativeStream, started, !released else { return }
        FSEventStreamStop(nativeStream)
        started = false
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        guard let nativeStream, !invalidated, !released else { return }
        FSEventStreamInvalidate(nativeStream)
        invalidated = true
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard let nativeStream, !released else { return }
        FSEventStreamRelease(nativeStream)
        self.nativeStream = nil
        released = true
    }

    deinit {
        stop()
        invalidate()
        release()
    }
}

private enum NativeFSEventsStreamFactory {
    static func make(configuration: FSEventsStreamConfiguration, delivery: @escaping FSEventsStreamDelivery) -> (any FSEventsStreamHandle)? {
        NativeFSEventsStreamHandle(configuration: configuration, delivery: delivery)
    }
}
#endif

public struct FSEventsRecoveryDependencies: Sendable {
    public var now: @Sendable () -> Date
    public var currentVolumeIdentity: @Sendable (DiskStatus) -> String
    public var loadCheckpoint: @Sendable (IncidentStore) -> (FSEventsCheckpoint?, Bool)
    public var saveCheckpoint: @Sendable (IncidentStore, FSEventsCheckpoint) throws -> Void
    public var appendEvidence: @Sendable (IncidentStore, FSEventEvidence) throws -> Void
    public var preserveCorruptCheckpoint: @Sendable (IncidentStore, Date) -> Bool
    public var replayAvailable: @Sendable (UInt64) -> Bool
    public var boundedFallbackBaseline: @Sendable (DiskStatus) -> String
    public var updateIncidentRecovery: @Sendable (inout StorageIncident, FilesystemEventRecovery) -> Void
    public var systemSnapshot: @Sendable () -> SystemAccounting
    public var makeActivity: @Sendable (String, String, DiagnosticOperationState, Date, String) -> DiagnosticOperation
    public var makeStream: FSEventsStreamFactory

    public init(
        now: @escaping @Sendable () -> Date,
        currentVolumeIdentity: @escaping @Sendable (DiskStatus) -> String,
        loadCheckpoint: @escaping @Sendable (IncidentStore) -> (FSEventsCheckpoint?, Bool),
        saveCheckpoint: @escaping @Sendable (IncidentStore, FSEventsCheckpoint) throws -> Void,
        appendEvidence: @escaping @Sendable (IncidentStore, FSEventEvidence) throws -> Void,
        preserveCorruptCheckpoint: @escaping @Sendable (IncidentStore, Date) -> Bool,
        replayAvailable: @escaping @Sendable (UInt64) -> Bool = { _ in true },
        boundedFallbackBaseline: @escaping @Sendable (DiskStatus) -> String = { _ in "Lightweight capacity baseline retained" },
        updateIncidentRecovery: @escaping @Sendable (inout StorageIncident, FilesystemEventRecovery) -> Void = { $0.filesystemEventRecovery = $1 },
        systemSnapshot: @escaping @Sendable () -> SystemAccounting = {
            let home = NSHomeDirectory()
            var accounting = SystemAccounting()
            accounting.trashBytes = FocusedAllocationMeasurer.measure(root: URL(fileURLWithPath: "\(home)/.Trash"), limit: 2_000, deadline: 10, classification: .trash).allocatedBytes
            accounting.swapBytes = FocusedAllocationMeasurer.measure(root: URL(fileURLWithPath: "/private/var/vm"), limit: 2_000, deadline: 10, classification: .swap).allocatedBytes
            accounting.dexCleanerBytes = FocusedAllocationMeasurer.measure(root: URL(fileURLWithPath: "\(home)/Library/Application Support/DexCleaner"), limit: 10_000, deadline: 10, classification: .applicationState).allocatedBytes
            return accounting
        },
        makeActivity: @escaping @Sendable (String, String, DiagnosticOperationState, Date, String) -> DiagnosticOperation = {
            DiagnosticOperation(type: $0, phase: $1, state: $2, startedAt: $3, endedAt: $2 == .running ? nil : $3, processed: 0, total: nil, bytes: 0, summary: $4, reportPath: nil)
        },
        makeStream: @escaping FSEventsStreamFactory = { _, _ in nil }
    ) {
        self.now = now
        self.currentVolumeIdentity = currentVolumeIdentity
        self.loadCheckpoint = loadCheckpoint
        self.saveCheckpoint = saveCheckpoint
        self.appendEvidence = appendEvidence
        self.preserveCorruptCheckpoint = preserveCorruptCheckpoint
        self.replayAvailable = replayAvailable
        self.boundedFallbackBaseline = boundedFallbackBaseline
        self.updateIncidentRecovery = updateIncidentRecovery
        self.systemSnapshot = systemSnapshot
        self.makeActivity = makeActivity
        self.makeStream = makeStream
    }

    public static let live = FSEventsRecoveryDependencies(
        now: { Date() },
        currentVolumeIdentity: { $0.filesystem },
        loadCheckpoint: { $0.readCheckpoint() },
        saveCheckpoint: { try $0.saveCheckpoint($1) },
        appendEvidence: { try $0.appendEvent($1) },
        preserveCorruptCheckpoint: { $0.preserveCorruptCheckpoint(at: $1) },
        makeStream: {
            #if os(macOS)
            return NativeFSEventsStreamFactory.make(configuration: $0, delivery: $1)
            #else
            return nil
            #endif
        }
    )
}

@MainActor public final class StorageIncidentRecorder: ObservableObject {
    @Published public private(set) var status: RecorderStatus = .armed
    @Published public private(set) var activeIncident: StorageIncident?
    @Published public private(set) var incidents: [StorageIncident] = []
    @Published public private(set) var operations: [DiagnosticOperation] = []
    @Published public private(set) var repeatedPattern: RepeatedPattern?
    @Published public private(set) var localCloudComparisons: [CopyComparisonResult] = []
    @Published public private(set) var lastEventID: UInt64 = 0
    @Published public private(set) var coverage: String = "Starting recorder"
    @Published public private(set) var reserveState: String = "Pending Safe Conditions"
    public var filesystemEventRecoveryState: FilesystemEventRecovery { recoveryRecord }
    public let settings: IncidentSettings; public let store: IncidentStore; private let recoveryDependencies: FSEventsRecoveryDependencies
    private var samples: [RecorderCapacitySample] = []; private var sleepCheckpoint: RecorderCapacitySample?; private var timer: Timer?; private var stableSince: Date?; private var eventCheckpoint: FSEventsCheckpoint?; private var duplicateEvents = 0; private var recoveryRecord = FilesystemEventRecovery()
    private var stream: (any FSEventsStreamHandle)?
    private var currentWatchedRoots: [String] = []
    private var streamLifecycleEnabled = false
    public init(store: IncidentStore = IncidentStore(), settings: IncidentSettings = IncidentSettings(), recoveryDependencies: FSEventsRecoveryDependencies = .live) { self.store = store; self.settings = settings; self.recoveryDependencies = recoveryDependencies; incidents = store.load([StorageIncident].self, named: "incidents-v1.json", fallback: []); samples = store.load([RecorderCapacitySample].self, named: "capacity-v2.json", fallback: []); operations = store.load([DiagnosticOperation].self, named: "activity-v1.json", fallback: []) }
    deinit {
        timer?.invalidate()
        if let stream {
            stream.stop()
            stream.invalidate()
            stream.release()
        }
    }
    public func start(sample: DiskStatus) {
        startRecovery(sample: sample, roots: watchedRoots(), startStream: true)
        ingest(status: sample, trigger: "Application launch")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.ingest(status: StorageCapacityProvider.measure(), trigger: "Five-minute periodic sample")
            }
        }
    }

    public func startRecovery(sample: DiskStatus, roots: [String], startStream: Bool = false) {
        status = .recording
        currentWatchedRoots = roots
        streamLifecycleEnabled = streamLifecycleEnabled || startStream
        let now = recoveryDependencies.now()
        let volume = recoveryDependencies.currentVolumeIdentity(sample)
        let loaded = recoveryDependencies.loadCheckpoint(store)
        let operation = beginOperation("FSEvents recovery", phase: "Validating durable checkpoint", total: nil)

        if loaded.1 {
            let preserved = recoveryDependencies.preserveCorruptCheckpoint(store, now)
            recoveryRecord = FilesystemEventRecovery(
                outcome: preserved ? .storeRecoveredAfterCorruption : .storedCheckpointInvalid,
                watchedVolumeIdentity: volume,
                watchedRoots: roots,
                recoveryStartedAt: now,
                missingIntervalStart: nil,
                missingIntervalEnd: now,
                fallbackBaselineAttempted: true,
                fallbackBaselineResult: recoveryDependencies.boundedFallbackBaseline(sample),
                evidenceCompleteness: .partial,
                detail: preserved ? "The corrupt checkpoint was preserved before a fresh baseline was written." : "The invalid checkpoint could not be preserved; a fresh baseline is required."
            )
            establishFreshBaseline(volume: volume, roots: roots, sample: sample, outcome: recoveryRecord.outcome, operation: operation, startStream: startStream)
            return
        }

        guard let checkpoint = loaded.0 else {
            recoveryRecord = FilesystemEventRecovery(
                outcome: .freshBaselineRequired,
                watchedVolumeIdentity: volume,
                watchedRoots: roots,
                recoveryStartedAt: now,
                missingIntervalEnd: now,
                fallbackBaselineAttempted: true,
                fallbackBaselineResult: recoveryDependencies.boundedFallbackBaseline(sample),
                evidenceCompleteness: .partial
            )
            establishFreshBaseline(volume: volume, roots: roots, sample: sample, outcome: .freshBaselineRequired, operation: operation, startStream: startStream)
            return
        }

        let outcome: FSEventsRecoveryOutcome?
        if checkpoint.schemaVersion != 1 || checkpoint.eventID == 0 {
            outcome = .storedCheckpointInvalid
        } else if checkpoint.volumeID != volume {
            outcome = .volumeChanged
        } else if checkpoint.roots != roots {
            outcome = .rootChanged
        } else if !recoveryDependencies.replayAvailable(checkpoint.eventID) {
            outcome = .historyUnavailable
        } else {
            outcome = nil
        }

        if let outcome {
            recoveryRecord = FilesystemEventRecovery(
                outcome: outcome,
                storedCheckpointEventID: checkpoint.eventID,
                requestedResumeEventID: nil,
                watchedVolumeIdentity: volume,
                watchedRoots: roots,
                recoveryStartedAt: now,
                missingIntervalStart: checkpoint.eventTimestamp,
                missingIntervalEnd: now,
                fallbackBaselineAttempted: true,
                fallbackBaselineResult: recoveryDependencies.boundedFallbackBaseline(sample),
                evidenceCompleteness: .partial,
                detail: "Durable continuity could not be claimed; a bounded capacity baseline was retained."
            )
            establishFreshBaseline(volume: volume, roots: roots, sample: sample, outcome: outcome, operation: operation, startStream: startStream)
            return
        }

        eventCheckpoint = checkpoint
        lastEventID = checkpoint.eventID
        recoveryRecord = FilesystemEventRecovery(
            outcome: .resumedCompletely,
            storedCheckpointEventID: checkpoint.eventID,
            requestedResumeEventID: checkpoint.eventID,
            watchedVolumeIdentity: volume,
            watchedRoots: roots,
            recoveryStartedAt: now,
            evidenceCompleteness: .complete
        )
        coverage = "FSEvents recovery requested from \(checkpoint.eventID)"
        if startStream {
            startFSEvents(from: checkpoint.eventID, roots: roots)
        }
        finishOperation(operation, state: .complete, summary: "Recovery requested from durable event \(checkpoint.eventID).")
    }

    private func establishFreshBaseline(volume: String, roots: [String], sample: DiskStatus, outcome: FSEventsRecoveryOutcome, operation: UUID, startStream: Bool) {
        let now = recoveryDependencies.now()
        let checkpoint = FSEventsCheckpoint(
            volumeID: volume,
            deviceID: volume,
            eventID: 0,
            eventTimestamp: now,
            roots: roots,
            checkpointedAt: now,
            lastRecovery: outcome
        )
        do {
            try recoveryDependencies.saveCheckpoint(store, checkpoint)
            eventCheckpoint = checkpoint
            lastEventID = 0
            status = .partialCoverage
            coverage = "\(outcome.rawValue); fresh baseline active"
            finishOperation(operation, state: .partial, summary: "\(outcome.rawValue). A lightweight baseline was retained.")
        } catch {
            eventCheckpoint = nil
            status = .partialCoverage
            recoveryRecord.evidenceCompleteness = .failed
            recoveryRecord.detail = "Fresh-baseline checkpoint persistence failed: \(error.localizedDescription). Recorder remains operational."
            coverage = "FSEvents checkpoint persistence failed; recorder remains operational"
            finishOperation(operation, state: .failed, summary: recoveryRecord.detail)
        }
        if startStream {
            #if os(macOS)
            startFSEvents(from: UInt64(kFSEventStreamEventIdSinceNow), roots: roots)
            #else
            startFSEvents(from: UInt64.max, roots: roots)
            #endif
        }
    }
    public func pause() { timer?.invalidate(); timer = nil; teardownStream(); status = .paused; coverage = "Recorder paused by user" }
    public func beforeSleep(status: DiskStatus) {
        if var checkpoint = eventCheckpoint {
            checkpoint.cleanShutdown = true
            checkpoint.checkpointedAt = recoveryDependencies.now()
            do {
                try recoveryDependencies.saveCheckpoint(store, checkpoint)
                eventCheckpoint = checkpoint
            } catch {
                self.status = .partialCoverage
                coverage = "Sleep checkpoint failed; wake continuity will be Partial"
            }
        }
        sleepCheckpoint = RecorderCapacitySample(status: status, trigger: "Before sleep", wakeState: "Sleeping", now: recoveryDependencies.now())
        ingest(sample: sleepCheckpoint!)
        teardownStream()
    }

    public func afterWake(status: DiskStatus) {
        let now = recoveryDependencies.now()
        let volume = recoveryDependencies.currentVolumeIdentity(status)
        if eventCheckpoint?.volumeID != volume {
            self.status = .partialCoverage
            coverage = "FSEvents volume changed after wake; fresh baseline required"
            recoveryRecord.outcome = .volumeChanged
            recoveryRecord.volumeChanged = true
            recoveryRecord.missingIntervalStart = sleepCheckpoint?.timestamp
            recoveryRecord.missingIntervalEnd = now
            recoveryRecord.evidenceCompleteness = .partial
            let checkpoint = FSEventsCheckpoint(volumeID: volume, deviceID: volume, eventTimestamp: now, roots: watchedRoots(), checkpointedAt: now, lastRecovery: .volumeChanged)
            try? recoveryDependencies.saveCheckpoint(store, checkpoint)
            eventCheckpoint = checkpoint
            lastEventID = 0
            if streamLifecycleEnabled {
                #if os(macOS)
                replaceFSEvents(from: UInt64(kFSEventStreamEventIdSinceNow), roots: watchedRoots())
                #else
                replaceFSEvents(from: UInt64.max, roots: watchedRoots())
                #endif
            }
        } else if sleepCheckpoint == nil {
            recoveryRecord.outcome = .resumedWithBoundedGap
            recoveryRecord.missingIntervalEnd = now
            recoveryRecord.evidenceCompleteness = .partial
            coverage = "Wake observed without a durable pre-sleep sample"
            if streamLifecycleEnabled { replaceFSEvents(from: eventCheckpoint?.eventID ?? lastEventID, roots: watchedRoots()) }
        } else {
            if streamLifecycleEnabled { replaceFSEvents(from: eventCheckpoint?.eventID ?? lastEventID, roots: watchedRoots()) }
        }
        ingest(status: status, trigger: "After wake", wakeState: "Woke")
        if let activeIncident { complete(activeIncident, after: samples.last) }
    }
    public func ingest(status: DiskStatus, trigger: String, wakeState: String = "Active") { ingest(sample: RecorderCapacitySample(status: status, trigger: trigger, wakeState: wakeState, incidentID: activeIncident?.id)) }
    public func ingest(sample: RecorderCapacitySample) { samples.append(sample); samples = Array(samples.suffix(210_000)); try? store.save(samples, named: "capacity-v2.json"); if activeIncident == nil, let trigger = IncidentTriggerEngine.trigger(samples: Array(samples.dropLast()), preSleep: sleepCheckpoint, current: sample, settings: settings) { open(trigger: trigger, sample: sample) }; if let incident = activeIncident, incident.startedAt.addingTimeInterval(settings.stableSeconds) <= sample.timestamp, let before = incident.before.immediatelyFreeBytes, let now = sample.immediatelyFreeBytes, now >= before - settings.consecutiveLoss { complete(incident, after: sample) }; reserveState = EmergencyReserveController.eligibility(status: sample, incidentActive: activeIncident != nil, stableSince: stableSince) }
    public func investigateNow(status: DiskStatus) { ingest(status: status, trigger: IncidentTrigger.manual.rawValue); if activeIncident == nil, let sample = samples.last { open(trigger: .manual, sample: sample) } }
    private func open(trigger: IncidentTrigger, sample: RecorderCapacitySample) { var incident = StorageIncident(trigger: trigger, before: sample); recoveryDependencies.updateIncidentRecovery(&incident, recoveryRecord); incident.coverageGaps = samples.count < 2 ? ["Insufficient prior capacity sample coverage."] : []; if recoveryRecord.evidenceCompleteness != .complete { incident.coverageGaps.append("Filesystem event recovery: \(recoveryRecord.outcome.rawValue)") }; incident.completeness = incident.coverageGaps.isEmpty ? .complete : .partial; activeIncident = incident; status = .investigating; _ = beginOperation("Incident investigation", phase: "Collecting changed paths", total: nil); snapshotSystem(into: &incident); activeIncident = incident }
    public func investigateChangedRoots(_ roots: [String], deadline: TimeInterval = 90, isCancelled: @Sendable () -> Bool = { false }) { guard var incident = activeIncident else { return }; updateOperation(phase: "Measuring allocation", processed: 0, total: roots.count); var measured: [PathMeasurement] = []; for root in roots.prefix(200) { if isCancelled() { break }; let pair = DiagnosticCatalog.roots().first { $0.0 == root }; measured.append(FocusedAllocationMeasurer.measure(root: URL(fileURLWithPath: root), deadline: deadline, classification: pair?.1 ?? .unresolved, isCancelled: isCancelled)) }; incident.measurements = measured; incident.system.explainedBytes = measured.reduce(0) { $0 + max(0, $1.allocatedBytes) }; incident.system.unexplainedBytes = max(0, incident.lossBytes - incident.system.explainedBytes); if isCancelled() || measured.count < min(200, roots.count) || measured.contains(where: { $0.complete != .complete }) { incident.completeness = .partial }; incident.processes = ProcessAttribution.snapshot(); incident.tasks = ScheduledTaskInspector.inspect(); activeIncident = incident; updateOperation(phase: isCancelled() ? "Cancelled with partial evidence retained" : "Correlating processes", processed: measured.count, total: roots.count); if isCancelled(), let operation = operations.first { finishOperation(operation.id, state: .cancelled, summary: "Focused investigation cancelled safely; measured evidence was retained.") } }
    public func inspectCloud() -> [CloudProviderEvidence] { let op = beginOperation("Cloud Storage Inspector", phase: "Inspecting cloud metadata", total: 4); let home = NSHomeDirectory(); let entries = [("Cloud roots", "\(home)/Library/CloudStorage", DiagnosticClassification.cloudPlaceholder), ("CloudDocs", "\(home)/Library/Application Support/CloudDocs", DiagnosticClassification.providerDatabase), ("File Provider", "\(home)/Library/Application Support/FileProvider", DiagnosticClassification.providerDatabase), ("Google Drive", "\(home)/Library/Application Support/Google/DriveFS", DiagnosticClassification.providerCache)]; let result = entries.map { name, path, kind -> CloudProviderEvidence in let m = FocusedAllocationMeasurer.measure(root: URL(fileURLWithPath: path), limit: 10_000, deadline: 60, classification: kind); return CloudProviderEvidence(provider: name, accountLabel: nil, domainIdentifier: nil, root: path, state: kind == .cloudPlaceholder ? "Placeholder-aware" : kind.rawValue, logicalBytes: m.logicalBytes, allocatedUserBytes: kind == .cloudPlaceholder ? m.allocatedBytes : 0, placeholderBytes: m.placeholderBytes, downloadedBytes: max(0, m.allocatedBytes), pinnedBytes: 0, cacheBytes: kind == .providerCache ? m.allocatedBytes : 0, databaseBytes: kind == .providerDatabase ? m.allocatedBytes : 0, completeness: m.complete, safeAction: "Reveal in Finder or use provider settings; DexCleaner does not mutate provider state.") }; if var incident = activeIncident { incident.cloud = result; activeIncident = incident }; finishOperation(op, state: result.contains(where: { $0.completeness != .complete }) ? .partial : .complete, summary: "Cloud inspection completed without opening file contents or materializing placeholders."); return result }
    public func finishActiveIncident(status: DiskStatus) -> [URL] { guard let incident = activeIncident else { return [] }; ingest(status: status, trigger: "Incident completion"); complete(incident, after: samples.last); return incidents.first(where: { $0.id == incident.id })?.reportURLs ?? [] }
    public func refreshRepeatedPattern() {
        let op = beginOperation("Repeated-pattern analysis", phase: "Comparing persisted incident evidence", total: incidents.count)
        let result = RepeatedPatternClassifier.classify(incidents, now: recoveryDependencies.now())
        repeatedPattern = result
        if !incidents.isEmpty {
            incidents[0].repeatedPatterns = [result]
            try? store.save(incidents, named: "incidents-v1.json")
        }
        let state: DiagnosticOperationState = result.evidenceCompleteness == .complete ? .complete : .partial
        finishOperation(op, state: state, summary: "\(result.kind.rawValue); \(result.occurrences) occurrences. Diagnostic only.")
    }

    public func compareLocalAndCloud(local: URL, cloud: URL, provider: String, lowSpace: Bool, providerMode: ProviderMode = .ordinary, isCancelled: @Sendable () -> Bool = { false }) {
        let op = beginOperation("Local/cloud comparison", phase: "Comparing resident metadata", total: nil)
        let result = LocalCloudComparator.compare(local: local, cloud: cloud, provider: provider, providerMode: providerMode, lowSpace: lowSpace, isCancelled: isCancelled)
        localCloudComparisons = [result]
        if var incident = activeIncident {
            incident.localCloudComparisons = [result]
            activeIncident = incident
        } else if !incidents.isEmpty {
            incidents[0].localCloudComparisons = [result]
            try? store.save(incidents, named: "incidents-v1.json")
        }
        let state: DiagnosticOperationState = result.coverage == .complete ? .complete : (result.coverage == .cancelled ? .cancelled : .partial)
        finishOperation(op, state: state, summary: "\(result.classification.rawValue). No cloud-provider state changed.")
    }

    public func setComparisonDisposition(_ disposition: CopyDisposition) {
        guard !localCloudComparisons.isEmpty else { return }
        localCloudComparisons[0].disposition = disposition
        if var incident = activeIncident {
            incident.localCloudComparisons = localCloudComparisons
            activeIncident = incident
        } else if !incidents.isEmpty {
            incidents[0].localCloudComparisons = localCloudComparisons
            try? store.save(incidents, named: "incidents-v1.json")
        }
        let op = beginOperation("Local/cloud comparison", phase: "Recording user disposition", total: 1)
        finishOperation(op, state: .complete, summary: "\(disposition.rawValue). No filesystem location was modified.")
    }

    public func recordComparisonResult(_ result: CopyComparisonResult, operationID: UUID? = nil) {
        localCloudComparisons = [result]
        if var incident = activeIncident {
            incident.localCloudComparisons = [result]
            activeIncident = incident
        } else if !incidents.isEmpty {
            incidents[0].localCloudComparisons = [result]
            try? store.save(incidents, named: "incidents-v1.json")
        }
        if let operationID {
            let state: DiagnosticOperationState = result.coverage == .complete ? .complete : (result.coverage == .cancelled ? .cancelled : .partial)
            finishOperation(operationID, state: state, summary: "\(result.classification.rawValue). No cloud-provider state changed.")
        }
    }

    public func requestCancellation() {
        guard let index = operations.firstIndex(where: { $0.state == .running && $0.cancellable == true }) else { return }
        operations[index].state = .cancelling
        operations[index].phase = "Stopping at a safe boundary"
        operations[index].lastMeaningfulProgress = recoveryDependencies.now()
        try? store.save(operations, named: "activity-v1.json")
    }

    @discardableResult public func createEmergencyReserve(
        home: URL,
        freeBytes: Int64,
        stable: Bool,
        target: Int64 = EmergencyReserveController.productionTargetBytes,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> EmergencyReserveStatus {
        let op = beginOperation("Emergency reserve", phase: "Creating physically allocated reserve", total: nil)
        do {
            let result = try EmergencyReserveController.create(
                injectedHome: home, freeBytes: freeBytes, stable: stable,
                incidentActive: activeIncident != nil,
                activeOperation: operations.contains { $0.id != op && $0.state == .running },
                target: target, now: recoveryDependencies.now(),
                freeCapacity: { StorageCapacityProvider.measure().immediatelyFreeBytes },
                isCancelled: isCancelled
            )
            reserveState = result.state.rawValue
            attachReserve(result)
            finishOperation(op, state: result.state == .ready ? .complete : .partial, summary: "\(result.state.rawValue): \(result.eligibilityReason)")
            return result
        } catch {
            let cancelled = error is CancellationError
            let result = EmergencyReserveStatus(state: cancelled ? .pending : .failed, targetBytes: target, eligibilityReason: cancelled ? "Creation cancelled before atomic finalization" : "Creation failed", failureReason: error.localizedDescription)
            reserveState = result.state.rawValue
            attachReserve(result)
            finishOperation(op, state: cancelled ? .cancelled : .failed, summary: cancelled ? "Reserve creation cancelled; temporary data removed and no final reserve was created." : error.localizedDescription)
            throw error
        }
    }

    @discardableResult public func releaseEmergencyReserve(home: URL) throws -> EmergencyReserveStatus {
        let op = beginOperation("Emergency reserve", phase: "Releasing exact DexCleaner reserve", total: 1)
        let result = try EmergencyReserveController.release(injectedHome: home, now: recoveryDependencies.now())
        reserveState = result.state.rawValue
        attachReserve(result)
        finishOperation(op, state: .complete, summary: "Reserve released; \(result.releasedBytes) bytes measured.")
        return result
    }

    public func handleEmergencyCapacity(home: URL, immediatelyFreeBytes: Int64?) {
        guard let free = immediatelyFreeBytes, free < settings.emergencyBytes,
              EmergencyReserveController.status(injectedHome: home)?.state == .ready else { return }
        _ = try? releaseEmergencyReserve(home: home)
    }

    @discardableResult public func runSyntheticDeepTrace(lines: [String], authorized: Bool, denied: Bool = false, cancelled: Bool = false, incidentPaths: [String] = []) -> DeepTraceEvidence {
        let op = beginOperation("Deep incident trace", phase: authorized ? "Filtering bounded metadata" : "Authorization required", total: nil)
        let result = DeepTraceController.synthetic(lines: lines, authorized: authorized, denied: denied, cancelled: cancelled, incidentPaths: incidentPaths, now: recoveryDependencies.now())
        recordDeepTraceEvidence(result, operation: op)
        return result
    }

    public func recordDeepTraceEvidence(_ result: DeepTraceEvidence) {
        let op = beginOperation("Deep incident trace", phase: "Recording bounded trace evidence", total: result.relevantOperations)
        recordDeepTraceEvidence(result, operation: op)
    }

    private func recordDeepTraceEvidence(_ result: DeepTraceEvidence, operation op: UUID) {
        if var incident = activeIncident {
            incident.deepTraceEvidence = result
            activeIncident = incident
        } else if !incidents.isEmpty {
            incidents[0].deepTraceEvidence = result
            try? store.save(incidents, named: "incidents-v1.json")
        }
        let state: DiagnosticOperationState = result.state == .complete ? .complete : (result.coverage == .cancelled ? .cancelled : .partial)
        finishOperation(op, state: state, summary: result.summary)
    }

    private func attachReserve(_ result: EmergencyReserveStatus) {
        if var incident = activeIncident {
            incident.emergencyReserveActivity = result
            activeIncident = incident
        } else if !incidents.isEmpty {
            incidents[0].emergencyReserveActivity = result
            try? store.save(incidents, named: "incidents-v1.json")
        }
    }

    public func recordEmergencyReserveStatus(_ result: EmergencyReserveStatus, operationID: UUID? = nil) {
        reserveState = result.state.rawValue
        attachReserve(result)
        if let operationID {
            let state: DiagnosticOperationState = result.state == .ready ? .complete : (result.eligibilityReason.localizedCaseInsensitiveContains("cancel") ? .cancelled : .partial)
            finishOperation(operationID, state: state, summary: result.failureReason ?? result.eligibilityReason)
        }
    }

    public func beginDiagnosticOperation(type: String, phase: String, total: Int? = nil) -> UUID {
        beginOperation(type, phase: phase, total: total)
    }

    public func finishDiagnosticOperation(_ id: UUID, state: DiagnosticOperationState, summary: String) {
        finishOperation(id, state: state, summary: summary)
    }

    private func complete(_ incident: StorageIncident, after: RecorderCapacitySample?) {
        var completed = activeIncident ?? incident
        completed.endedAt = after?.timestamp ?? recoveryDependencies.now()
        completed.after = after
        completed.system.unexplainedBytes = max(0, completed.lossBytes - completed.system.explainedBytes)
        incidents.removeAll { $0.id == completed.id }
        incidents.insert(completed, at: 0)
        incidents = Array(incidents.prefix(730))
        let pattern = RepeatedPatternClassifier.classify(incidents, now: recoveryDependencies.now())
        repeatedPattern = pattern
        completed.repeatedPatterns = [pattern]
        incidents[0] = completed
        let urls = (try? StorageIncidentReportWriter.write(completed, store: store)) ?? []
        completed.reportURLs = urls
        incidents[0] = completed
        try? store.save(incidents, named: "incidents-v1.json")
        activeIncident = nil
        status = completed.completeness == .complete ? .recording : .partialCoverage
        finishMostRecentOperation(summary: "Incident report ready")
    }
    private func snapshotSystem(into incident: inout StorageIncident) { incident.system = recoveryDependencies.systemSnapshot() }
    private func beginOperation(_ type: String, phase: String, total: Int?) -> UUID { var entry = recoveryDependencies.makeActivity(type, phase, .running, recoveryDependencies.now(), "Running"); entry.total = total; entry.cancellable = ["Local/cloud comparison", "Deep incident trace", "Emergency reserve", "Incident investigation"].contains(type); operations.insert(entry, at: 0); operations = Array(operations.prefix(100)); try? store.save(operations, named: "activity-v1.json"); return entry.id }
    private func updateOperation(phase: String, processed: Int, total: Int?) { guard !operations.isEmpty else { return }; operations[0].phase = phase; operations[0].processed = processed; operations[0].total = total; operations[0].lastMeaningfulProgress = recoveryDependencies.now(); try? store.save(operations, named: "activity-v1.json") }
    private func finishOperation(_ id: UUID, state: DiagnosticOperationState, summary: String) { guard let index = operations.firstIndex(where: { $0.id == id }) else { return }; operations[index].state = state; operations[index].endedAt = recoveryDependencies.now(); operations[index].summary = summary; try? store.save(operations, named: "activity-v1.json") }
    private func finishMostRecentOperation(summary: String) { guard let op = operations.first else { return }; finishOperation(op.id, state: activeIncident == nil ? .complete : .partial, summary: summary) }
    private func watchedRoots() -> [String] { [NSHomeDirectory(), "/Applications", "/Library", "/private/var", "/opt", "\(NSHomeDirectory())/.Trash", "\(NSHomeDirectory())/Library/CloudStorage"] }
    private func startFSEvents(from eventID: UInt64, roots: [String]) {
        guard stream == nil else { return }
        currentWatchedRoots = roots
        #if os(macOS)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        let sinceNow = UInt64(kFSEventStreamEventIdSinceNow)
        #else
        let flags: UInt32 = 0
        let sinceNow = UInt64.max
        #endif
        let configuration = FSEventsStreamConfiguration(roots: roots, startingEventID: eventID, latency: 1, flags: flags)
        let candidate = recoveryDependencies.makeStream(configuration) { [weak self] events in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for var event in events {
                    event.incidentID = self.activeIncident?.id
                    self.accept(event)
                }
            }
        }
        guard let candidate else {
            status = .partialCoverage
            coverage = "FSEvents stream creation failed; recorder remains operational"
            recoveryRecord.evidenceCompleteness = .failed
            recoveryRecord.detail = coverage
            recordRecoveryActivity(state: .failed, summary: coverage)
            return
        }
        stream = candidate
        guard candidate.start() else {
            candidate.stop()
            candidate.invalidate()
            candidate.release()
            stream = nil
            status = .partialCoverage
            coverage = "FSEvents stream start failed; recorder remains operational"
            recoveryRecord.evidenceCompleteness = .failed
            recoveryRecord.detail = coverage
            recordRecoveryActivity(state: .failed, summary: coverage)
            return
        }
        coverage = eventID == sinceNow ? "FSEvents active" : "FSEvents replay active"
    }

    private func replaceFSEvents(from eventID: UInt64, roots: [String]) {
        teardownStream()
        startFSEvents(from: eventID, roots: roots)
    }

    private func teardownStream() {
        guard let stream else { return }
        stream.stop()
        stream.invalidate()
        stream.release()
        self.stream = nil
    }

    public func restartRecoveryStreamForTesting(from eventID: UInt64, roots: [String]) {
        streamLifecycleEnabled = true
        replaceFSEvents(from: eventID, roots: roots)
    }
    public func acceptRecoveryEvent(_ event: FSEventEvidence) {
        accept(event)
    }

    private func accept(_ event: FSEventEvidence) {
        guard event.eventID > lastEventID else {
            duplicateEvents += 1
            recoveryRecord.duplicatesSuppressed = duplicateEvents
            recoveryRecord.outcome = .resumedWithDuplicatesSuppressed
            coverage = "FSEvents replay active; \(duplicateEvents) duplicates suppressed"
            attachRecoveryToIncident()
            return
        }

        do {
            // Ordering is deliberate: synchronized evidence, durable checkpoint,
            // in-memory resume ID, then incident and Activity Center state.
            try recoveryDependencies.appendEvidence(store, event)
            var checkpoint = eventCheckpoint ?? FSEventsCheckpoint(
                volumeID: event.volume,
                deviceID: event.volume,
                roots: recoveryRecord.watchedRoots,
                checkpointedAt: recoveryDependencies.now()
            )
            checkpoint.eventID = event.eventID
            checkpoint.eventTimestamp = event.timestamp
            checkpoint.checkpointedAt = recoveryDependencies.now()
            checkpoint.cleanShutdown = false
            checkpoint.lastRecovery = duplicateEvents > 0 ? .resumedWithDuplicatesSuppressed : .resumedCompletely
            try recoveryDependencies.saveCheckpoint(store, checkpoint)

            eventCheckpoint = checkpoint
            lastEventID = event.eventID
            recoveryRecord.firstReplayedEventID = recoveryRecord.firstReplayedEventID ?? event.eventID
            recoveryRecord.newestRecoveredEventID = event.eventID
            recoveryRecord.eventsReplayed += 1
            recoveryRecord.duplicatesSuppressed = duplicateEvents
            recoveryRecord.recoveryEndedAt = recoveryDependencies.now()
            recoveryRecord.outcome = duplicateEvents > 0 ? .resumedWithDuplicatesSuppressed : .resumedCompletely
            recoveryRecord.evidenceCompleteness = .complete

            #if os(macOS)
            let userDropped = event.flags & UInt32(kFSEventStreamEventFlagUserDropped) != 0
            let kernelDropped = event.flags & UInt32(kFSEventStreamEventFlagKernelDropped) != 0
            let rootChanged = event.flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0
            let boundedGap = event.flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0
            #else
            let userDropped = false, kernelDropped = false, rootChanged = false, boundedGap = false
            #endif

            if userDropped || kernelDropped || rootChanged || boundedGap {
                status = .partialCoverage
                recoveryRecord.userEventsDropped = recoveryRecord.userEventsDropped || userDropped
                recoveryRecord.kernelEventsDropped = recoveryRecord.kernelEventsDropped || kernelDropped
                recoveryRecord.rootChanged = recoveryRecord.rootChanged || rootChanged
                recoveryRecord.outcome = rootChanged ? .rootChanged : ((userDropped || kernelDropped) ? .eventsDropped : .resumedWithBoundedGap)
                recoveryRecord.missingIntervalStart = eventCheckpoint?.eventTimestamp
                recoveryRecord.missingIntervalEnd = recoveryDependencies.now()
                recoveryRecord.evidenceCompleteness = .partial
                coverage = "\(recoveryRecord.outcome.rawValue); explicit missing interval recorded"
            } else {
                coverage = recoveryRecord.outcome.rawValue
            }
            attachRecoveryToIncident()
            recordRecoveryActivity(state: recoveryRecord.evidenceCompleteness == .complete ? .complete : .partial, summary: coverage)
        } catch {
            status = .partialCoverage
            recoveryRecord.evidenceCompleteness = .failed
            recoveryRecord.recoveryEndedAt = recoveryDependencies.now()
            recoveryRecord.detail = "Recovery commit failed before in-memory advancement: \(error.localizedDescription). Replay may recur; silent evidence loss is not claimed."
            coverage = "FSEvents recovery commit failed; recorder remains operational"
            attachRecoveryToIncident()
            recordRecoveryActivity(state: .failed, summary: recoveryRecord.detail)
        }
    }

    private func attachRecoveryToIncident() {
        guard var incident = activeIncident else { return }
        recoveryDependencies.updateIncidentRecovery(&incident, recoveryRecord)
        if recoveryRecord.evidenceCompleteness != .complete {
            incident.completeness = .partial
            let gap = "Filesystem event recovery: \(recoveryRecord.outcome.rawValue)"
            if !incident.coverageGaps.contains(gap) { incident.coverageGaps.append(gap) }
        }
        activeIncident = incident
    }

    private func recordRecoveryActivity(state: DiagnosticOperationState, summary: String) {
        let entry = recoveryDependencies.makeActivity("FSEvents recovery", "Persisting recovery evidence", state, recoveryDependencies.now(), summary)
        operations.insert(entry, at: 0)
        operations = Array(operations.prefix(100))
        try? store.save(operations, named: "activity-v1.json")
    }
}

public enum ProcessAttribution { public static func snapshot() -> [ProcessEvidence] { ProcessInfo.processInfo.arguments.prefix(1).map { ProcessEvidence(name: ProcessInfo.processInfo.processName, executable: $0, bundleID: Bundle.main.bundleIdentifier, path: nil, confidence: .merelyActive, detail: "Running process snapshot; no path-level causation inferred.") } } }
public enum ScheduledTaskInspector { public static func inspect(home: String = NSHomeDirectory()) -> [ScheduledTaskEvidence] { let root = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents"); let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []; return files.filter { $0.pathExtension == "plist" }.prefix(100).map { url in let values = (try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)) as? [String: Any]; let schedule: String? = values?["StartCalendarInterval"] == nil ? nil : "Scheduled"; return ScheduledTaskEvidence(label: values?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent, program: (values?["ProgramArguments"] as? [String])?.first ?? values?["Program"] as? String, schedule: schedule, path: url.path, confidence: .possibleContributor, detail: "Scheduled-item overlap is not writer proof.") } } }
public enum EmergencyReserveController { public static let relativePath = "Library/Application Support/DexCleaner/EmergencyReserve/reserve.bin"; public static func eligibility(status: RecorderCapacitySample, incidentActive: Bool, stableSince: Date?) -> String { guard !incidentActive, let free = status.immediatelyFreeBytes, free >= 15_000_000_000 else { return "Pending Safe Conditions" }; guard stableSince.map({ Date().timeIntervalSince($0) >= 1_800 }) ?? false else { return "Pending 30-minute stability" }; return "Ready to create" }; public static func isOnlyAllowedPath(_ url: URL, home: String = NSHomeDirectory()) -> Bool { url.standardizedFileURL.path == URL(fileURLWithPath: home).appendingPathComponent(relativePath).standardizedFileURL.path } }
public enum StorageIncidentReportWriter { public static func write(_ incident: StorageIncident, store: IncidentStore) throws -> [URL] { let dir = store.directory.appendingPathComponent("Reports", isDirectory: true); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); let stamp = ISO8601DateFormatter().string(from: incident.startedAt).replacingOccurrences(of: ":", with: "-"); let base = dir.appendingPathComponent("DexCleaner-Storage-Incident-\(stamp)-\(incident.id.uuidString.prefix(8))"); let markdown = markdown(incident) + recoveryMarkdown(incident.filesystemEventRecovery) + completionMarkdown(incident); try markdown.write(to: base.appendingPathExtension("md"), atomically: true, encoding: .utf8); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(incident).write(to: base.appendingPathExtension("json"), options: .atomic); let csv = "incident_id,started_at,loss_bytes,explained_bytes,unexplained_bytes,completeness\n\(incident.id.uuidString),\(incident.startedAt.timeIntervalSince1970),\(incident.lossBytes),\(incident.system.explainedBytes),\(incident.system.unexplainedBytes),\(incident.completeness.rawValue)\n"; try csv.write(to: base.appendingPathExtension("csv"), atomically: true, encoding: .utf8); return [base.appendingPathExtension("md"), base.appendingPathExtension("json"), base.appendingPathExtension("csv")] }
    private static func recoveryMarkdown(_ r: FilesystemEventRecovery?) -> String { guard let r else { return "\n## Filesystem event recovery\n\nNo filesystem-event recovery evidence was associated with this incident.\n" }; func id(_ value: UInt64?) -> String { guard let value, value > 0 else { return "None" }; return String(value) }; let none = "None", unavailable = "Unavailable"; let interval = "\(r.recoveryStartedAt?.description ?? none) to \(r.recoveryEndedAt?.description ?? none)"; let missing = "\(r.missingIntervalStart?.description ?? none) to \(r.missingIntervalEnd?.description ?? none)"; let volume = r.watchedVolumeIdentity ?? unavailable, baseline = r.fallbackBaselineResult ?? none; return "\n## Filesystem event recovery\n\n- Recovery result: \(r.outcome.rawValue)\n- Stored checkpoint event ID: \(id(r.storedCheckpointEventID))\n- Requested resume event ID: \(id(r.requestedResumeEventID))\n- Recovered event range: \(id(r.firstReplayedEventID))–\(id(r.newestRecoveredEventID))\n- Watched volume: \(volume)\n- Recovery interval: \(interval)\n- Events replayed: \(r.eventsReplayed)\n- Duplicates suppressed: \(r.duplicatesSuppressed)\n- Dropped-event state: user \(r.userEventsDropped), kernel \(r.kernelEventsDropped)\n- Root-changed state: \(r.rootChanged)\n- Volume-changed state: \(r.volumeChanged)\n- Missing interval: \(missing)\n- Fallback baseline: \(baseline)\n- Evidence completeness: \(r.evidenceCompleteness.rawValue)\n- Explanation: \(r.detail)\n- FSEvents identifies changed locations; it does not measure byte growth. Allocated-byte measurement is required to establish physical growth.\n" }
    private static func markdown(_ i: StorageIncident) -> String { var text = "# DexCleaner Storage Incident Report\n\n## Incident summary\n\n- Incident ID: \(i.id.uuidString)\n- Start: \(i.startedAt)\n- End: \(i.endedAt?.description ?? "Active")\n- Trigger: \(i.trigger.rawValue)\n- Net loss: \(i.lossBytes) bytes\n- Evidence completeness: \(i.completeness.rawValue)\n- Explained amount: \(i.system.explainedBytes) bytes\n- Explained percentage: \(i.explainedPercentage)%\n- Unexplained allocation change: \(i.system.unexplainedBytes) bytes\n- Cleanup occurred: No. Diagnostic findings do not create cleanup authority.\n\n## Top measured growth\n\n"; let measurements = i.measurements.map { "- `\($0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))`: allocated \($0.allocatedBytes), logical \($0.logicalBytes), placeholders \($0.placeholderBytes), \($0.complete.rawValue)" }.joined(separator: "\n"); let processes = i.processes.map { "- \($0.name): \($0.confidence.rawValue) — \($0.detail)" }.joined(separator: "\n"); let tasks = i.tasks.map { "- \($0.label): \($0.confidence.rawValue)" }.joined(separator: "\n"); let cloud = i.cloud.map { "- \($0.provider): local allocation \($0.allocatedUserBytes), logical \($0.logicalBytes), placeholders \($0.placeholderBytes); \($0.safeAction)" }.joined(separator: "\n"); text += measurements; text += "\n\n## Process evidence\n\n\(processes)\n\n## Scheduled-task evidence\n\n\(tasks)\n\n## Cloud storage analysis\n\n\(cloud)\n\n## APFS and system changes\n\n- Swap: \(i.system.swapBytes) bytes\n- Trash: \(i.system.trashBytes) bytes\n- DexCleaner self-storage: \(i.system.dexCleanerBytes.map(String.init) ?? "Unavailable") bytes\n- \(i.system.detail)\n\n## Measurement limitations\n\n\(i.coverageGaps.joined(separator: "\n"))\n\n## Safety statement\n\nNo diagnostic result is a cleanup candidate. No cloud or user file was changed.\n"; return text }
    private static func completionMarkdown(_ incident: StorageIncident) -> String {
        let newFiles = incident.newFiles.isEmpty ? "None measured." : incident.newFiles.map { "- `\($0.path)`: \($0.currentAllocatedBytes) allocated bytes" }.joined(separator: "\n")
        let expanded = incident.expandedFiles.isEmpty ? "None measured." : incident.expandedFiles.map { "- `\($0.path)`: +\($0.deltaBytes) allocated bytes" }.joined(separator: "\n")
        let patterns = incident.repeatedPatterns?.map {
            "- \($0.kind.rawValue) · \($0.confidence) · \($0.occurrences) occurrences · cumulative \($0.cumulativeBytes) bytes · trend \($0.trend) · \($0.evidenceCompleteness.rawValue)\n  Supporting: \($0.supporting.joined(separator: "; "))\n  Contradictory: \($0.contradictory.joined(separator: "; "))\n  Explanation: \($0.explanation)"
        }.joined(separator: "\n") ?? "Not analyzed or absent in this incident."
        let comparisons = incident.localCloudComparisons?.map {
            "- \($0.classification.rawValue) · \($0.confidence)\n  Local: `\($0.localRoot)`\n  Cloud: `\($0.cloudRoot)`\n  Provider/mode: \($0.provider) / \($0.providerMode.rawValue)\n  Coverage: \($0.coverage.rawValue); files \($0.filesSampled); placeholders skipped \($0.placeholdersSkipped); bytes read \($0.bytesRead); limits \($0.limitsReached.joined(separator: ", ")); disposition \($0.disposition.rawValue)\n  \($0.reason)"
        }.joined(separator: "\n") ?? "No comparison was run."
        let reserve: String
        if let value = incident.emergencyReserveActivity {
            reserve = "- State: \(value.state.rawValue)\n- Target: \(value.targetBytes) bytes\n- Physical allocation: \(value.allocatedBytes) bytes\n- Last creation: \(value.lastCreation?.description ?? "Never")\n- Last release: \(value.lastRelease?.description ?? "Never")\n- Bytes restored: \(value.releasedBytes)\n- Eligibility: \(value.eligibilityReason)\n- Failure: \(value.failureReason ?? "None")\n- Rebuild eligible: \(value.rebuildEligible)"
        } else {
            reserve = "No reserve activity was associated with this incident."
        }
        let trace: String
        if let value = incident.deepTraceEvidence {
            trace = "- State: \(value.state.rawValue)\n- Authorization: \(value.authorizationState)\n- Duration: \(value.duration) seconds\n- Relevant operations: \(value.relevantOperations)\n- Processes: \(value.processAssociations.joined(separator: ", "))\n- Paths: \(value.paths.joined(separator: ", "))\n- Redacted: \(value.redacted)\n- Coverage: \(value.coverage.rawValue)\n- Partial reason: \(value.partialReason ?? "None")\n- \(value.summary)"
        } else {
            trace = "Deep trace was not requested."
        }
        return """

        ## Largest new files

        \(newFiles)

        ## Largest expanded files

        \(expanded)

        ## Repeated patterns

        \(patterns)

        Diagnostic only — not authorized for cleanup.

        ## Local and cloud comparison

        \(comparisons)

        No cloud-provider state was modified. Diagnostic only — not authorized for cleanup.

        ## Emergency reserve

        \(reserve)

        The reserve contains no user data and visibly consumes storage.

        ## Deep incident trace

        \(trace)

        Deep trace is optional, bounded to 60 seconds, metadata-only, and diagnostic only.

        ## Recommended next action

        Review the evidence and reveal relevant locations. Cleanup still requires a sealed-manifest candidate, explicit selection, immutable Preview, and filesystem revalidation.

        """
    }
}
