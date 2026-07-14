import Foundation

public struct CleanupRunner {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    public func previewSelected(_ items: [ScanItem]) -> PreviewOutcome {
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
            planItems.append(CleanupPlanItem(
                scanItemID: item.id,
                manifestID: manifestID,
                path: item.path,
                displayName: item.displayName,
                sizeBytes: item.sizeBytes,
                identity: identity,
                safetyReason: decision.reason
            ))
            let processNote = item.owningProcessRunning ? " The owning application appears to be running; close it before cleanup when practical." : ""
            results.append(CleanupResult(path: item.path, status: "Authorized for confirmation", detail: decision.reason + processNote))
        }

        guard planItems.count == selected.count else { return PreviewOutcome(results: results, plan: nil) }
        let plan = CleanupPlan(
            manifestVersion: CleanupCatalog.policyVersion,
            manifestChecksum: CleanupCatalog.manifestChecksum,
            items: planItems
        )
        return PreviewOutcome(results: results, plan: plan)
    }

    public func clean(plan: CleanupPlan, now: Date = Date()) -> [CleanupResult] {
        guard !plan.items.isEmpty else {
            return [CleanupResult(path: "plan://\(plan.id.uuidString)", status: "Blocked", detail: "Cleanup plan contains no targets.")]
        }
        let planAge = now.timeIntervalSince(plan.createdAt)
        guard planAge >= 0, planAge <= PreviewAuthorization.maximumPlanAge else {
            return [CleanupResult(path: "plan://\(plan.id.uuidString)", status: "Blocked", detail: "Cleanup plan expired. Run Preview again.")]
        }
        let normalizedPaths = plan.items.map { SafetyEngine.lexicalNormalize($0.path) }
        guard Set(normalizedPaths).count == normalizedPaths.count else {
            return [CleanupResult(path: "plan://\(plan.id.uuidString)", status: "Blocked", detail: "Cleanup plan contains duplicate target paths.")]
        }
        guard plan.manifestVersion == CleanupCatalog.policyVersion,
              plan.manifestChecksum == CleanupCatalog.manifestChecksum else {
            return [CleanupResult(path: "plan://\(plan.id.uuidString)", status: "Blocked", detail: "Cleanup manifest changed after preview. Run a new scan and preview.")]
        }
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
                continue
            }
            #if os(macOS)
            do {
                let url = URL(fileURLWithPath: item.path)
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                cache.invalidateTreeAndAncestors(path: item.path, upTo: home)
                let destination = resultingURL?.path ?? "Finder Trash"
                results.append(CleanupResult(path: item.path, status: "Moved to Trash", detail: "Moved to \(destination). Space is not guaranteed to be free until Trash is emptied manually."))
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
