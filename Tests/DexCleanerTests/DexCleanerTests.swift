import Foundation
import XCTest
@testable import DexCleanerCore

final class DexCleanerSafetyTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func item(path: String, manifestID: String = "homebrew-cache", risk: RiskLevel = .safe, action: CleanupAction = .moveToTrash, selected: Bool = true) -> ScanItem {
        ScanItem(
            manifestID: manifestID,
            path: path,
            displayName: "Test item",
            group: "Homebrew",
            category: .packageCache,
            risk: risk,
            sizeBytes: 1024,
            explanation: "Test",
            recoveryNote: "Regenerate",
            action: action,
            isSelected: selected,
            measuredAt: Date(),
            measurementSource: .fresh
        )
    }

    func testBundledManifestLoadsAndValidates() {
        XCTAssertTrue(CleanupCatalog.isAvailable, CleanupCatalog.validationErrors.joined(separator: "\n"))
        XCTAssertEqual(CleanupCatalog.policyVersion, "1.0.0")
        XCTAssertFalse(CleanupCatalog.manifestChecksum.isEmpty)
        XCTAssertTrue(CleanupCatalog.cleanableEntries.allSatisfy { $0.risk == .safe && !$0.defaultSelected })
    }

    func testManifestValidatorRejectsDuplicateIDsOverlapsBroadRootsAndNonSafeEntries() {
        let entries = [
            CatalogEntry(id: "same", relativePath: "Library/Caches", displayName: "Broad", group: "Test", category: .exactCache, risk: .safe, explanation: "x", recoveryNote: "x"),
            CatalogEntry(id: "same", relativePath: "Library/Caches/App", displayName: "Nested", group: "Test", category: .exactCache, risk: .caution, explanation: "x", recoveryNote: "x", defaultSelected: true)
        ]
        let manifest = CleanupManifest(version: "1", name: "Test", policy: "Test", safeExactTargets: entries, forbiddenFragments: [])
        let errors = ManifestValidator.validate(manifest).joined(separator: "\n")
        XCTAssertTrue(errors.contains("Duplicate manifest id"))
        XCTAssertTrue(errors.contains("forbidden broad root"))
        XCTAssertTrue(errors.contains("not Safe"))
        XCTAssertTrue(errors.contains("selected by default"))
        XCTAssertTrue(errors.contains("Overlapping manifest paths"))
    }

    func testExactManifestTargetIsAllowed() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let decision = SafetyEngine.decision(for: item(path: target.path), home: home.path)
        XCTAssertTrue(decision.allowed, decision.reason)
    }

    func testBroadUnknownProtectedOutsideHomeAndNonSafeTargetsAreRejected() throws {
        let home = try temporaryHome()
        let broad = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: broad, withIntermediateDirectories: true)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: broad.path), home: home.path).allowed)

        let unknown = home.appendingPathComponent("Library/Application Support/Unknown/Cache")
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: unknown.path), home: home.path).allowed)

        let protected = home.appendingPathComponent("Documents/Important")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: protected.path), home: home.path).allowed)

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertFalse(SafetyEngine.decision(for: item(path: outside.path), home: home.path).allowed)

        let allowed = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: allowed.path, risk: .caution), home: home.path).allowed)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: allowed.path, action: .auditOnly), home: home.path).allowed)
    }

    func testSymlinkedExactTargetIsRejected() throws {
        let home = try temporaryHome()
        let parent = home.appendingPathComponent("Library/Caches")
        let userData = home.appendingPathComponent("Documents/Important")
        let link = parent.appendingPathComponent("Homebrew")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: userData.path)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: link.path), home: home.path).allowed)
    }

    func testPreviewCreatesImmutablePlanAndDoesNotMutateFilesystem() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: target.appendingPathComponent("artifact"))
        let outcome = CleanupRunner(home: home.path).previewSelected([item(path: target.path)])
        XCTAssertNotNil(outcome.plan)
        XCTAssertEqual(outcome.results.first?.status, "Authorized for confirmation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testFilesystemChangeAfterPreviewBlocksPlan() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let source = item(path: target.path)
        let outcome = CleanupRunner(home: home.path).previewSelected([source])
        let planItem = try XCTUnwrap(outcome.plan?.items.first)
        Thread.sleep(forTimeInterval: 1.05)
        try Data("changed".utf8).write(to: target.appendingPathComponent("new-file"))
        let decision = SafetyEngine.decision(for: planItem, home: home.path)
        XCTAssertFalse(decision.allowed)
        XCTAssertTrue(decision.reason.contains("changed after preview"))
    }

    func testPreviewAuthorizationInvalidatesWhenSelectionChanges() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let selected = item(path: target.path)
        let plan = try XCTUnwrap(CleanupRunner(home: home.path).previewSelected([selected]).plan)
        var authorization = PreviewAuthorization()
        authorization.authorize(items: [selected], plan: plan)
        XCTAssertTrue(authorization.isValid(items: [selected], plan: plan))
        var changed = selected
        changed.isSelected = false
        XCTAssertFalse(authorization.isValid(items: [changed], plan: plan))
        authorization.invalidate()
        XCTAssertFalse(authorization.isValid(items: [selected], plan: plan))
    }

    func testGitTemporaryPackIsAuditOnly() throws {
        let home = try temporaryHome()
        let pack = home.appendingPathComponent("Projects/Example/.git/objects/pack")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        let file = pack.appendingPathComponent("tmp_pack_old")
        try Data(repeating: 1, count: 1024).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: file.path)
        var issues: [ScanIssue] = []
        let findings = DiskScanner(home: home.path).gitTemporaryPackAuditItems(issues: &issues)
        XCTAssertTrue(findings.contains { $0.path == file.path })
        XCTAssertTrue(findings.allSatisfy { $0.action == .auditOnly && !$0.isCleanable })
    }

    func testScanCacheExpiresAndInvalidates() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let cache = ScanCache(home: home.path, maximumAge: 10)
        cache.store(path: target.path, sizeBytes: 99, scannedAt: Date())
        XCTAssertEqual(cache.cachedRecord(path: target.path)?.sizeBytes, 99)
        cache.invalidate(path: target.path)
        XCTAssertNil(cache.cachedRecord(path: target.path))
        cache.store(path: target.path, sizeBytes: 88, scannedAt: Date().addingTimeInterval(-20))
        XCTAssertNil(cache.cachedRecord(path: target.path))
    }

    func testScannerReportsFreshThenCachedMeasurement() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: target.appendingPathComponent("cache.bin"))
        let cache = ScanCache(home: home.path, maximumAge: 60)
        let scanner = DiskScanner(home: home.path, cache: cache)
        let entry = try XCTUnwrap(CleanupCatalog.entry(forManifestID: "homebrew-cache"))
        var issues: [ScanIssue] = []
        let first = try XCTUnwrap(scanner.scanCatalogEntry(entry, issues: &issues))
        let second = try XCTUnwrap(scanner.scanCatalogEntry(entry, issues: &issues))
        XCTAssertEqual(first.measurementSource, .fresh)
        XCTAssertEqual(second.measurementSource, .cache)
    }

    func testProtectedMarkersDoNotClaimMeasuredBytes() throws {
        let home = try temporaryHome()
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        let scanner = DiskScanner(home: home.path)
        let protected = scanner.protectedPathMarkers()
        XCTAssertTrue(protected.allSatisfy { $0.sizeBytes == 0 && $0.measurementSource == .notMeasured })
        let summaries = scanner.storageSummaries(from: protected)
        XCTAssertTrue(summaries.allSatisfy { $0.bytes == 0 })
    }


    func testManifestValidatorRejectsPathAliasesAndForbiddenTargets() {
        let entries = [
            CatalogEntry(id: "dot", relativePath: "Library/./Caches/Homebrew", displayName: "Dot", group: "Test", category: .exactCache, risk: .safe, explanation: "x", recoveryNote: "x"),
            CatalogEntry(id: "slash", relativePath: "Library//Caches/pip", displayName: "Slash", group: "Test", category: .exactCache, risk: .safe, explanation: "x", recoveryNote: "x"),
            CatalogEntry(id: "protected", relativePath: "Library/Caches/SecretState", displayName: "Protected", group: "Test", category: .exactCache, risk: .safe, explanation: "x", recoveryNote: "x")
        ]
        let manifest = CleanupManifest(
            version: "1",
            name: "Test",
            policy: "Test",
            safeExactTargets: entries,
            forbiddenFragments: ["/SecretState"]
        )
        let errors = ManifestValidator.validate(manifest).joined(separator: "\n")
        XCTAssertTrue(errors.contains("invalid canonical relative path"))
        XCTAssertTrue(errors.contains("conflicts with forbidden fragment"))
    }

    func testPlanManifestIDMustMatchItsExactPath() throws {
        let home = try temporaryHome()
        let homebrew = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: homebrew, withIntermediateDirectories: true)
        let identity = try XCTUnwrap(FileIdentity.capture(path: homebrew.path))
        let mismatched = CleanupPlanItem(
            scanItemID: UUID(),
            manifestID: "pip-cache",
            path: homebrew.path,
            displayName: "Mismatched",
            sizeBytes: 0,
            identity: identity,
            safetyReason: "Test"
        )
        let decision = SafetyEngine.decision(for: mismatched, home: home.path)
        XCTAssertFalse(decision.allowed)
        XCTAssertTrue(decision.reason.contains("Manifest ID and exact target path"))
    }

    func testExpiredAndDuplicatePlansAreBlocked() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let selected = item(path: target.path)
        let preview = try XCTUnwrap(CleanupRunner(home: home.path).previewSelected([selected]).plan)
        let expiredNow = preview.createdAt.addingTimeInterval(PreviewAuthorization.maximumPlanAge + 1)
        var authorization = PreviewAuthorization()
        authorization.authorize(items: [selected], plan: preview)
        XCTAssertFalse(authorization.isValid(items: [selected], plan: preview, now: expiredNow))
        XCTAssertEqual(CleanupRunner(home: home.path).clean(plan: preview, now: expiredNow).first?.status, "Blocked")

        let duplicate = CleanupPlan(
            manifestVersion: preview.manifestVersion,
            manifestChecksum: preview.manifestChecksum,
            items: [preview.items[0], preview.items[0]]
        )
        let result = CleanupRunner(home: home.path).clean(plan: duplicate)
        XCTAssertEqual(result.first?.status, "Blocked")
        XCTAssertTrue(result.first?.detail.contains("duplicate") == true)
    }

    func testCacheInvalidationRemovesTargetAndAncestorMeasurements() throws {
        let home = try temporaryHome()
        let library = home.appendingPathComponent("Library")
        let caches = library.appendingPathComponent("Caches")
        let target = caches.appendingPathComponent("Homebrew")
        let unrelated = home.appendingPathComponent("Unrelated")
        for url in [library, caches, target, unrelated] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let cache = ScanCache(home: home.path, maximumAge: 60)
        cache.store(path: library.path, sizeBytes: 1)
        cache.store(path: caches.path, sizeBytes: 2)
        cache.store(path: target.path, sizeBytes: 3)
        cache.store(path: unrelated.path, sizeBytes: 4)
        cache.invalidateTreeAndAncestors(path: target.path, upTo: home.path)
        XCTAssertNil(cache.cachedRecord(path: library.path))
        XCTAssertNil(cache.cachedRecord(path: caches.path))
        XCTAssertNil(cache.cachedRecord(path: target.path))
        XCTAssertEqual(cache.cachedRecord(path: unrelated.path)?.sizeBytes, 4)
    }

    func testMandatoryLargeFileExclusionsCannotBeRemoved() throws {
        let home = try temporaryHome()
        let scanner = DiskScanner(
            home: home.path,
            excludedLargeFileRelativePaths: ["Custom", "../escape", "Library/../Documents"]
        )
        XCTAssertTrue(Set(DiskScanner.mandatoryExcludedLargeFileRelativePaths).isSubset(of: Set(scanner.excludedLargeFileRelativePaths)))
        XCTAssertTrue(scanner.excludedLargeFileRelativePaths.contains("Custom"))
        XCTAssertFalse(scanner.excludedLargeFileRelativePaths.contains("../escape"))
        XCTAssertFalse(scanner.excludedLargeFileRelativePaths.contains("Library/../Documents"))
    }

    func testAuditChildrenPrunesProtectedHomeRootsBeforeMeasuring() throws {
        let home = try temporaryHome()
        for name in ["Projects", "Documents", "Library", ".cache"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        var issues: [ScanIssue] = []
        let findings = DiskScanner(home: home.path).auditChildren(rootPath: home.path, title: "Home", limit: 50, issues: &issues)
        XCTAssertFalse(findings.contains { ["Projects", "Documents", "Library", ".cache"].contains(URL(fileURLWithPath: $0.path).lastPathComponent) })
    }

    func testScanCompletenessCanRepresentFailurePartialAndCancellation() {
        let failure = ScanIssue(kind: .commandFailure, area: "Disk", detail: "failed")
        XCTAssertEqual(DiskScanner.determineCompleteness(cancelled: false, hasUsableData: false, issues: [failure]), .failed)
        XCTAssertEqual(DiskScanner.determineCompleteness(cancelled: false, hasUsableData: true, issues: [failure]), .partial)
        XCTAssertEqual(DiskScanner.determineCompleteness(cancelled: true, hasUsableData: true, issues: []), .cancelled)
        XCTAssertEqual(DiskScanner.determineCompleteness(cancelled: false, hasUsableData: true, issues: []), .complete)
    }
}

final class DexCleanerReportingTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMarkdownAndJSONReportsIncludeAuthorityCompletenessPlanAndRedaction() throws {
        let home = try temporaryHome()
        let reports = home.appendingPathComponent("reports")
        let path = home.appendingPathComponent("Library/Caches/Homebrew").path
        let identity = FileIdentity(fileNumber: 1, systemNumber: 2, fileType: "directory", sizeBytes: 1024, modificationTime: 1)
        let plan = CleanupPlan(manifestVersion: "1", manifestChecksum: "abc", items: [CleanupPlanItem(scanItemID: UUID(), manifestID: "homebrew-cache", path: path, displayName: "Homebrew", sizeBytes: 1024, identity: identity, safetyReason: "Authorized")])
        let scanItem = ScanItem(manifestID: "homebrew-cache", path: path, displayName: "Homebrew", group: "Homebrew", category: .packageCache, risk: .safe, sizeBytes: 1024, explanation: "Test", recoveryNote: "Test", action: .moveToTrash, isSelected: true, measuredAt: Date(), measurementSource: .fresh)
        let report = ScanReport(
            mode: .dryRun,
            timestamp: Date(),
            diskStatus: DiskStatus(filesystem: "test", size: "10G", used: "5G", available: "5G", capacity: "50%"),
            items: [scanItem],
            results: [CleanupResult(path: path, status: "Authorized for confirmation", detail: "Authorized at \(home.path)/Library")],
            storageSummaries: [StorageSummaryItem(label: "At \(home.path)", bytes: 1024, detail: "Measured under \(home.path)")],
            permissionDiagnostics: [PermissionDiagnostic(title: "Access", status: "Limited", detail: "Cannot read \(home.path)/Library", remediation: "Open \(home.path)")],
            warnings: ["Warning from \(home.path)"],
            issues: [ScanIssue(kind: .timeout, area: "Audit \(home.path)", detail: "Timed out at \(home.path)")],
            completeness: .partial,
            scanDurationSeconds: 1,
            policyVersion: "1",
            manifestChecksum: "abc",
            appVersion: "1",
            accessStatus: "Limited",
            cleanupPlan: plan
        )
        let markdownURL = try ReportWriter.write(report: report, format: .markdown, redaction: .homeRelative, destinationDirectory: reports, home: home.path)
        let markdown = try String(contentsOf: markdownURL)
        XCTAssertTrue(markdown.contains("Manifest checksum: abc"))
        XCTAssertTrue(markdown.contains("Scan completeness: Partial"))
        XCTAssertTrue(markdown.contains("Plan ID"))
        XCTAssertTrue(markdown.contains("~/Library/Caches/Homebrew"))
        XCTAssertFalse(markdown.contains(home.path))
        let secondMarkdownURL = try ReportWriter.write(report: report, format: .markdown, redaction: .homeRelative, destinationDirectory: reports, home: home.path)
        XCTAssertNotEqual(markdownURL.lastPathComponent, secondMarkdownURL.lastPathComponent)

        let jsonURL = try ReportWriter.write(report: report, format: .json, redaction: .homeRelative, destinationDirectory: reports, home: home.path)
        let data = try Data(contentsOf: jsonURL)
        let decoded = try JSONDecoder.withISO8601.decode(ScanReport.self, from: data)
        XCTAssertEqual(decoded.completeness, .partial)
        XCTAssertEqual(decoded.manifestChecksum, "abc")
        XCTAssertEqual(decoded.items.first?.path, "~/Library/Caches/Homebrew")
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains(home.path) ?? true)
    }

    func testOperationLedgerIsAppendOnlyJSONLines() throws {
        let home = try temporaryHome()
        let first = OperationLedgerEntry(mode: .dryRun, planID: UUID(), manifestVersion: "1", manifestChecksum: "a", results: [], movedToTrashBytes: 0)
        let second = OperationLedgerEntry(mode: .cleanup, planID: UUID(), manifestVersion: "1", manifestChecksum: "a", results: [CleanupResult(path: "x", status: "Moved to Trash", detail: "x")], movedToTrashBytes: 1)
        let url = try OperationLedger.append(first, home: home.path)
        _ = try OperationLedger.append(second, home: home.path)
        let lines = try String(contentsOf: url).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
    }
}

final class ShellCancellationTests: XCTestCase {
    func testShellRunRespondsToTaskCancellation() async {
        let task = Task.detached { Shell.run("/bin/sleep", ["5"], timeout: 10) }
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(result.durationSeconds, 3)
    }
}

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
