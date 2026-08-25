import Foundation

public enum PlanPreflightFailureReason: String, Codable, Hashable, Sendable {
    case emptyPlan = "Empty plan"
    case expired = "Expired plan"
    case duplicatePath = "Duplicate path"
    case invalidSelectionSignature = "Invalid selection signature"
    case invalidEvidenceSignature = "Invalid evidence signature"
    case manifestChanged = "Manifest changed"
    case candidateChanged = "Candidate changed"
    case candidateOpen = "Candidate open"
    case detectorUnavailable = "Open-file detector unavailable"
    case cancelled = "Cancelled"
}

public struct PlanPreflightFailure: Codable, Hashable, Sendable {
    public var reason: PlanPreflightFailureReason
    public var path: String?
    public var detail: String

    public init(reason: PlanPreflightFailureReason, path: String? = nil, detail: String) {
        self.reason = reason
        self.path = path
        self.detail = detail
    }
}

public struct PlanPreflightResult: Codable, Hashable, Sendable {
    public var checkedAt: Date
    public var checkedItemCount: Int
    public var failure: PlanPreflightFailure?

    public init(checkedAt: Date, checkedItemCount: Int, failure: PlanPreflightFailure? = nil) {
        self.checkedAt = checkedAt
        self.checkedItemCount = checkedItemCount
        self.failure = failure
    }

    public var allowed: Bool { failure == nil }
}

public struct CleanupRunner {
    public let home: String
    public let openFileChecker: ExactOpenFileChecker

    public init(home: String = NSHomeDirectory(), openFileChecker: ExactOpenFileChecker = .production) {
        self.home = home
        self.openFileChecker = openFileChecker
    }

    public func previewSelected(_ items: [ScanItem], sourceScanID: UUID? = nil, sourceScanAt: Date? = nil, campaignID: UUID? = nil) -> PreviewOutcome {
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else {
            return PreviewOutcome(results: [CleanupResult(path: "selection://empty", status: "Blocked", detail: "No selected cleanup candidates.")], plan: nil)
        }
        guard CleanupCatalog.isAvailable else {
            return PreviewOutcome(results: [CleanupResult(path: "manifest://unavailable", status: "Blocked", detail: CleanupCatalog.validationErrors.joined(separator: " "))], plan: nil)
        }

        var results: [CleanupResult] = []
        var planItems: [CleanupPlanItem] = []
        for item in selected {
            let decision = SafetyEngine.decision(for: item, home: home)
            guard decision.allowed else {
                results.append(CleanupResult(path: item.path, status: "Blocked", detail: decision.reason))
                continue
            }
            guard let manifestID = item.manifestID, let identity = FileIdentity.capture(path: item.path) else {
                results.append(CleanupResult(path: item.path, status: "Blocked", detail: "Manifest identity or filesystem identity is unavailable."))
                continue
            }
            guard let evidence = CandidateEvidenceFactory.forCandidate(item: item, identity: identity, home: home), evidence.isActionable else {
                results.append(CleanupResult(path: item.path, status: "Blocked", detail: "Complete cleanup evidence could not be established."))
                continue
            }
            planItems.append(CleanupPlanItem(
                scanItemID: item.id,
                manifestID: manifestID,
                path: item.path,
                displayName: item.displayName,
                sizeBytes: item.sizeBytes,
                identity: identity,
                safetyReason: decision.reason,
                risk: item.risk,
                action: item.action,
                evidence: evidence
            ))
            let processNote = item.owningProcessRunning ? " The owning application appears to be running; close it before cleanup when practical." : ""
            results.append(CleanupResult(path: item.path, status: "Authorized for confirmation", detail: decision.reason + processNote))
        }

        guard planItems.count == selected.count else { return PreviewOutcome(results: results, plan: nil) }
        let plan = CleanupPlan(
            manifestVersion: CleanupCatalog.policyVersion,
            manifestChecksum: CleanupCatalog.manifestChecksum,
            selectionSignature: CleanupPlan.signature(for: selected),
            sourceScanID: sourceScanID,
            sourceScanAt: sourceScanAt,
            campaignID: campaignID,
            items: planItems
        )
        return PreviewOutcome(results: results, plan: plan)
    }

    public func preflight(plan: CleanupPlan, now: Date = Date()) -> PlanPreflightResult {
        func failed(_ reason: PlanPreflightFailureReason, path: String? = nil, _ detail: String, checked: Int = 0) -> PlanPreflightResult {
            PlanPreflightResult(checkedAt: now, checkedItemCount: checked, failure: PlanPreflightFailure(reason: reason, path: path, detail: detail))
        }
        guard !currentTaskIsCancelled else { return failed(.cancelled, path: nil, "Cleanup was cancelled before final preflight.") }
        guard !plan.items.isEmpty else { return failed(.emptyPlan, path: nil, "Cleanup plan contains no targets.") }
        guard CampaignFreshness.isCurrent(plan: plan, now: now) else { return failed(.expired, path: nil, "Source scan or cleanup plan is stale. Run a new scan and preview.") }
        let planAge = now.timeIntervalSince(plan.createdAt)
        guard planAge >= 0, planAge <= PreviewAuthorization.maximumPlanAge else { return failed(.expired, path: nil, "Cleanup plan expired. Run Preview again.") }
        let normalizedPaths = plan.items.map { SafetyEngine.lexicalNormalize($0.path) }
        guard Set(normalizedPaths).count == normalizedPaths.count else { return failed(.duplicatePath, path: nil, "Cleanup plan contains duplicate target paths.") }
        guard plan.selectionSignature == CleanupPlan.signature(for: plan.items) else { return failed(.invalidSelectionSignature, path: nil, "Cleanup plan selection signature is invalid.") }
        guard plan.evidenceSignature != nil,
              plan.evidenceSignature == CleanupPlan.evidenceSignature(for: plan.items) else {
            return failed(.invalidEvidenceSignature, path: nil, "Cleanup plan evidence signature is missing or invalid.")
        }
        guard plan.manifestVersion == CleanupCatalog.policyVersion,
              plan.manifestChecksum == CleanupCatalog.manifestChecksum else {
            return failed(.manifestChanged, path: nil, "Cleanup manifest changed after preview. Run a new scan and preview.")
        }
        for (index, item) in plan.items.enumerated() {
            guard !currentTaskIsCancelled else { return failed(.cancelled, path: item.path, "Cleanup was cancelled during final preflight.", checked: index) }
            let decision = SafetyEngine.decision(for: item, home: home)
            guard decision.allowed else { return failed(.candidateChanged, path: item.path, decision.reason, checked: index + 1) }
            switch openFileChecker.state(for: item.path) {
            case .closed:
                continue
            case let .inUse(owners):
                return failed(.candidateOpen, path: item.path, "Candidate is open by: \(owners.joined(separator: ", ")). Close the owner and run a new preview.", checked: index + 1)
            case let .unavailable(detail):
                return failed(.detectorUnavailable, path: item.path, detail, checked: index + 1)
            }
        }
        return PlanPreflightResult(checkedAt: now, checkedItemCount: plan.items.count)
    }

    public func clean(plan: CleanupPlan, now: Date = Date()) -> [CleanupResult] {
        let finalPreflight = preflight(plan: plan, now: now)
        guard let failure = finalPreflight.failure else {
            return performClean(plan: plan)
        }
        let typedDetail = "Final plan preflight blocked [\(failure.reason.rawValue)]: \(failure.detail)"
        return [CleanupResult(path: failure.path ?? "plan://\(plan.id.uuidString)", status: "Blocked", detail: typedDetail)]
    }

    public func cleanWithReceipt(plan: CleanupPlan, now: Date = Date(), freeBytesBefore: Int64? = nil, freeBytesAfter: Int64? = nil) -> CleanupExecutionResult {
        let started = now
        let finalPreflight = preflight(plan: plan, now: now)
        let results: [CleanupResult]
        if let failure = finalPreflight.failure {
            results = [CleanupResult(path: failure.path ?? "plan://\(plan.id.uuidString)", status: "Blocked", detail: "Final plan preflight blocked [\(failure.reason.rawValue)]: \(failure.detail)")]
        } else {
            results = performClean(plan: plan)
        }
        let receipt = CleanupReceiptFactory.make(plan: plan, preflight: finalPreflight, results: results, startedAt: started, freeBytesBefore: freeBytesBefore, freeBytesAfter: freeBytesAfter)
        return CleanupExecutionResult(results: results, receipt: receipt)
    }

    private func performClean(plan: CleanupPlan) -> [CleanupResult] {
        let cache = ScanCache(home: home)
        var results: [CleanupResult] = []
        for item in plan.items {
            if currentTaskIsCancelled {
                results.append(CleanupResult(path: item.path, status: "Cancelled", detail: "Cleanup stopped before this target was moved."))
                continue
            }
            let decision = SafetyEngine.decision(for: item, home: home)
            guard decision.allowed else {
                results.append(CleanupResult(path: item.path, status: "Blocked", detail: decision.reason))
                break
            }
            switch openFileChecker.state(for: item.path) {
            case .closed:
                break
            case let .inUse(owners):
                results.append(CleanupResult(path: item.path, status: "Blocked", detail: "Candidate became open after plan preflight: \(owners.joined(separator: ", "))."))
                cache.save()
                return results
            case let .unavailable(detail):
                results.append(CleanupResult(path: item.path, status: "Blocked", detail: "Exact open-file revalidation became unavailable: \(detail)"))
                cache.save()
                return results
            }
            #if os(macOS)
            do {
                let url = URL(fileURLWithPath: item.path)
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                cache.invalidateTreeAndAncestors(path: item.path, upTo: home)
                let destination = resultingURL?.path ?? "Finder Trash"
                results.append(CleanupResult(
                    path: item.path,
                    status: "Moved to Trash",
                    detail: "Moved to \(destination). Space is not guaranteed to be free until Trash is emptied manually.",
                    resultingPath: resultingURL?.path
                ))
            } catch {
                results.append(CleanupResult(path: item.path, status: "Failed", detail: error.localizedDescription))
            }
            #else
            results.append(CleanupResult(path: item.path, status: "Unsupported platform", detail: "Finder Trash cleanup is available only on macOS."))
            #endif
        }
        cache.save()
        return results
    }

    private var currentTaskIsCancelled: Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }
}
