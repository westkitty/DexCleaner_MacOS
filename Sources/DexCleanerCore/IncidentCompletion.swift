import Foundation

// These completion components produce diagnostic evidence only. None imports or
// calls cleanup selection, Preview authorization, CleanupRunner, or Finder Trash.

public final class DiagnosticCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

public enum FSEventsRecoveryOutcome: String, Codable, Sendable {
    case resumedCompletely = "Resumed completely"
    case resumedWithDuplicatesSuppressed = "Resumed with duplicate events suppressed"
    case resumedWithBoundedGap = "Resumed with bounded coverage gap"
    case historyUnavailable = "History unavailable"
    case eventsDropped = "Events dropped"
    case rootChanged = "Root changed"
    case volumeChanged = "Volume changed"
    case storedCheckpointInvalid = "Invalid checkpoint"
    case storeRecoveredAfterCorruption = "Corrupt checkpoint preserved"
    case freshBaselineRequired = "Fresh baseline required"
}

public struct FSEventsCheckpoint: Codable, Equatable, Sendable {
    public var volumeID: String
    public var deviceID: String
    public var eventID: UInt64
    public var eventTimestamp: Date
    public var roots: [String]
    public var mode: String
    public var checkpointedAt: Date
    public var sessionID: String
    public var cleanShutdown: Bool
    public var schemaVersion: Int
    public var lastRecovery: FSEventsRecoveryOutcome?

    public init(
        volumeID: String,
        deviceID: String,
        eventID: UInt64 = 0,
        eventTimestamp: Date = Date(),
        roots: [String],
        mode: String = "file-events",
        checkpointedAt: Date = Date(),
        sessionID: String = UUID().uuidString,
        cleanShutdown: Bool = false,
        schemaVersion: Int = 1,
        lastRecovery: FSEventsRecoveryOutcome? = nil
    ) {
        self.volumeID = volumeID
        self.deviceID = deviceID
        self.eventID = eventID
        self.eventTimestamp = eventTimestamp
        self.roots = roots
        self.mode = mode
        self.checkpointedAt = checkpointedAt
        self.sessionID = sessionID
        self.cleanShutdown = cleanShutdown
        self.schemaVersion = schemaVersion
        self.lastRecovery = lastRecovery
    }
}

public struct FSEventsRecoveryResult: Codable, Sendable {
    public var outcome: FSEventsRecoveryOutcome
    public var resumedFrom: UInt64?
    public var resumedTo: UInt64?
    public var missingInterval: String?
    public var coverage: EvidenceCompleteness
    public var requiresBaseline: Bool
}

public enum FSEventsRecoveryEngine {
    public static func recover(
        checkpoint: FSEventsCheckpoint?,
        mountedVolumeID: String?,
        eventIDs: [UInt64],
        dropped: Bool = false,
        rootsMatch: Bool = true,
        storeRecovered: Bool = false
    ) -> FSEventsRecoveryResult {
        guard let checkpoint else {
            return .init(
                outcome: storeRecovered ? .storeRecoveredAfterCorruption : .freshBaselineRequired,
                resumedFrom: nil,
                resumedTo: nil,
                missingInterval: "No durable checkpoint",
                coverage: .partial,
                requiresBaseline: true
            )
        }
        guard checkpoint.schemaVersion == 1, checkpoint.eventID > 0 else {
            return .init(outcome: .storedCheckpointInvalid, resumedFrom: checkpoint.eventID, resumedTo: nil, missingInterval: "Checkpoint schema or event ID is invalid", coverage: .partial, requiresBaseline: true)
        }
        guard mountedVolumeID == checkpoint.volumeID else {
            return .init(outcome: .volumeChanged, resumedFrom: checkpoint.eventID, resumedTo: nil, missingInterval: "Saved volume identity does not match", coverage: .partial, requiresBaseline: true)
        }
        guard rootsMatch else {
            return .init(outcome: .rootChanged, resumedFrom: checkpoint.eventID, resumedTo: eventIDs.max(), missingInterval: "Watched roots changed", coverage: .partial, requiresBaseline: true)
        }
        guard !eventIDs.isEmpty else {
            return .init(outcome: .historyUnavailable, resumedFrom: checkpoint.eventID, resumedTo: nil, missingInterval: "No replay history was available", coverage: .partial, requiresBaseline: true)
        }
        if dropped {
            return .init(outcome: .eventsDropped, resumedFrom: checkpoint.eventID, resumedTo: eventIDs.max(), missingInterval: "FSEvents reported dropped events", coverage: .partial, requiresBaseline: true)
        }
        let unique = Set(eventIDs.filter { $0 > checkpoint.eventID })
        let duplicates = eventIDs.filter { $0 > checkpoint.eventID }.count - unique.count
        return .init(
            outcome: duplicates > 0 ? .resumedWithDuplicatesSuppressed : .resumedCompletely,
            resumedFrom: checkpoint.eventID,
            resumedTo: unique.max(),
            missingInterval: nil,
            coverage: .complete,
            requiresBaseline: false
        )
    }

    public static func deduplicate(_ events: [FSEventEvidence], after checkpoint: UInt64) -> [FSEventEvidence] {
        Array(
            Dictionary(grouping: events.filter { $0.eventID > checkpoint }, by: \.eventID)
                .values
                .compactMap(\.first)
                .sorted { $0.eventID < $1.eventID }
        )
    }
}

public enum RepeatedPatternKind: String, Codable, Sendable {
    case insufficientHistory = "Insufficient incident history"
    case none = "No repeated pattern detected"
    case repeatedPathGrowth = "Repeated path growth"
    case repeatedApplicationGrowth = "Repeated application-associated growth"
    case repeatedScheduledOverlap = "Repeated scheduled-task overlap"
    case repeatedAfterLaunch = "Repeated after-launch growth"
    case repeatedAfterWake = "Repeated after-wake growth"
    case repeatedTimeOfDay = "Repeated time-of-day growth"
    case repeatedProviderGrowth = "Repeated provider growth"
    case repeatedBuildOutput = "Repeated build-output recreation"
    case repeatedBackup = "Repeated backup creation"
    case repeatedVMOrDatabase = "Repeated VM or database expansion"
    case repeatedSwapOnly = "Repeated swap-only pressure"
    case recurrenceReduced = "Recurrence reduced"
    case recurrenceStopped = "Recurrence stopped"
    case conflicting = "Conflicting evidence"
}

public enum PatternConfidence: String, Codable, Sendable {
    case strong = "Strong repeated pattern"
    case probable = "Probable repeated pattern"
    case possible = "Possible repeated pattern"
    case insufficient = "Insufficient evidence"
    case conflicting = "Conflicting evidence"
}

public struct RepeatedPattern: Codable, Sendable {
    public var kind: RepeatedPatternKind
    public var confidence: String
    public var occurrences: Int
    public var incidentIDs: [UUID]
    public var first: Date?
    public var last: Date?
    public var averageBytes: Int64
    public var minimumBytes: Int64
    public var maximumBytes: Int64
    public var cumulativeBytes: Int64
    public var normalizedPath: String?
    public var owningApplication: String?
    public var executable: String?
    public var bundleIdentifier: String?
    public var scheduledTask: String?
    public var launchRelationship: String?
    public var timeOfDayBucket: String?
    public var sleepWakeRelationship: String?
    public var provider: String?
    public var storageCategory: DiagnosticClassification?
    public var swapRelationship: String?
    public var retentionControl: String
    public var trend: String
    public var supporting: [String]
    public var contradictory: [String]
    public var analyzedAt: Date
    public var sourceHistoryRevision: Int
    public var evidenceCompleteness: EvidenceCompleteness
    public var explanation: String

    public init(
        kind: RepeatedPatternKind,
        confidence: String,
        incidents: [StorageIncident],
        normalizedPath: String? = nil,
        supporting: [String] = [],
        contradictory: [String] = [],
        retentionControl: String = "Unknown",
        analyzedAt: Date = Date()
    ) {
        let deltas = incidents.map(\.lossBytes)
        self.kind = kind
        self.confidence = confidence
        occurrences = incidents.count
        incidentIDs = incidents.map(\.id)
        first = incidents.map(\.startedAt).min()
        last = incidents.map(\.startedAt).max()
        averageBytes = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Int64(deltas.count)
        minimumBytes = deltas.min() ?? 0
        maximumBytes = deltas.max() ?? 0
        cumulativeBytes = deltas.reduce(0, +)
        self.normalizedPath = normalizedPath
        let process = incidents.flatMap(\.processes).first
        owningApplication = process?.name
        executable = process?.executable
        bundleIdentifier = process?.bundleID
        scheduledTask = incidents.flatMap(\.tasks).first?.label
        launchRelationship = incidents.allSatisfy { $0.before.trigger.localizedCaseInsensitiveContains("launch") } ? "Repeated after launch" : nil
        timeOfDayBucket = Self.timeBucket(for: incidents)
        sleepWakeRelationship = incidents.allSatisfy { $0.before.wakeState == "Woke" } ? "Repeated after wake" : nil
        provider = incidents.flatMap(\.cloud).first?.provider
        storageCategory = incidents.flatMap(\.measurements).first?.classification
        swapRelationship = incidents.allSatisfy { $0.system.swapBytes > 0 && $0.measurements.isEmpty } ? "Swap-only evidence" : nil
        self.retentionControl = retentionControl
        trend = Self.trend(for: deltas)
        self.supporting = supporting
        self.contradictory = contradictory
        self.analyzedAt = analyzedAt
        sourceHistoryRevision = incidents.count
        evidenceCompleteness = contradictory.isEmpty && !incidents.contains(where: { $0.completeness != .complete }) ? .complete : .partial
        explanation = "This is recurrence evidence, not proof of causation and not cleanup authority."
    }

    private static func trend(for values: [Int64]) -> String {
        guard values.count >= 2, let first = values.first, let last = values.last else { return "Insufficient trend" }
        if last == 0 { return "Stopped" }
        if last < first { return "Decreasing" }
        if last > first { return "Increasing" }
        return "Stable"
    }

    private static func timeBucket(for incidents: [StorageIncident]) -> String? {
        guard !incidents.isEmpty else { return nil }
        let hours = incidents.map { Calendar(identifier: .gregorian).component(.hour, from: $0.startedAt) }
        guard let first = hours.first, hours.allSatisfy({ abs($0 - first) <= 1 }) else { return nil }
        return String(format: "%02d:00–%02d:59", first, min(23, first + 1))
    }
}

public enum RepeatedPatternClassifier {
    public static func classify(_ incidents: [StorageIncident], now: Date = Date()) -> RepeatedPattern {
        let history = incidents.sorted { $0.startedAt < $1.startedAt }
        guard history.count >= 3 else {
            return RepeatedPattern(kind: .insufficientHistory, confidence: PatternConfidence.insufficient.rawValue, incidents: history, analyzedAt: now)
        }

        let pathGroups = Dictionary(
            grouping: history.flatMap { incident in incident.measurements.map { (ChangedPathCoalescer.ancestor(for: $0.path), $0.classification, incident) } },
            by: { $0.0 }
        )
        let rankedPaths = pathGroups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
        if let winner = rankedPaths.first, winner.value.count >= 3 {
            let matches = uniqueIncidents(winner.value.map(\.2))
            let category = winner.value.first?.1
            let lower = winner.key.lowercased()
            let lastOccurrence = matches.map(\.startedAt).max()
            let sufficientQuietInterval = lastOccurrence.map { last in
                history.contains { $0.startedAt.timeIntervalSince(last) >= 7 * 86_400 && !$0.measurements.contains { ChangedPathCoalescer.ancestor(for: $0.path) == winner.key } }
            } ?? false
            let retention = history.last(where: { $0.retentionControlState != nil })?.retentionControlState ?? "Unknown"
            if sufficientQuietInterval {
                return RepeatedPattern(
                    kind: .recurrenceStopped,
                    confidence: PatternConfidence.probable.rawValue,
                    incidents: matches,
                    normalizedPath: winner.key,
                    supporting: ["No new occurrence was recorded during a sufficient seven-day observation interval."],
                    retentionControl: retention,
                    analyzedAt: now
                )
            }
            if let first = matches.first?.lossBytes, let last = matches.last?.lossBytes, first > 0, last * 2 <= first {
                return RepeatedPattern(
                    kind: .recurrenceReduced,
                    confidence: PatternConfidence.probable.rawValue,
                    incidents: matches,
                    normalizedPath: winner.key,
                    supporting: ["Later recurrence was materially smaller than the first recorded occurrence."],
                    retentionControl: retention,
                    analyzedAt: now
                )
            }
            let kind: RepeatedPatternKind
            if category == .buildOutput || lower.contains("/.build") || lower.contains("/deriveddata") {
                kind = .repeatedBuildOutput
            } else if lower.contains("backup") {
                kind = .repeatedBackup
            } else if category == .providerDatabase || lower.contains(".vm") || lower.contains("database") {
                kind = .repeatedVMOrDatabase
            } else {
                kind = .repeatedPathGrowth
            }
            return RepeatedPattern(
                kind: kind,
                confidence: matches.count >= 4 ? PatternConfidence.strong.rawValue : PatternConfidence.probable.rawValue,
                incidents: matches,
                normalizedPath: winner.key,
                supporting: ["The same meaningful root appeared in \(matches.count) incidents."],
                retentionControl: retention,
                analyzedAt: now
            )
        }

        let owners = Dictionary(grouping: history.flatMap { incident in incident.processes.map { ($0.bundleID ?? $0.executable, incident) } }, by: \.0)
        if let owner = owners.max(by: { $0.value.count < $1.value.count }), owner.value.count >= 3 {
            return RepeatedPattern(kind: .repeatedApplicationGrowth, confidence: PatternConfidence.probable.rawValue, incidents: uniqueIncidents(owner.value.map(\.1)), supporting: ["The same application association recurred; association is not writer proof."], analyzedAt: now)
        }

        let scheduled = history.filter { !$0.tasks.isEmpty }
        if scheduled.count >= 3 {
            return RepeatedPattern(kind: .repeatedScheduledOverlap, confidence: PatternConfidence.possible.rawValue, incidents: scheduled, supporting: ["Scheduled-task timing overlapped repeatedly."], analyzedAt: now)
        }
        let launched = history.filter { $0.before.trigger.localizedCaseInsensitiveContains("launch") }
        if launched.count >= 3 {
            return RepeatedPattern(kind: .repeatedAfterLaunch, confidence: PatternConfidence.probable.rawValue, incidents: launched, supporting: ["Capacity loss followed application launch repeatedly."], analyzedAt: now)
        }
        let wakes = history.filter { $0.before.wakeState == "Woke" }
        if wakes.count >= 3 {
            return RepeatedPattern(kind: .repeatedAfterWake, confidence: PatternConfidence.probable.rawValue, incidents: wakes, supporting: ["Capacity loss recurred after wake."], analyzedAt: now)
        }
        let providers = Dictionary(grouping: history.flatMap { incident in incident.cloud.map { ($0.provider, incident) } }, by: \.0)
        if let provider = providers.max(by: { $0.value.count < $1.value.count }), provider.value.count >= 3 {
            return RepeatedPattern(kind: .repeatedProviderGrowth, confidence: PatternConfidence.possible.rawValue, incidents: uniqueIncidents(provider.value.map(\.1)), supporting: ["The same provider association recurred; provider activity is not proof of writes."], analyzedAt: now)
        }
        if history.allSatisfy({ $0.system.swapBytes > 0 && $0.measurements.isEmpty }) {
            return RepeatedPattern(kind: .repeatedSwapOnly, confidence: PatternConfidence.possible.rawValue, incidents: history, supporting: ["Only swap-pressure evidence recurred."], analyzedAt: now)
        }

        let bucket = RepeatedPattern(kind: .repeatedTimeOfDay, confidence: PatternConfidence.possible.rawValue, incidents: history, analyzedAt: now)
        if history.count >= 4, bucket.timeOfDayBucket != nil {
            var result = bucket
            result.supporting = ["Incidents clustered in the same time-of-day bucket."]
            return result
        }
        if history.contains(where: { $0.completeness != .complete }) {
            return RepeatedPattern(kind: .conflicting, confidence: PatternConfidence.conflicting.rawValue, incidents: history, contradictory: ["Incomplete incidents prevent a stable recurrence conclusion."], analyzedAt: now)
        }
        return RepeatedPattern(kind: .none, confidence: PatternConfidence.insufficient.rawValue, incidents: history, analyzedAt: now)
    }

    private static func uniqueIncidents(_ incidents: [StorageIncident]) -> [StorageIncident] {
        var seen = Set<UUID>()
        return incidents.filter { seen.insert($0.id).inserted }
    }
}

public enum CopyClassification: String, Codable, Sendable {
    case nameOnly = "Similar name"
    case possible = "Possible duplicate candidate"
    case strong = "Strong duplicate candidate"
    case confirmed = "Confirmed separate local and cloud copies"
    case intentionallyMirrored = "Intentional mirrored provider content"
    case separateCheckout = "Separate local checkout"
    case diverged = "Diverged repositories"
    case incomplete = "Comparison incomplete"
    case unavailable = "Comparison unavailable"
    case refused = "Comparison refused"
}

public enum CopyDisposition: String, Codable, Sendable {
    case undecided = "Undecided"
    case intentionallySeparate = "Intentionally separate"
    case ignored = "Ignored"
}

public enum ProviderMode: String, Codable, Sendable {
    case ordinary = "Ordinary local content"
    case onlineOnly = "Online-only"
    case downloaded = "Downloaded"
    case mirrored = "Mirrored"
    case pinned = "Pinned"
    case placeholder = "Placeholder"
    case cache = "Provider cache"
    case database = "Provider database"
}

public struct LocalCloudComparisonLimits: Sendable {
    public var maximumFiles: Int
    public var maximumHashBytes: Int64
    public var maximumDuration: TimeInterval
    public var maximumDifferences: Int
    public var hashResidentFiles: Bool

    public init(maximumFiles: Int = 1_000, maximumHashBytes: Int64 = 1_073_741_824, maximumDuration: TimeInterval = 60, maximumDifferences: Int = 100, hashResidentFiles: Bool = true) {
        self.maximumFiles = maximumFiles
        self.maximumHashBytes = maximumHashBytes
        self.maximumDuration = maximumDuration
        self.maximumDifferences = maximumDifferences
        self.hashResidentFiles = hashResidentFiles
    }
}

public struct ComparisonFileMetadata: Sendable {
    public var isRegularFile: Bool
    public var isDirectory: Bool
    public var isSymbolicLink: Bool
    public var logicalBytes: Int64
    public var allocatedBytes: Int64
    public var modifiedAt: Date?
    public var placeholder: Bool
    public var dataless: Bool
    public var filesystemIdentity: String?
    public var stableIdentifier: String?

    public init(isRegularFile: Bool = false, isDirectory: Bool = false, isSymbolicLink: Bool = false, logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0, modifiedAt: Date? = nil, placeholder: Bool = false, dataless: Bool = false, filesystemIdentity: String? = nil, stableIdentifier: String? = nil) {
        self.isRegularFile = isRegularFile
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.modifiedAt = modifiedAt
        self.placeholder = placeholder
        self.dataless = dataless
        self.filesystemIdentity = filesystemIdentity
        self.stableIdentifier = stableIdentifier
    }
}

public struct LocalCloudComparisonDependencies: Sendable {
    public var metadata: @Sendable (URL) -> ComparisonFileMetadata?
    public var readResidentData: @Sendable (URL) -> Data?

    public init(metadata: @escaping @Sendable (URL) -> ComparisonFileMetadata?, readResidentData: @escaping @Sendable (URL) -> Data?) {
        self.metadata = metadata
        self.readResidentData = readResidentData
    }

    public static let live = LocalCloudComparisonDependencies(
        metadata: { LocalCloudComparator.liveMetadata(for: $0) },
        readResidentData: { try? Data(contentsOf: $0, options: .mappedIfSafe) }
    )
}

public struct CopyComparisonResult: Codable, Sendable {
    public var localRoot: String
    public var cloudRoot: String
    public var provider: String
    public var providerMode: ProviderMode
    public var classification: CopyClassification
    public var confidence: String
    public var comparisonStartedAt: Date
    public var comparisonEndedAt: Date
    public var filesSampled: Int
    public var directoriesExamined: Int
    public var placeholdersSkipped: Int
    public var datalessFilesSkipped: Int
    public var symlinksSkipped: Int
    public var filesystemBoundariesRefused: Int
    public var filesMatched: Int
    public var filesDiffering: Int
    public var bytesRead: Int64
    public var hashBytesRead: Int64
    public var localPhysicalAllocation: Int64
    public var cloudPhysicalAllocation: Int64
    public var localLogicalBytes: Int64
    public var cloudLogicalBytes: Int64
    public var matchingRelativePaths: [String]
    public var differingRelativePaths: [String]
    public var stableIdentifiersMatched: Int
    public var hashesMatched: Int
    public var coverage: EvidenceCompleteness
    public var limitsReached: [String]
    public var cancelled: Bool
    public var lowSpace: Bool
    public var reason: String
    public var safeActions: [String]
    public var disposition: CopyDisposition

    public init(
        localRoot: String,
        cloudRoot: String,
        provider: String,
        providerMode: ProviderMode,
        classification: CopyClassification,
        confidence: String,
        comparisonStartedAt: Date,
        comparisonEndedAt: Date,
        filesSampled: Int,
        directoriesExamined: Int,
        placeholdersSkipped: Int,
        datalessFilesSkipped: Int,
        symlinksSkipped: Int,
        filesystemBoundariesRefused: Int,
        filesMatched: Int,
        filesDiffering: Int,
        bytesRead: Int64,
        hashBytesRead: Int64,
        localPhysicalAllocation: Int64,
        cloudPhysicalAllocation: Int64,
        localLogicalBytes: Int64,
        cloudLogicalBytes: Int64,
        matchingRelativePaths: [String],
        differingRelativePaths: [String],
        stableIdentifiersMatched: Int,
        hashesMatched: Int,
        coverage: EvidenceCompleteness,
        limitsReached: [String],
        cancelled: Bool,
        lowSpace: Bool,
        reason: String,
        safeActions: [String],
        disposition: CopyDisposition
    ) {
        self.localRoot = localRoot
        self.cloudRoot = cloudRoot
        self.provider = provider
        self.providerMode = providerMode
        self.classification = classification
        self.confidence = confidence
        self.comparisonStartedAt = comparisonStartedAt
        self.comparisonEndedAt = comparisonEndedAt
        self.filesSampled = filesSampled
        self.directoriesExamined = directoriesExamined
        self.placeholdersSkipped = placeholdersSkipped
        self.datalessFilesSkipped = datalessFilesSkipped
        self.symlinksSkipped = symlinksSkipped
        self.filesystemBoundariesRefused = filesystemBoundariesRefused
        self.filesMatched = filesMatched
        self.filesDiffering = filesDiffering
        self.bytesRead = bytesRead
        self.hashBytesRead = hashBytesRead
        self.localPhysicalAllocation = localPhysicalAllocation
        self.cloudPhysicalAllocation = cloudPhysicalAllocation
        self.localLogicalBytes = localLogicalBytes
        self.cloudLogicalBytes = cloudLogicalBytes
        self.matchingRelativePaths = matchingRelativePaths
        self.differingRelativePaths = differingRelativePaths
        self.stableIdentifiersMatched = stableIdentifiersMatched
        self.hashesMatched = hashesMatched
        self.coverage = coverage
        self.limitsReached = limitsReached
        self.cancelled = cancelled
        self.lowSpace = lowSpace
        self.reason = reason
        self.safeActions = safeActions
        self.disposition = disposition
    }

    public var matchingPaths: Int { filesMatched }
    public var differingPaths: Int { filesDiffering }
}

public enum LocalCloudComparator {
    private struct Entry {
        var relativePath: String
        var size: Int64
        var modified: Date?
        var allocated: Int64
        var url: URL
        var stableIdentifier: String?
    }

    public static func compare(
        local: URL,
        cloud: URL,
        provider: String,
        providerMode: ProviderMode = .ordinary,
        lowSpace: Bool = false,
        limit: Int = 1_000,
        deadline: TimeInterval = 60,
        limits suppliedLimits: LocalCloudComparisonLimits? = nil,
        now: @Sendable () -> Date = { Date() },
        isCancelled: @Sendable () -> Bool = { false },
        dependencies: LocalCloudComparisonDependencies = .live
    ) -> CopyComparisonResult {
        let started = now()
        var limits = suppliedLimits ?? LocalCloudComparisonLimits(maximumFiles: limit, maximumDuration: deadline)
        limits.maximumFiles = min(limits.maximumFiles, 1_000)
        limits.maximumHashBytes = min(limits.maximumHashBytes, 1_073_741_824)
        limits.maximumDuration = min(limits.maximumDuration, 60)
        limits.maximumDifferences = min(limits.maximumDifferences, 100)

        func unavailable(_ reason: String) -> CopyComparisonResult {
            CopyComparisonResult(
                localRoot: local.path, cloudRoot: cloud.path, provider: provider, providerMode: providerMode,
                classification: .unavailable, confidence: "Unavailable", comparisonStartedAt: started, comparisonEndedAt: now(),
                filesSampled: 0, directoriesExamined: 0, placeholdersSkipped: 0, datalessFilesSkipped: 0,
                symlinksSkipped: 0, filesystemBoundariesRefused: 0, filesMatched: 0, filesDiffering: 0,
                bytesRead: 0, hashBytesRead: 0, localPhysicalAllocation: 0, cloudPhysicalAllocation: 0,
                localLogicalBytes: 0, cloudLogicalBytes: 0, matchingRelativePaths: [], differingRelativePaths: [],
                stableIdentifiersMatched: 0, hashesMatched: 0, coverage: .unavailable, limitsReached: [],
                cancelled: false, lowSpace: lowSpace, reason: reason,
                safeActions: ["Reveal both locations", "Mark intentionally separate", "Ignore comparison"],
                disposition: .undecided
            )
        }

        guard !lowSpace else { return unavailable("Critical low-space backoff disables optional hashing and comparison.") }
        guard FileManager.default.fileExists(atPath: local.path), FileManager.default.fileExists(atPath: cloud.path) else {
            return unavailable("One or both roots are unavailable.")
        }

        let fm = FileManager.default
        guard
            let localRootValues = dependencies.metadata(local),
            let cloudRootValues = dependencies.metadata(cloud),
            localRootValues.isDirectory,
            cloudRootValues.isDirectory,
            !localRootValues.isSymbolicLink,
            !cloudRootValues.isSymbolicLink
        else { return unavailable("Roots must be ordinary directories and cannot be symbolic links.") }

        var placeholders = 0, dataless = 0, symlinks = 0, boundaries = 0, directories = 0, totalFiles = 0
        var limitsReached: [String] = []
        var cancelled = false
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey, .isUbiquitousItemKey, .totalFileAllocatedSizeKey,
            .volumeIdentifierKey
        ]

        func list(_ root: URL, rootVolume: String?) -> [String: Entry] {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else { return [:] }
            var entries: [String: Entry] = [:]
            let normalizedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
            while let url = enumerator.nextObject() as? URL {
                if isCancelled() {
                    cancelled = true
                    break
                }
                if now().timeIntervalSince(started) >= limits.maximumDuration {
                    limitsReached.append("60-second time limit")
                    break
                }
                guard let values = dependencies.metadata(url) else { continue }
                if values.isSymbolicLink {
                    symlinks += 1
                    enumerator.skipDescendants()
                    continue
                }
                if let volume = values.filesystemIdentity, let rootVolume, volume != rootVolume {
                    boundaries += 1
                    enumerator.skipDescendants()
                    continue
                }
                if values.isDirectory {
                    directories += 1
                    continue
                }
                guard values.isRegularFile else { continue }
                if totalFiles >= limits.maximumFiles {
                    limitsReached.append("1,000-file limit")
                    break
                }
                let size = values.logicalBytes
                let allocated = values.allocatedBytes
                if values.placeholder {
                    placeholders += 1
                    continue
                }
                if values.dataless {
                    dataless += 1
                    continue
                }
                let normalizedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
                let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
                guard normalizedPath.hasPrefix(prefix) else {
                    boundaries += 1
                    continue
                }
                let relative = String(normalizedPath.dropFirst(prefix.count))
                entries[relative] = Entry(relativePath: relative, size: size, modified: values.modifiedAt, allocated: allocated, url: url, stableIdentifier: values.stableIdentifier)
                totalFiles += 1
            }
            return entries
        }

        let localEntries = list(local, rootVolume: localRootValues.filesystemIdentity)
        let cloudEntries = list(cloud, rootVolume: cloudRootValues.filesystemIdentity)
        let shared = Set(localEntries.keys).intersection(cloudEntries.keys).sorted()
        var metadataMatches: [String] = []
        var differences: [String] = []
        var hashMatches = 0
        var stableMatches = 0
        var hashBytes: Int64 = 0

        for relative in shared {
            guard let a = localEntries[relative], let b = cloudEntries[relative] else { continue }
            let stableIdentityMatches = a.stableIdentifier != nil && a.stableIdentifier == b.stableIdentifier
            if stableIdentityMatches {
                stableMatches += 1
                metadataMatches.append(relative)
            } else if a.size == b.size && a.modified == b.modified {
                metadataMatches.append(relative)
            } else if differences.count < limits.maximumDifferences {
                differences.append(relative)
            }
            guard limits.hashResidentFiles, a.size == b.size else { continue }
            let proposed = a.size + b.size
            guard hashBytes + proposed <= limits.maximumHashBytes else {
                if !limitsReached.contains("1 GiB hash-byte limit") { limitsReached.append("1 GiB hash-byte limit") }
                continue
            }
            guard let left = dependencies.readResidentData(a.url), let right = dependencies.readResidentData(b.url) else { continue }
            hashBytes += Int64(left.count + right.count)
            if left == right { hashMatches += 1 }
        }
        let onlyLocal = Set(localEntries.keys).subtracting(cloudEntries.keys)
        let onlyCloud = Set(cloudEntries.keys).subtracting(localEntries.keys)
        differences.append(contentsOf: (onlyLocal.union(onlyCloud)).sorted().prefix(max(0, limits.maximumDifferences - differences.count)))

        let bothGit = fm.fileExists(atPath: local.appendingPathComponent(".git").path) && fm.fileExists(atPath: cloud.appendingPathComponent(".git").path)
        let classification: CopyClassification
        let confidence: String
        if cancelled || !limitsReached.isEmpty {
            classification = .incomplete
            confidence = "Partial bounded comparison"
        } else if bothGit {
            classification = differences.isEmpty ? .separateCheckout : .diverged
            confidence = "Repository ancestry is not duplicate proof"
        } else if providerMode == .mirrored {
            classification = .intentionallyMirrored
            confidence = "Provider-declared mirror mode"
        } else if !shared.isEmpty && (hashMatches == shared.count || stableMatches == shared.count) && differences.isEmpty {
            classification = .strong
            confidence = "Bounded resident-file hashes agree"
        } else if metadataMatches.count >= 3 && differences.isEmpty {
            classification = .possible
            confidence = "Strong metadata agreement; contents not fully proven"
        } else {
            classification = .nameOnly
            confidence = "Names or partial structure only"
        }

        let filesMatched = hashMatches > 0 ? hashMatches : metadataMatches.count
        return CopyComparisonResult(
            localRoot: local.path, cloudRoot: cloud.path, provider: provider, providerMode: providerMode,
            classification: classification, confidence: confidence, comparisonStartedAt: started, comparisonEndedAt: now(),
            filesSampled: localEntries.count + cloudEntries.count, directoriesExamined: directories,
            placeholdersSkipped: placeholders, datalessFilesSkipped: dataless, symlinksSkipped: symlinks,
            filesystemBoundariesRefused: boundaries, filesMatched: filesMatched, filesDiffering: differences.count,
            bytesRead: hashBytes, hashBytesRead: hashBytes,
            localPhysicalAllocation: localEntries.values.reduce(0) { $0 + $1.allocated },
            cloudPhysicalAllocation: cloudEntries.values.reduce(0) { $0 + $1.allocated },
            localLogicalBytes: localEntries.values.reduce(0) { $0 + $1.size },
            cloudLogicalBytes: cloudEntries.values.reduce(0) { $0 + $1.size },
            matchingRelativePaths: Array((hashMatches > 0 ? shared : metadataMatches).prefix(100)),
            differingRelativePaths: differences, stableIdentifiersMatched: stableMatches,
            hashesMatched: hashMatches, coverage: cancelled ? .cancelled : (limitsReached.isEmpty ? .complete : .partial),
            limitsReached: Array(Set(limitsReached)).sorted(), cancelled: cancelled, lowSpace: lowSpace,
            reason: "Only already-resident files were eligible. Placeholders, dataless files, symlinks, and filesystem crossings were refused. No cloud-provider state was modified.",
            safeActions: ["Reveal both locations", "Add both roots to watchlist", "Mark intentionally separate", "Ignore comparison"],
            disposition: .undecided
        )
    }

    public static func liveMetadata(for url: URL) -> ComparisonFileMetadata? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey, .fileResourceIdentifierKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let allocated = Int64(values.totalFileAllocatedSize ?? 0)
        let ubiquitous = values.isUbiquitousItem == true
        return ComparisonFileMetadata(
            isRegularFile: values.isRegularFile == true,
            isDirectory: values.isDirectory == true,
            isSymbolicLink: values.isSymbolicLink == true,
            logicalBytes: Int64(values.fileSize ?? 0),
            allocatedBytes: allocated,
            modifiedAt: values.contentModificationDate,
            placeholder: ubiquitous && allocated == 0,
            dataless: ubiquitous && allocated == 0,
            filesystemIdentity: (values.volumeIdentifier as? AnyHashable).map { String(describing: $0) },
            stableIdentifier: (values.fileResourceIdentifier as? AnyHashable).map { String(describing: $0) }
        )
    }
}

public enum DeepTraceState: String, Codable, Sendable {
    case available = "Available"
    case requiresAuthorization = "Requires authorization"
    case authorizationDenied = "Authorization denied"
    case running = "Running"
    case stopping = "Stopping"
    case complete = "Complete"
    case partial = "Partial"
    case failed = "Failed"
    case unsupported = "Unsupported"
}

public struct DeepTraceEvidence: Codable, Sendable {
    public var state: DeepTraceState
    public var requestedAt: Date
    public var authorizationState: String
    public var startedAt: Date?
    public var endedAt: Date?
    public var duration: TimeInterval
    public var relevantOperations: Int
    public var processAssociations: [String]
    public var paths: [String]
    public var redacted: Bool
    public var coverage: EvidenceCompleteness
    public var partialReason: String?
    public var summary: String
    public var process: String? { processAssociations.first }
    public var path: String? { paths.first }
}

public enum DeepTraceController {
    public static let maximumDuration: TimeInterval = 60

    public static func runBounded(
        incidentPaths: [String],
        requestedDuration: TimeInterval = maximumDuration,
        executable: URL = URL(fileURLWithPath: "/usr/bin/fs_usage"),
        now: @Sendable () -> Date = { Date() },
        isCancelled: @Sendable () -> Bool = { false }
    ) -> DeepTraceEvidence {
        let requestedAt = now()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return DeepTraceEvidence(state: .unsupported, requestedAt: requestedAt, authorizationState: "Unavailable", startedAt: nil, endedAt: nil, duration: 0, relevantOperations: 0, processAssociations: [], paths: [], redacted: true, coverage: .unavailable, partialReason: "The bounded trace command is unavailable.", summary: "Normal incident recording remains operational.")
        }
        let duration = min(max(1, requestedDuration), maximumDuration)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["-w", "-f", "filesys"]
        process.standardOutput = pipe
        process.standardError = pipe
        let buffer = DeepTraceOutputBuffer(limit: 1_048_576)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return DeepTraceEvidence(state: .failed, requestedAt: requestedAt, authorizationState: "Launch failed", startedAt: nil, endedAt: now(), duration: 0, relevantOperations: 0, processAssociations: [], paths: [], redacted: true, coverage: .failed, partialReason: error.localizedDescription, summary: "Trace launch failed; normal incident recording remains operational.")
        }
        let deadline = Date().addingTimeInterval(duration)
        var cancelled = false
        while process.isRunning, Date() < deadline {
            if isCancelled() {
                cancelled = true
                break
            }
            _ = finished.wait(timeout: .now() + 0.1)
        }
        let timedOut = process.isRunning && !cancelled
        if process.isRunning {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let output = String(data: buffer.data, encoding: .utf8) ?? ""
        if output.localizedCaseInsensitiveContains("must be root") || output.localizedCaseInsensitiveContains("permission denied") {
            return DeepTraceEvidence(state: .requiresAuthorization, requestedAt: requestedAt, authorizationState: "Required", startedAt: requestedAt, endedAt: now(), duration: min(duration, now().timeIntervalSince(requestedAt)), relevantOperations: 0, processAssociations: [], paths: [], redacted: true, coverage: .unavailable, partialReason: "Supported macOS authorization is required; no credential was requested or stored.", summary: "Authorization is required. Normal incident recording remains armed.")
        }
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        return synthetic(lines: lines, authorized: true, cancelled: cancelled || timedOut, timeout: duration, incidentPaths: incidentPaths, now: requestedAt)
    }

    public static func synthetic(
        lines: [String],
        authorized: Bool,
        denied: Bool = false,
        cancelled: Bool = false,
        timeout: TimeInterval = 60,
        incidentPaths: [String] = [],
        now: Date = Date()
    ) -> DeepTraceEvidence {
        if denied {
            return evidence(state: .authorizationDenied, authorization: "Denied", now: now, coverage: .unavailable, reason: "Authorization was denied. Normal incident recording remains armed.")
        }
        guard authorized else {
            return evidence(state: .requiresAuthorization, authorization: "Required", now: now, coverage: .unavailable, reason: "Authorization is required for a bounded diagnostic trace; no credentials are retained.")
        }

        let duration = min(max(0, timeout), maximumDuration)
        let relevant = lines.filter { line in
            guard line.contains("WRITE") else { return false }
            return incidentPaths.isEmpty || incidentPaths.contains(where: line.contains)
        }.prefix(500)
        let sanitized = relevant.map(redact)
        let processes = Array(Set(sanitized.compactMap { $0.split(separator: " ").first.map(String.init) })).sorted()
        let paths = Array(Set(sanitized.compactMap { line -> String? in
            guard let range = line.range(of: " path=") else { return nil }
            return String(line[range.upperBound...].split(separator: " ").first ?? "")
        })).sorted()
        let timedOut = timeout > maximumDuration
        let state: DeepTraceState = cancelled || timedOut ? .partial : .complete
        let coverage: EvidenceCompleteness = cancelled ? .cancelled : (timedOut ? .partial : .complete)
        return DeepTraceEvidence(
            state: state, requestedAt: now, authorizationState: "Authorized for this run",
            startedAt: now, endedAt: now.addingTimeInterval(duration), duration: duration,
            relevantOperations: sanitized.count, processAssociations: processes, paths: paths,
            redacted: true, coverage: coverage,
            partialReason: cancelled ? "Cancelled safely" : (timedOut ? "Stopped at the 60-second bound" : nil),
            summary: "\(sanitized.count) relevant metadata operations retained; unrelated events and sensitive arguments were discarded."
        )
    }

    private static func evidence(state: DeepTraceState, authorization: String, now: Date, coverage: EvidenceCompleteness, reason: String) -> DeepTraceEvidence {
        DeepTraceEvidence(state: state, requestedAt: now, authorizationState: authorization, startedAt: nil, endedAt: nil, duration: 0, relevantOperations: 0, processAssociations: [], paths: [], redacted: true, coverage: coverage, partialReason: reason, summary: reason)
    }

    private static func redact(_ line: String) -> String {
        var value = line.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        for marker in ["--token", "--password", "--secret", "Authorization:"] {
            if let range = value.range(of: marker, options: .caseInsensitive) {
                value.replaceSubrange(range.lowerBound..<value.endIndex, with: "[redacted]")
            }
        }
        return value
    }
}

private final class DeepTraceOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard storage.count < limit else { return }
        storage.append(data.prefix(limit - storage.count))
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

public enum ReserveState: String, Codable, Sendable {
    case disabled = "Disabled"
    case pending = "Pending Safe Conditions"
    case creating = "Creating"
    case ready = "Ready"
    case releasing = "Releasing"
    case released = "Released"
    case waiting = "Waiting to Rebuild"
    case failed = "Failed"
}

public struct EmergencyReserveStatus: Codable, Sendable {
    public var state: ReserveState
    public var previousState: ReserveState?
    public var targetBytes: Int64
    public var allocatedBytes: Int64
    public var lastCreation: Date?
    public var lastRelease: Date?
    public var releasedBytes: Int64
    public var eligibilityReason: String
    public var failureReason: String?
    public var rebuildEligible: Bool
    public var owner: String
    public var measurementCompleteness: EvidenceCompleteness?

    public init(
        state: ReserveState = .pending,
        previousState: ReserveState? = nil,
        targetBytes: Int64 = 1_073_741_824,
        allocatedBytes: Int64 = 0,
        lastCreation: Date? = nil,
        lastRelease: Date? = nil,
        releasedBytes: Int64 = 0,
        eligibilityReason: String = "Pending safe conditions",
        failureReason: String? = nil,
        rebuildEligible: Bool = false,
        owner: String = "DexCleaner",
        measurementCompleteness: EvidenceCompleteness? = nil
    ) {
        self.state = state
        self.previousState = previousState
        self.targetBytes = targetBytes
        self.allocatedBytes = allocatedBytes
        self.lastCreation = lastCreation
        self.lastRelease = lastRelease
        self.releasedBytes = releasedBytes
        self.eligibilityReason = eligibilityReason
        self.failureReason = failureReason
        self.rebuildEligible = rebuildEligible
        self.owner = owner
        self.measurementCompleteness = measurementCompleteness
    }
}

public extension EmergencyReserveController {
    static let productionTargetBytes: Int64 = 1_073_741_824

    static func create(
        injectedHome: URL,
        freeBytes: Int64,
        stable: Bool,
        incidentActive: Bool,
        activeOperation: Bool = false,
        featureEnabled: Bool = true,
        warningBytes: Int64 = 10_000_000_000,
        target: Int64 = productionTargetBytes,
        chunkBytes: Int = 1_048_576,
        now: Date = Date(),
        freeCapacity: @Sendable () -> Int64? = { nil },
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> EmergencyReserveStatus {
        guard featureEnabled else { return .init(state: .disabled, targetBytes: target, eligibilityReason: "Feature disabled") }
        guard freeBytes >= 15_000_000_000 else { return .init(state: .pending, targetBytes: target, eligibilityReason: "Immediately free is below 15 GB") }
        guard stable else { return .init(state: .pending, targetBytes: target, eligibilityReason: "Storage has not been stable for 30 minutes") }
        guard !incidentActive else { return .init(state: .pending, targetBytes: target, eligibilityReason: "An incident is active") }
        guard !activeOperation else { return .init(state: .pending, targetBytes: target, eligibilityReason: "A major operation is active") }
        guard freeBytes - target > warningBytes else { return .init(state: .pending, targetBytes: target, eligibilityReason: "Projected remaining capacity is unsafe") }
        guard target > 0, target <= productionTargetBytes else { return .init(state: .failed, targetBytes: target, failureReason: "Invalid reserve target") }

        let fm = FileManager.default
        let final = injectedHome.appendingPathComponent(relativePath)
        let directory = final.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".reserve-\(UUID().uuidString).tmp")
        guard isOnlyAllowedPath(final, home: injectedHome.path) else {
            return .init(state: .failed, targetBytes: target, failureReason: "Exact reserve path validation failed")
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: final.path) else {
            return .init(state: .failed, targetBytes: target, failureReason: "Reserve already exists")
        }

        do {
            guard fm.createFile(atPath: temporary.path, contents: nil) else {
                return .init(state: .failed, targetBytes: target, failureReason: "Temporary reserve could not be created")
            }
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            let chunk = Data(repeating: 0xA5, count: max(4_096, min(chunkBytes, 4 * 1_048_576)))
            var written: Int64 = 0
            while written < target {
                if isCancelled() { throw CancellationError() }
                if let current = freeCapacity(), current - min(Int64(chunk.count), target - written) <= warningBytes {
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                let amount = Int(min(Int64(chunk.count), target - written))
                try handle.write(contentsOf: chunk.prefix(amount))
                written += Int64(amount)
            }
            try handle.synchronize()
            let values = try temporary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let allocated = Int64(values.totalFileAllocatedSize ?? 0)
            guard allocated >= target else { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.moveItem(at: temporary, to: final)
            let status = EmergencyReserveStatus(state: .ready, previousState: .creating, targetBytes: target, allocatedBytes: allocated, lastCreation: now, eligibilityReason: "Created under safe conditions")
            try persistReserveStatus(status, at: directory)
            return status
        } catch {
            if fm.fileExists(atPath: temporary.path) { try? fm.removeItem(at: temporary) }
            throw error
        }
    }

    static func release(
        injectedHome: URL,
        now: Date = Date(),
        measuredFreeBefore: Int64? = nil,
        measuredFreeAfter: @Sendable () -> Int64? = { nil }
    ) throws -> EmergencyReserveStatus {
        let fm = FileManager.default
        let url = injectedHome.appendingPathComponent(relativePath)
        let directory = url.deletingLastPathComponent()
        guard isOnlyAllowedPath(url, home: injectedHome.path), fm.fileExists(atPath: url.path) else {
            return .init(state: .failed, failureReason: "The exact DexCleaner reserve does not exist")
        }
        let stored = try loadReserveStatus(at: directory)
        guard stored.owner == "DexCleaner" else {
            return .init(state: .failed, failureReason: "Reserve ownership record is invalid")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            return .init(state: .failed, failureReason: "Reserve is not an ordinary regular file")
        }
        let allocation = Int64(values.totalFileAllocatedSize ?? 0)
        try fm.removeItem(at: url)
        let measuredAfter = measuredFreeBefore == nil ? nil : measuredFreeAfter()
        let restored = measuredFreeBefore.flatMap { before in measuredAfter.map { max(0, $0 - before) } } ?? allocation
        let remeasurementFailed = measuredFreeBefore != nil && measuredAfter == nil
        let status = EmergencyReserveStatus(
            state: .waiting, previousState: .releasing, targetBytes: stored.targetBytes,
            allocatedBytes: 0, lastCreation: stored.lastCreation, lastRelease: now,
            releasedBytes: restored,
            eligibilityReason: remeasurementFailed
                ? "Released; capacity remeasurement was unavailable, so restored bytes use physical allocation evidence"
                : "Released; rebuild waits for fresh safe conditions",
            failureReason: remeasurementFailed ? "Post-release capacity remeasurement was unavailable" : nil,
            rebuildEligible: false,
            measurementCompleteness: remeasurementFailed ? .partial : .complete
        )
        try persistReserveStatus(status, at: directory)
        return status
    }

    static func status(injectedHome: URL) -> EmergencyReserveStatus? {
        let directory = injectedHome.appendingPathComponent(relativePath).deletingLastPathComponent()
        return try? loadReserveStatus(at: directory)
    }

    private static func reserveStateURL(_ directory: URL) -> URL {
        directory.appendingPathComponent("reserve-state-v1.json")
    }

    private static func persistReserveStatus(_ status: EmergencyReserveStatus, at directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(status).write(to: reserveStateURL(directory), options: .atomic)
    }

    private static func loadReserveStatus(at directory: URL) throws -> EmergencyReserveStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EmergencyReserveStatus.self, from: Data(contentsOf: reserveStateURL(directory)))
    }
}

public enum UICertificationHarness {
    public static func snapshots() -> [String: String] {
        [
            "01-armed-recorder": "Recorder Armed | Launch at Login | Immediately free | Available for work | Quick Scan",
            "02-active-incident": "Investigating… | Active incident | indeterminate progress | Cancel | Diagnostic only",
            "03-recovery-pattern": "FSEvents Partial | missing interval | Strong repeated pattern | Conflicting evidence | Refresh Patterns",
            "04-comparison": "Comparing… | Complete | Partial | placeholders skipped | Compare Copies | Diagnostic only",
            "05-reserve": "Pending Safe Conditions | Creating… | Ready | Released | Rebuild Reserve | actual allocation disclosed",
            "06-deep-trace": "Requires authorization | Tracing… | Partial | Cancel | metadata only | 60-second maximum",
            "07-operation-states": "Complete | Partial | Cancelled | Failed | elapsed | item count | retained completion summary",
            "08-candidates-preview": "Not scanned | Scanning… | Candidates found | Preview ready | Close | Move to Trash disabled"
        ]
    }
}
