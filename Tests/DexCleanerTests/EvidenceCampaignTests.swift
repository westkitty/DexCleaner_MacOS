import Foundation
import XCTest
@testable import DexCleanerCore

final class EvidenceCoreTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerEvidenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func selectedItem(entry: CatalogEntry, home: URL) throws -> ScanItem {
        let target = home.appendingPathComponent(entry.relativePath)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return ScanItem(
            manifestID: entry.id,
            path: target.path,
            displayName: entry.displayName,
            group: entry.group,
            category: entry.category,
            risk: entry.risk,
            sizeBytes: 64,
            explanation: entry.explanation,
            recoveryNote: entry.recoveryNote,
            action: entry.action,
            isSelected: true,
            measuredAt: Date(),
            measurementSource: .fresh
        )
    }

    func testManifestAndRuleProvenanceAreVersioned() throws {
        XCTAssertEqual(CleanupCatalog.schemaVersion, "1.0.0")
        XCTAssertEqual(CleanupCatalog.rulesVersion, "1.0.0")
        let entry = try XCTUnwrap(CleanupCatalog.entry(forManifestID: "homebrew-cache"))
        let provenance = CleanupCatalog.provenance(for: entry)
        XCTAssertTrue(provenance.isComplete)
        XCTAssertEqual(provenance.sourceKind, .declarativeManifest)
        XCTAssertEqual(provenance.sourceChecksum, CleanupCatalog.manifestChecksum)
    }

    func testEvidenceFingerprintBindsIdentityDecisionsRecordsAndProvenance() throws {
        let home = try temporaryHome()
        let entry = try XCTUnwrap(CleanupCatalog.entry(forManifestID: "homebrew-cache"))
        let item = try selectedItem(entry: entry, home: home)
        let identity = try XCTUnwrap(FileIdentity.capture(path: item.path))
        var evidence = try XCTUnwrap(CandidateEvidenceFactory.exactManifest(item: item, identity: identity, home: home.path))
        XCTAssertTrue(evidence.isActionable)
        XCTAssertEqual(evidence.fingerprint, evidence.calculatedFingerprint)

        evidence.protection = .unknown
        XCTAssertFalse(evidence.isActionable)
        XCTAssertNotEqual(evidence.fingerprint, evidence.calculatedFingerprint)
    }

    func testUnknownEvidenceFailsClosed() throws {
        let home = try temporaryHome()
        let entry = try XCTUnwrap(CleanupCatalog.entry(forManifestID: "homebrew-cache"))
        let source = try selectedItem(entry: entry, home: home)
        let preview = try XCTUnwrap(CleanupRunner(home: home.path).previewSelected([source]).plan)
        let original = try XCTUnwrap(preview.items.first)
        var evidence = try XCTUnwrap(original.evidence)
        evidence.protection = .unknown
        let changed = CleanupPlanItem(
            id: original.id,
            scanItemID: original.scanItemID,
            manifestID: original.manifestID,
            path: original.path,
            displayName: original.displayName,
            sizeBytes: original.sizeBytes,
            identity: original.identity,
            safetyReason: original.safetyReason,
            risk: original.risk,
            action: original.action,
            evidence: evidence
        )
        XCTAssertFalse(SafetyEngine.decision(for: changed, home: home.path).allowed)
    }

    func testVersionedMarkdownAndJSONShareRedactedEvidenceState() throws {
        let home = try temporaryHome()
        let reports = home.appendingPathComponent("reports")
        let entry = try XCTUnwrap(CleanupCatalog.entry(forManifestID: "homebrew-cache"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(entry.relativePath), withIntermediateDirectories: true)
        var issues: [ScanIssue] = []
        let item = try XCTUnwrap(DiskScanner(home: home.path).scanCatalogEntry(entry, issues: &issues))
        let report = ScanReport(
            timestamp: Date(),
            diskStatus: DiskStatus(),
            items: [item],
            results: [],
            scanDurationSeconds: 1,
            policyVersion: CleanupCatalog.policyVersion,
            manifestChecksum: CleanupCatalog.manifestChecksum,
            appVersion: "test",
            accessStatus: "Synthetic"
        )
        let markdownURL = try ReportWriter.write(report: report, format: .markdown, redaction: .homeRelative, destinationDirectory: reports, home: home.path)
        let jsonURL = try ReportWriter.write(report: report, format: .json, redaction: .homeRelative, destinationDirectory: reports, home: home.path)
        let markdown = try String(contentsOf: markdownURL)
        let jsonData = try Data(contentsOf: jsonURL)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanReport.self, from: jsonData)

        XCTAssertEqual(decoded.schemaVersion, ReportSchema.currentVersion)
        XCTAssertTrue(markdown.contains("Report schema: \(ReportSchema.currentVersion)"))
        XCTAssertTrue(markdown.contains("Candidate evidence and rule provenance"))
        XCTAssertTrue(json.contains("\"schemaVersion\""))
        XCTAssertFalse(markdown.contains(home.path))
        XCTAssertFalse(json.contains(home.path))
        XCTAssertEqual(decoded.evidenceBundles?.first?.provenance.ruleID, entry.id)
    }
}

final class PlanWidePreflightTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerPreflightTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func selectedItems(count: Int, home: URL) throws -> [ScanItem] {
        try CleanupCatalog.cleanableEntries.prefix(count).map { entry in
            let target = home.appendingPathComponent(entry.relativePath)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return ScanItem(
                manifestID: entry.id,
                path: target.path,
                displayName: entry.displayName,
                group: entry.group,
                category: entry.category,
                risk: entry.risk,
                sizeBytes: 64,
                explanation: entry.explanation,
                recoveryNote: entry.recoveryNote,
                action: entry.action,
                isSelected: true,
                measuredAt: Date(),
                measurementSource: .fresh
            )
        }
    }

    private var closedChecker: ExactOpenFileChecker {
        ExactOpenFileChecker { _ in .closed }
    }

    func testStaleFourthItemBlocksEntirePlanBeforeFirstMutation() throws {
        let home = try temporaryHome()
        let items = try selectedItems(count: 4, home: home)
        let runner = CleanupRunner(home: home.path, openFileChecker: closedChecker)
        let plan = try XCTUnwrap(runner.previewSelected(items).plan)
        let stalePath = try XCTUnwrap(plan.items.last?.path)
        try FileManager.default.removeItem(atPath: stalePath)
        try FileManager.default.createDirectory(atPath: stalePath, withIntermediateDirectories: true)

        let result = runner.clean(plan: plan)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.status, "Blocked")
        XCTAssertTrue(result.first?.detail.contains(PlanPreflightFailureReason.candidateChanged.rawValue) == true)
        XCTAssertTrue(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testOpenAfterPreviewBlocksBeforeMutation() throws {
        let home = try temporaryHome()
        let items = try selectedItems(count: 2, home: home)
        let openPath = items[1].path
        let checker = ExactOpenFileChecker { path in path == openPath ? .inUse(owners: ["fixture (pid 42)"]) : .closed }
        let runner = CleanupRunner(home: home.path, openFileChecker: checker)
        let plan = try XCTUnwrap(runner.previewSelected(items).plan)

        let preflight = runner.preflight(plan: plan)
        XCTAssertEqual(preflight.failure?.reason, .candidateOpen)
        XCTAssertEqual(preflight.checkedItemCount, 2)
        XCTAssertEqual(runner.clean(plan: plan).first?.status, "Blocked")
        XCTAssertTrue(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testRequiredDetectorUnavailableFailsClosed() throws {
        let home = try temporaryHome()
        let items = try selectedItems(count: 1, home: home)
        let runner = CleanupRunner(home: home.path, openFileChecker: ExactOpenFileChecker { _ in .unavailable(detail: "fixture unavailable") })
        let plan = try XCTUnwrap(runner.previewSelected(items).plan)
        XCTAssertEqual(runner.preflight(plan: plan).failure?.reason, .detectorUnavailable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: items[0].path))
    }

    func testEvidenceSignatureTamperingBlocksPlan() throws {
        let home = try temporaryHome()
        let items = try selectedItems(count: 1, home: home)
        let runner = CleanupRunner(home: home.path, openFileChecker: closedChecker)
        let plan = try XCTUnwrap(runner.previewSelected(items).plan)
        let changed = CleanupPlan(
            id: plan.id,
            createdAt: plan.createdAt,
            manifestVersion: plan.manifestVersion,
            manifestChecksum: plan.manifestChecksum,
            selectionSignature: plan.selectionSignature,
            evidenceSignature: "changed",
            items: plan.items
        )
        XCTAssertEqual(runner.preflight(plan: changed).failure?.reason, .invalidEvidenceSignature)
    }
}
