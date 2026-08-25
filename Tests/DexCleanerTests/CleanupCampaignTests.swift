import Foundation
import XCTest
@testable import DexCleanerCore

final class CleanupCampaignTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerCampaignTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func selectedHomebrewItem(home: URL) throws -> ScanItem {
        let entry = try XCTUnwrap(CleanupCatalog.entry(forManifestID: "homebrew-cache"))
        let target = home.appendingPathComponent(entry.relativePath)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return ScanItem(manifestID: entry.id, path: target.path, displayName: entry.displayName, group: entry.group, category: entry.category, risk: entry.risk, sizeBytes: 128, explanation: entry.explanation, recoveryNote: entry.recoveryNote, action: entry.action, isSelected: true, measuredAt: Date(), measurementSource: .fresh)
    }

    func testAbsentApprovedTargetProducesBlockedIdempotentReceiptWithoutRetry() throws {
        let home = try temporaryHome()
        let source = try selectedHomebrewItem(home: home)
        let runner = CleanupRunner(home: home.path, openFileChecker: ExactOpenFileChecker { _ in .closed })
        let plan = try XCTUnwrap(runner.previewSelected([source]).plan)
        try FileManager.default.removeItem(atPath: source.path)

        let execution = runner.cleanWithReceipt(plan: plan, freeBytesBefore: 100, freeBytesAfter: 100)
        XCTAssertEqual(execution.results.first?.status, "Blocked")
        XCTAssertEqual(execution.receipt.schemaVersion, CleanupReceiptSchema.currentVersion)
        XCTAssertEqual(execution.receipt.terminalState, .blocked)
        XCTAssertEqual(execution.receipt.candidates.first?.attemptState, .skippedAlreadyAbsent)
        XCTAssertEqual(execution.receipt.accounting.movedToTrashBytes, 0)
        XCTAssertNil(execution.receipt.accounting.estimatedPhysicalReclaimBytes)
        XCTAssertEqual(execution.receipt.accounting.observedFreeSpaceDelta, 0)
        XCTAssertTrue(execution.receipt.accounting.physicalReclaimStatement.contains("does not prove"))
        XCTAssertTrue(CleanupCampaignEvaluator.retryCandidateIDs(from: execution.receipt).isEmpty)
    }

    func testPartialReceiptKeepsCompletedAndRemainingItemsDistinct() throws {
        let home = try temporaryHome()
        let entries = Array(CleanupCatalog.cleanableEntries.prefix(2))
        let items = try entries.map { entry -> ScanItem in
            let target = home.appendingPathComponent(entry.relativePath)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return ScanItem(manifestID: entry.id, path: target.path, displayName: entry.displayName, group: entry.group, category: entry.category, risk: entry.risk, sizeBytes: 10, explanation: entry.explanation, recoveryNote: entry.recoveryNote, action: entry.action, isSelected: true)
        }
        let runner = CleanupRunner(home: home.path, openFileChecker: ExactOpenFileChecker { _ in .closed })
        let plan = try XCTUnwrap(runner.previewSelected(items).plan)
        let preflight = PlanPreflightResult(checkedAt: Date(), checkedItemCount: 2)
        let results = [
            CleanupResult(path: plan.items[0].path, status: "Moved to Trash", detail: "Synthetic", resultingPath: "/fixture/Trash/one"),
            CleanupResult(path: plan.items[1].path, status: "Blocked", detail: "Synthetic stale state")
        ]
        let receipt = CleanupReceiptFactory.make(plan: plan, preflight: preflight, results: results, startedAt: Date())
        XCTAssertEqual(receipt.terminalState, .partial)
        XCTAssertEqual(receipt.candidates.map(\.attemptState), [.movedToTrash, .blocked])
        XCTAssertEqual(receipt.accounting.movedToTrashBytes, 10)
        XCTAssertEqual(CleanupCampaignEvaluator.retryCandidateIDs(from: receipt), [plan.items[1].manifestID])
    }

    func testStopRecommendationIsTransparentAndRecomputed() {
        let review = ScanItem(path: "audit://one", displayName: "Review", category: .auditOnly, risk: .auditOnly, sizeBytes: 0, explanation: "Review", action: .auditOnly, isSelected: false)
        let stop = CleanupCampaignEvaluator.recommendation(items: [review])
        XCTAssertTrue(stop.shouldStop)
        XCTAssertTrue(stop.reasons.contains { $0.contains("No evidence-proven actionable") })

        var actionable = review
        actionable.risk = .safe
        actionable.action = .moveToTrash
        XCTAssertFalse(CleanupCampaignEvaluator.recommendation(items: [actionable]).shouldStop)
        XCTAssertTrue(CleanupCampaignEvaluator.recommendation(items: [actionable], objectiveSatisfied: true).shouldStop)
    }

    func testProgressAndReceiptAreVersionedCodableArtifacts() throws {
        let start = Date()
        let progress = CampaignProgressSnapshot(phase: "Hashing", state: .cancelled, candidatesConsidered: 4, filesExamined: 10, bytesExamined: 20, filesHashed: 2, bytesHashed: 8, partialResultCount: 1, startedAt: start, heartbeatAt: start)
        XCTAssertEqual(try JSONDecoder().decode(CampaignProgressSnapshot.self, from: JSONEncoder().encode(progress)).state, .cancelled)

        let directory = try temporaryHome()
        let preflight = PlanPreflightResult(checkedAt: start, checkedItemCount: 0, failure: PlanPreflightFailure(reason: .emptyPlan, detail: "Synthetic"))
        let receipt = CleanupActionReceipt(planID: UUID(), startedAt: start, endedAt: start, terminalState: .blocked, planPreflight: preflight, candidates: [], accounting: ReclaimAccounting(logicalCandidateBytes: 0, movedToTrashBytes: 0))
        let url = try ActionReceiptWriter.write(receipt, directory: directory)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"schemaVersion\"") == true)
    }

    func testCampaignFreshnessAndRerankRequireNewScanWhenStale() throws {
        let home = try temporaryHome()
        let source = try selectedHomebrewItem(home: home)
        let scanID = UUID()
        let campaignID = UUID()
        let staleAt = Date(timeIntervalSinceNow: -(CampaignFreshness.maximumScanAge + 1))
        let runner = CleanupRunner(home: home.path, openFileChecker: ExactOpenFileChecker { _ in .closed })
        let plan = try XCTUnwrap(runner.previewSelected([source], sourceScanID: scanID, sourceScanAt: staleAt, campaignID: campaignID).plan)
        XCTAssertEqual(runner.preflight(plan: plan).failure?.reason, .expired)

        var small = source
        small.sizeBytes = 1
        var large = source
        large.path += "-review"
        large.sizeBytes = 100
        large.risk = .auditOnly
        large.action = .auditOnly
        XCTAssertEqual(CleanupCampaignEvaluator.reranked([large, small]).first?.path, small.path)
    }

    func testGuidedCampaignIsExplicitGroupedAndStartsWithNoSelection() throws {
        let home = try temporaryHome()
        let campaignID = UUID()
        let result = GuidedCleanupCampaign(home: home.path).run(campaignID: campaignID)
        XCTAssertEqual(result.campaignID, campaignID)
        XCTAssertEqual(Set(result.domains.map(\.domain)), Set(CampaignDomain.allCases))
        XCTAssertTrue(result.snapshot.items.allSatisfy { !$0.isSelected })
        XCTAssertEqual(result.progress.state, .completed)
        XCTAssertEqual(result.stopRecommendation.actionableCount, result.snapshot.items.filter(\.isCleanable).count)
        XCTAssertTrue(result.domains.first(where: { $0.domain == .duplicates })?.detail.contains("user-selected scope") == true)
    }
}
