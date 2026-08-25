import Foundation

public enum CleanupReceiptSchema {
    public static let currentVersion = "1.0.0"
}

public enum CleanupReceiptTerminalState: String, Codable, Hashable, Sendable {
    case completed = "Completed"
    case partial = "Partial"
    case cancelled = "Cancelled"
    case blocked = "Blocked"
    case failed = "Failed"
}

public enum CandidateAttemptState: String, Codable, Hashable, Sendable {
    case movedToTrash = "Moved to Trash"
    case blocked = "Blocked"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case skippedAlreadyAbsent = "Skipped: already absent"
    case notAttempted = "Not attempted"
}

public struct ReclaimAccounting: Codable, Hashable, Sendable {
    public var logicalCandidateBytes: Int64
    public var allocatedCandidateBytes: Int64?
    public var estimatedPhysicalReclaimBytes: Int64?
    public var movedToTrashBytes: Int64
    public var freeBytesBefore: Int64?
    public var freeBytesAfter: Int64?

    public init(logicalCandidateBytes: Int64, allocatedCandidateBytes: Int64? = nil, estimatedPhysicalReclaimBytes: Int64? = nil, movedToTrashBytes: Int64, freeBytesBefore: Int64? = nil, freeBytesAfter: Int64? = nil) {
        self.logicalCandidateBytes = logicalCandidateBytes
        self.allocatedCandidateBytes = allocatedCandidateBytes
        self.estimatedPhysicalReclaimBytes = estimatedPhysicalReclaimBytes
        self.movedToTrashBytes = movedToTrashBytes
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
    }

    public var observedFreeSpaceDelta: Int64? {
        guard let before = freeBytesBefore, let after = freeBytesAfter else { return nil }
        return after - before
    }

    public var physicalReclaimStatement: String {
        estimatedPhysicalReclaimBytes == nil ? "Unknown. Finder Trash movement does not prove physical space was reclaimed." : "Estimated from dedicated physical-allocation evidence."
    }
}

public struct CandidateActionReceipt: Codable, Hashable, Sendable {
    public var candidateID: String
    public var ruleID: String
    public var approvedAction: CleanupAction
    public var preflightReason: String
    public var evidenceFingerprint: String?
    public var beforeIdentity: FileIdentity
    public var attemptState: CandidateAttemptState
    public var resultDetail: String
    public var resultingTrashPath: String?
    public var afterIdentity: FileIdentity?

    public init(candidateID: String, ruleID: String, approvedAction: CleanupAction, preflightReason: String, evidenceFingerprint: String?, beforeIdentity: FileIdentity, attemptState: CandidateAttemptState, resultDetail: String, resultingTrashPath: String?, afterIdentity: FileIdentity?) {
        self.candidateID = candidateID
        self.ruleID = ruleID
        self.approvedAction = approvedAction
        self.preflightReason = preflightReason
        self.evidenceFingerprint = evidenceFingerprint
        self.beforeIdentity = beforeIdentity
        self.attemptState = attemptState
        self.resultDetail = resultDetail
        self.resultingTrashPath = resultingTrashPath
        self.afterIdentity = afterIdentity
    }
}

public struct CleanupActionReceipt: Codable, Hashable, Sendable {
    public var schemaVersion: String
    public var operationID: UUID
    public var planID: UUID
    public var sourceScanID: UUID?
    public var campaignID: UUID?
    public var startedAt: Date
    public var endedAt: Date
    public var terminalState: CleanupReceiptTerminalState
    public var planPreflight: PlanPreflightResult
    public var candidates: [CandidateActionReceipt]
    public var accounting: ReclaimAccounting

    public init(schemaVersion: String = CleanupReceiptSchema.currentVersion, operationID: UUID = UUID(), planID: UUID, sourceScanID: UUID? = nil, campaignID: UUID? = nil, startedAt: Date, endedAt: Date, terminalState: CleanupReceiptTerminalState, planPreflight: PlanPreflightResult, candidates: [CandidateActionReceipt], accounting: ReclaimAccounting) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.planID = planID
        self.sourceScanID = sourceScanID
        self.campaignID = campaignID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.terminalState = terminalState
        self.planPreflight = planPreflight
        self.candidates = candidates
        self.accounting = accounting
    }
}

public struct CleanupExecutionResult: Sendable {
    public var results: [CleanupResult]
    public var receipt: CleanupActionReceipt
}

public enum CleanupReceiptFactory {
    public static func make(plan: CleanupPlan, preflight: PlanPreflightResult, results: [CleanupResult], startedAt: Date, endedAt: Date = Date(), freeBytesBefore: Int64? = nil, freeBytesAfter: Int64? = nil) -> CleanupActionReceipt {
        let byPath = Dictionary(uniqueKeysWithValues: results.map { (SafetyEngine.lexicalNormalize($0.path), $0) })
        let candidates = plan.items.map { item -> CandidateActionReceipt in
            let result = byPath[SafetyEngine.lexicalNormalize(item.path)]
            let state: CandidateAttemptState
            switch result?.status {
            case "Moved to Trash": state = .movedToTrash
            case "Failed": state = .failed
            case "Cancelled": state = .cancelled
            case "Blocked": state = result?.detail.localizedCaseInsensitiveContains("no longer exists") == true ? .skippedAlreadyAbsent : .blocked
            default: state = .notAttempted
            }
            return CandidateActionReceipt(
                candidateID: item.manifestID,
                ruleID: item.evidence?.provenance.ruleID ?? item.manifestID,
                approvedAction: item.action,
                preflightReason: preflight.failure?.path == item.path ? preflight.failure?.detail ?? "Blocked" : "Plan-wide preflight passed for this candidate.",
                evidenceFingerprint: item.evidence?.fingerprint,
                beforeIdentity: item.identity,
                attemptState: state,
                resultDetail: result?.detail ?? "No attempt was made.",
                resultingTrashPath: result?.resultingPath,
                afterIdentity: FileIdentity.capture(path: item.path)
            )
        }
        let states = Set(candidates.map(\.attemptState))
        let terminal: CleanupReceiptTerminalState
        if states == [.movedToTrash] { terminal = .completed }
        else if states.contains(.cancelled) { terminal = states.count == 1 ? .cancelled : .partial }
        else if states.contains(.failed) { terminal = states.count == 1 ? .failed : .partial }
        else if states.contains(.movedToTrash) { terminal = .partial }
        else { terminal = .blocked }
        let movedBytes = zip(plan.items, candidates).reduce(Int64(0)) { partial, pair in partial + (pair.1.attemptState == .movedToTrash ? pair.0.sizeBytes : 0) }
        return CleanupActionReceipt(
            planID: plan.id,
            sourceScanID: plan.sourceScanID,
            campaignID: plan.campaignID,
            startedAt: startedAt,
            endedAt: endedAt,
            terminalState: terminal,
            planPreflight: preflight,
            candidates: candidates,
            accounting: ReclaimAccounting(logicalCandidateBytes: plan.totalBytes, allocatedCandidateBytes: nil, estimatedPhysicalReclaimBytes: nil, movedToTrashBytes: movedBytes, freeBytesBefore: freeBytesBefore, freeBytesAfter: freeBytesAfter)
        )
    }
}

public enum ActionReceiptWriter {
    public static func write(_ receipt: CleanupActionReceipt, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("DexCleaner-Action-Receipt-\(receipt.operationID.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: url, options: .atomic)
        return url
    }
}

public enum CampaignProgressState: String, Codable, Hashable, Sendable {
    case running = "Running"
    case completed = "Completed"
    case partial = "Partial"
    case cancelled = "Cancelled"
    case failed = "Failed"
}

public enum CampaignFreshness {
    public static let maximumScanAge: TimeInterval = 15 * 60

    public static func isCurrent(plan: CleanupPlan, now: Date = Date()) -> Bool {
        guard let sourceScanAt = plan.sourceScanAt else { return true }
        let age = now.timeIntervalSince(sourceScanAt)
        return age >= 0 && age <= maximumScanAge
    }
}

public struct CampaignProgressSnapshot: Codable, Hashable, Sendable {
    public var phase: String
    public var state: CampaignProgressState
    public var candidatesConsidered: Int
    public var filesExamined: Int
    public var bytesExamined: Int64
    public var filesHashed: Int
    public var bytesHashed: Int64
    public var partialResultCount: Int
    public var startedAt: Date
    public var heartbeatAt: Date
}

public struct StopRecommendation: Codable, Hashable, Sendable {
    public var shouldStop: Bool
    public var reasons: [String]
    public var actionableCount: Int
    public var reviewCount: Int
    public var protectedCount: Int
    public var unknownCount: Int
}

public enum CleanupCampaignEvaluator {
    public static func reranked(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted {
            if $0.isCleanable != $1.isCleanable { return $0.isCleanable && !$1.isCleanable }
            if $0.sizeBytes != $1.sizeBytes { return $0.sizeBytes > $1.sizeBytes }
            return SafetyEngine.lexicalNormalize($0.path) < SafetyEngine.lexicalNormalize($1.path)
        }
    }

    public static func retryCandidateIDs(from receipt: CleanupActionReceipt) -> [String] {
        receipt.candidates.compactMap { candidate in
            switch candidate.attemptState {
            case .movedToTrash, .skippedAlreadyAbsent: return nil
            case .blocked, .failed, .cancelled, .notAttempted: return candidate.candidateID
            }
        }
    }

    public static func recommendation(items: [ScanItem], evidenceStale: Bool = false, objectiveSatisfied: Bool = false) -> StopRecommendation {
        let actionable = items.filter(\.isCleanable).count
        let review = items.filter { $0.risk == .caution || $0.risk == .auditOnly }.count
        let protected = items.filter { $0.risk == .protected || $0.risk == .forbidden }.count
        let unknown = items.filter { $0.measurementSource == .notMeasured || $0.evidence?.protection == .unknown }.count
        var reasons: [String] = []
        if evidenceStale { reasons.append("Evidence is stale; run a new scan before considering action.") }
        if objectiveSatisfied { reasons.append("The configured free-space objective is satisfied.") }
        if actionable == 0 { reasons.append("No evidence-proven actionable candidates remain.") }
        if actionable == 0 && review + protected + unknown > 0 { reasons.append("Remaining findings require review, are protected, or are unknown.") }
        return StopRecommendation(shouldStop: evidenceStale || objectiveSatisfied || actionable == 0, reasons: reasons, actionableCount: actionable, reviewCount: review, protectedCount: protected, unknownCount: unknown)
    }
}
