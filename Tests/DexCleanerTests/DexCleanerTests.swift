import Foundation
import XCTest
@testable import DexCleanerCore
#if os(macOS)
import CoreServices
#endif

final class DexCleanerSafetyLegacyTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
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

final class DexCleanerContractTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerContractTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func selectedItem(path: String, manifestID: String = "homebrew-cache") -> ScanItem {
        ScanItem(
            manifestID: manifestID,
            path: path,
            displayName: "Synthetic cache",
            group: "Homebrew",
            category: .packageCache,
            risk: .safe,
            sizeBytes: 64,
            explanation: "Synthetic",
            recoveryNote: "Synthetic",
            action: .moveToTrash,
            isSelected: true,
            measuredAt: Date(),
            measurementSource: .fresh
        )
    }

    func testDocumentsAssetsAntigravityAuthenticationSessionsCloudProjectsAndGitAreProtected() throws {
        let home = try temporaryHome()
        let protectedRelativePaths = [
            "Documents",
            "Documents/assets",
            ".antigravity",
            ".antigravity_archive",
            "Library/Application Support/Antigravity",
            "Library/Application Support/Example/Authentication",
            "Library/Application Support/Example/Sessions",
            "Library/Application Support/Example/Conversations",
            "Library/CloudStorage/Provider",
            "Projects/Example",
            "Developer/Example/.git"
        ]
        for relative in protectedRelativePaths {
            let target = home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let decision = SafetyEngine.decision(for: selectedItem(path: target.path), home: home.path)
            XCTAssertFalse(decision.allowed, "Protected path unexpectedly allowed: \(relative)")
        }
    }

    func testPermissionFailureProducesPartialStatusWithoutInventedBytes() {
        let issue = ScanIssue(kind: .permission, area: "Synthetic denied path", detail: "Permission denied")
        XCTAssertEqual(
            DiskScanner.determineCompleteness(cancelled: false, hasUsableData: true, issues: [issue]),
            .partial
        )
        let marker = ScanItem(
            path: "permission://Synthetic denied path",
            displayName: "Denied",
            category: .permissionDiagnostic,
            risk: .caution,
            sizeBytes: 0,
            explanation: "Permission denied",
            action: .auditOnly,
            isSelected: false,
            measurementSource: .notMeasured
        )
        XCTAssertEqual(marker.measurementSource, .notMeasured)
        XCTAssertFalse(marker.isCleanable)
    }

    func testManifestChangeAndSelectionSignatureChangeBlockCleanup() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let plan = try XCTUnwrap(CleanupRunner(home: home.path).previewSelected([selectedItem(path: target.path)]).plan)

        let changedManifest = CleanupPlan(
            id: plan.id,
            createdAt: plan.createdAt,
            manifestVersion: plan.manifestVersion,
            manifestChecksum: "changed",
            selectionSignature: plan.selectionSignature,
            items: plan.items
        )
        XCTAssertEqual(CleanupRunner(home: home.path).clean(plan: changedManifest).first?.status, "Blocked")

        let changedSelection = CleanupPlan(
            id: plan.id,
            createdAt: plan.createdAt,
            manifestVersion: plan.manifestVersion,
            manifestChecksum: plan.manifestChecksum,
            selectionSignature: "changed",
            items: plan.items
        )
        XCTAssertEqual(CleanupRunner(home: home.path).clean(plan: changedSelection).first?.status, "Blocked")
    }

    func testDuplicateMountIdentitiesAreCountedOnce() {
        let records = [
            MountedFilesystemRecord(deviceIdentity: "disk9s1", filesystemIdentity: "abc", mountPath: "/Volumes/one"),
            MountedFilesystemRecord(deviceIdentity: "disk9s1", filesystemIdentity: "abc", mountPath: "/Volumes/one-1"),
            MountedFilesystemRecord(deviceIdentity: "disk10s1", filesystemIdentity: "def", mountPath: "/Volumes/two")
        ]
        XCTAssertEqual(MountedFilesystemDeduplicator.unique(records).count, 2)
    }

    func testOnlyOneOperationCanHoldAuthority() {
        let coordinator = OperationCoordinator()
        XCTAssertTrue(coordinator.begin())
        XCTAssertFalse(coordinator.begin())
        coordinator.end()
        XCTAssertTrue(coordinator.begin())
        coordinator.end()
    }

    func testInterruptedLedgerOperationReconcilesWithoutRetry() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let plan = try XCTUnwrap(CleanupRunner(home: home.path).previewSelected([selectedItem(path: target.path)]).plan)
        let pending = try OperationLedger.begin(plan: plan, home: home.path)
        let reconciled = try OperationLedger.reconcilePendingOperations(home: home.path)
        XCTAssertEqual(reconciled.first?.operationID, pending.operationID)
        XCTAssertEqual(reconciled.first?.state, .reconciled)
        XCTAssertEqual(reconciled.first?.results.first?.status, "Reconciled")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testStorageModelDefinesAvailableForWorkAndMeasurementState() {
        let status = StorageCapacityProvider.measure()
        XCTAssertNotNil(status.totalBytes)
        XCTAssertNotNil(status.availableForWorkBytes)
        XCTAssertNotEqual(status.state, .failed)
        XCTAssertTrue(status.detail.contains("Available for work"))
    }

    func testFreshCapacityExpiresToCachedAtTheDocumentedInterval() {
        let measuredAt = Date(timeIntervalSince1970: 1_000)
        let fresh = DiskStatus(
            availableForWorkBytes: 1,
            state: .fresh,
            measuredAt: measuredAt,
            detail: "Fresh native measurement."
        )

        XCTAssertEqual(
            StorageCapacityProvider.presentationStatus(
                fresh,
                now: measuredAt.addingTimeInterval(StorageCapacityProvider.freshnessInterval)
            ).state,
            .fresh
        )
        let expired = StorageCapacityProvider.presentationStatus(
            fresh,
            now: measuredAt.addingTimeInterval(StorageCapacityProvider.freshnessInterval + 0.001)
        )
        XCTAssertEqual(expired.state, .cached)
        XCTAssertEqual(expired.measuredAt, measuredAt)
        XCTAssertTrue(expired.detail.contains("60-second freshness interval"))
    }

    func testCapacityTimestampsUseTheRequestedMacTimezoneConsistently() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let detroit = try! XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        let utc = try! XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")

        let refreshTimestamp = StorageCapacityProvider.displayTimestamp(date, timeZone: detroit, locale: locale)
        let scanTimestamp = StorageCapacityProvider.displayTimestamp(date, timeZone: detroit, locale: locale)
        let utcTimestamp = StorageCapacityProvider.displayTimestamp(date, timeZone: utc, locale: locale)
        let defaultTimestamp = StorageCapacityProvider.displayTimestamp(date)
        let macTimestamp = StorageCapacityProvider.displayTimestamp(
            date,
            timeZone: .autoupdatingCurrent,
            locale: .autoupdatingCurrent
        )

        XCTAssertEqual(refreshTimestamp, scanTimestamp)
        XCTAssertNotEqual(refreshTimestamp, utcTimestamp)
        XCTAssertEqual(defaultTimestamp, macTimestamp)
    }

    func testAuthorizedSyntheticFixtureCanMoveToTrashAndRestore() throws {
        guard ProcessInfo.processInfo.environment["DEXCLEANER_RUN_TRASH_TEST"] == "1" else {
            throw XCTSkip("Set DEXCLEANER_RUN_TRASH_TEST=1 only for the controlled release-candidate Trash round trip.")
        }

        let fixtureRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/DexCleaner/TestFixtures", isDirectory: true)
            .appendingPathComponent("roundtrip-\(UUID().uuidString)", isDirectory: true)
        let syntheticHome = fixtureRoot.appendingPathComponent("SyntheticHome", isDirectory: true)
        let target = syntheticHome.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("DexCleaner controlled fixture".utf8).write(to: target.appendingPathComponent("fixture.txt"), options: .atomic)

        let preview = try XCTUnwrap(CleanupRunner(home: syntheticHome.path).previewSelected([selectedItem(path: target.path)]).plan)
        let result = try XCTUnwrap(CleanupRunner(home: syntheticHome.path).clean(plan: preview).first)
        XCTAssertEqual(result.status, "Moved to Trash")
        XCTAssertFalse(result.detail.localizedCaseInsensitiveContains("freed"))
        let trashURL = try XCTUnwrap(result.resultingPath.map(URL.init(fileURLWithPath:)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))

        try FileManager.default.moveItem(at: trashURL, to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("fixture.txt").path))

        let finalState = """
        fixture=\(target.path)
        final_state=restored
        trash_was_emptied=false
        recorded_at=\(ISO8601DateFormatter().string(from: Date()))
        """
        try finalState.write(to: fixtureRoot.appendingPathComponent("FINAL_STATE.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("FINAL_STATE.txt").path))
    }
}

final class DexCleanerSafetyTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerMonitoring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sample(_ minute: Int, available: Int64? = 20_000_000_000, free: Int64? = 15_000_000_000, state: StorageMeasurementState = .fresh) -> CapacitySample {
        CapacitySample(timestamp: Date(timeIntervalSince1970: TimeInterval(minute * 60)), totalBytes: 100_000_000_000, immediatelyFreeBytes: free, availableForWorkBytes: available, opportunisticBytes: nil, potentiallyPurgeableBytes: nil, state: state, source: "Synthetic", trigger: .syntheticTest)
    }

    func testCapacityHistoryPersistsRecoversMalformedTailAndReportsRangeStatistics() throws {
        let directory = try temporaryDirectory(), store = CapacityHistoryStore(directory: directory)
        try store.record(sample(0)); try store.record(sample(5, available: 19_000_000_000)); try store.record(sample(10, available: 18_000_000_000, state: .disputed))
        let raw = directory.appendingPathComponent("capacity-raw-v1.ndjson")
        let handle = try FileHandle(forWritingTo: raw); try handle.seekToEnd(); try handle.write(contentsOf: Data("{bad final record".utf8)); try handle.close()
        let stats = store.statistics(range: .day, now: Date(timeIntervalSince1970: 900))
        XCTAssertEqual(stats.records.count, 3)
        XCTAssertEqual(stats.netChange, -2_000_000_000)
        XCTAssertEqual(stats.failedOrDisputedCount, 1)
        XCTAssertGreaterThan(store.summary().bytes, 0)
    }

    func testCapacityHistoryCompactsAgedSamplesWithoutErasingValidHistory() throws {
        let directory = try temporaryDirectory(), store = CapacityHistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 80_000_000)
        try store.record(CapacitySample(timestamp: now.addingTimeInterval(-40 * 86_400), totalBytes: 1, immediatelyFreeBytes: 9, availableForWorkBytes: 10, opportunisticBytes: nil, potentiallyPurgeableBytes: nil, state: .fresh, source: "Synthetic", trigger: .syntheticTest))
        try store.record(CapacitySample(timestamp: now.addingTimeInterval(-120), totalBytes: 1, immediatelyFreeBytes: 8, availableForWorkBytes: 9, opportunisticBytes: nil, potentiallyPurgeableBytes: nil, state: .fresh, source: "Synthetic", trigger: .syntheticTest))
        try store.compact(now: now)
        XCTAssertEqual(store.summary().rawSampleCount, 1)
        XCTAssertGreaterThanOrEqual(store.summary().aggregateCount, 1)
    }

    func testSamplingGateCoalescesRapidRequestsAndAlertEpisodesDoNotSpam() {
        var gate = CapacitySamplingGate()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(gate.accepts(start)); XCTAssertFalse(gate.accepts(start.addingTimeInterval(30))); XCTAssertTrue(gate.accepts(start.addingTimeInterval(61)))
        let config = StorageAlertConfiguration(), warning = StorageAlertEngine.evaluate(immediatelyFreeBytes: 9_000_000_000, at: start, configuration: config, state: StorageAlertState())
        XCTAssertEqual(warning.event, .warningCrossed); XCTAssertTrue(warning.shouldNotify)
        let repeatWarning = StorageAlertEngine.evaluate(immediatelyFreeBytes: 8_000_000_000, at: start.addingTimeInterval(120), configuration: config, state: warning.state)
        XCTAssertEqual(repeatWarning.event, .none); XCTAssertFalse(repeatWarning.shouldNotify)
        let critical = StorageAlertEngine.evaluate(immediatelyFreeBytes: 4_000_000_000, at: start.addingTimeInterval(3_700), configuration: config, state: repeatWarning.state)
        XCTAssertEqual(critical.event, .criticalCrossed)
        let recovered = StorageAlertEngine.evaluate(immediatelyFreeBytes: 12_000_000_000, at: start.addingTimeInterval(7_400), configuration: config, state: critical.state)
        XCTAssertEqual(recovered.event, .recovered)
    }

    func testDriverWatchlistComparisonDropDetectionAndForecastRemainDiagnostic() throws {
        let directory = try temporaryDirectory(), store = StorageDriverStore(directory: directory)
        let watch = try store.addWatch(name: "Project", path: "/tmp/project")
        XCTAssertTrue(watch.isWatch)
        try store.append(DriverSnapshot(driverID: watch.id, timestamp: Date(timeIntervalSince1970: 1), bytes: 10, state: .complete, duration: 0, filesystemNumber: 1))
        try store.append(DriverSnapshot(driverID: watch.id, timestamp: Date(timeIntervalSince1970: 2), bytes: 30, state: .complete, duration: 0, filesystemNumber: 1))
        let comparison = StorageDriverAnalytics.compare(drivers: [watch], newest: [watch.id: try XCTUnwrap(store.snapshots(for: watch.id).last)], earlier: [watch.id: try XCTUnwrap(store.snapshots(for: watch.id).first)], capacityChange: -25)
        XCTAssertEqual(comparison.changes.first?.1, 20)
        XCTAssertTrue(comparison.confidence.contains("causation is not inferred"))
        let decline = [sample(0, available: 20_000_000_000), sample(360, available: 17_000_000_000)]
        XCTAssertNotNil(StorageDriverAnalytics.significantDrop(samples: decline, now: Date(timeIntervalSince1970: 22_000)))
        XCTAssertNil(CapacityForecast.estimate(samples: [sample(0), sample(5)]))
        try store.removeWatch(watch.id); XCTAssertTrue(store.watchlist().isEmpty)
    }

    func testChartSeriesSeparatesAlternatingMetricsAndGapTolerancePreservesNormalCadence() {
        let records: [CapacityHistoryRecord] = [.raw(sample(0, available: 12_000_000_000, free: 9_000_000_000)), .raw(sample(5, available: 11_000_000_000, free: 8_000_000_000))]
        let points = CapacityChartSeries.points(records: records)
        XCTAssertEqual(points.filter { $0.metric == .availableForWork }.map(\.value), [12_000_000_000, 11_000_000_000])
        XCTAssertEqual(points.filter { $0.metric == .immediatelyFree }.map(\.value), [9_000_000_000, 8_000_000_000])
        XCTAssertFalse(CapacityHistoryStore.isMaterialGap(300))
        XCTAssertFalse(CapacityHistoryStore.isMaterialGap(301))
        XCTAssertFalse(CapacityHistoryStore.isMaterialGap(360))
        XCTAssertTrue(CapacityHistoryStore.isMaterialGap(661))
        XCTAssertTrue(CapacityHistoryStore.isMaterialGap(3_600))
    }

    func testAlertEpisodeRetainsCrossingValueAndResetsAfterRecovery() {
        let start = Date(timeIntervalSince1970: 5_000), configuration = StorageAlertConfiguration()
        let warning = StorageAlertEngine.evaluate(immediatelyFreeBytes: 9_180_000_000, at: start, configuration: configuration, state: StorageAlertState())
        XCTAssertEqual(warning.state.episodeStartedImmediatelyFreeBytes, 9_180_000_000)
        let later = StorageAlertEngine.evaluate(immediatelyFreeBytes: 8_060_000_000, at: start.addingTimeInterval(300), configuration: configuration, state: warning.state)
        XCTAssertEqual(later.state.episodeStartedImmediatelyFreeBytes, 9_180_000_000)
        let recovered = StorageAlertEngine.evaluate(immediatelyFreeBytes: 12_000_000_000, at: start.addingTimeInterval(600), configuration: configuration, state: later.state)
        XCTAssertNil(recovered.state.episodeStartedImmediatelyFreeBytes)
    }

    func testReportLabelsNoScanAsStatusAndPreservesExplicitModes() {
        var status = ScanReport(mode: .scan, timestamp: Date(), diskStatus: DiskStatus(), items: [], results: [], storageSummaries: [], permissionDiagnostics: [], warnings: [], issues: [], completeness: .notRun, scanDurationSeconds: 0, policyVersion: "1", manifestChecksum: "x", appVersion: "1", accessStatus: "Not tested")
        XCTAssertEqual(ReportWriter.reportLabel(for: status), "Status")
        status.completeness = .complete
        XCTAssertEqual(ReportWriter.reportLabel(for: status), "Scan")
        status.mode = .cleanup
        XCTAssertEqual(ReportWriter.reportLabel(for: status), "Cleanup")
    }

    func testIncidentThresholdsHysteresisAndSleepWakeTrigger() {
        let start = Date(timeIntervalSince1970: 90_000)
        func record(_ seconds: TimeInterval, _ free: Int64) -> RecorderCapacitySample {
            RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: free, availableForWorkBytes: free, state: .fresh, measuredAt: start.addingTimeInterval(seconds)), trigger: "Synthetic", now: start.addingTimeInterval(seconds))
        }
        let before = record(0, 12_000_000_000)
        let after = record(300, 11_400_000_000)
        XCTAssertEqual(IncidentTriggerEngine.trigger(samples: [before], preSleep: nil, current: after), .consecutive512MiB)
        XCTAssertEqual(IncidentTriggerEngine.trigger(samples: [before], preSleep: before, current: after), .consecutive512MiB)
        XCTAssertNil(IncidentTriggerEngine.trigger(samples: [before], preSleep: nil, current: record(300, 11_600_000_000)))
    }

    func testChangedPathCoalescingKeepsMeaningfulRoots() {
        XCTAssertEqual(ChangedPathCoalescer.ancestor(for: "/Users/a/Project/.build/arm64/release/x"), "/Users/a/Project/.build")
        XCTAssertEqual(ChangedPathCoalescer.ancestor(for: "/Users/a/Library/Application Support/Claude/state/x"), "/Users/a/Library/Application Support/Claude")
        XCTAssertEqual(ChangedPathCoalescer.coalesce(["/Users/a/Project/.build/a", "/Users/a/Project/.build/b"]).count, 1)
    }

    func testFocusedAllocatedMeasurementRefusesSymlinksAndPreservesLogicalDifference() throws {
        let root = try temporaryHome()
        let safe = root.appendingPathComponent("safe.bin")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try Data(repeating: 7, count: 8192).write(to: safe)
        try Data(repeating: 9, count: 8192).write(to: outside)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: outside.path)
        let measurement = FocusedAllocationMeasurer.measure(root: root, limit: 100)
        XCTAssertGreaterThan(measurement.logicalBytes, 0)
        XCTAssertGreaterThanOrEqual(measurement.allocatedBytes, 0)
        XCTAssertEqual(measurement.complete.rawValue, EvidenceCompleteness.complete.rawValue)
    }

    func testCloudPlaceholderModelNeverTreatsLogicalRepresentationAsAllocated() {
        let cloud = CloudProviderEvidence(provider: "Synthetic", accountLabel: "redacted", domainIdentifier: "synthetic", root: "~/Cloud", state: "Online only", logicalBytes: 100_000_000_000, allocatedUserBytes: 0, placeholderBytes: 100_000_000_000, downloadedBytes: 0, pinnedBytes: 0, cacheBytes: 10, databaseBytes: 20, completeness: .complete, safeAction: "Reveal in Finder")
        XCTAssertEqual(cloud.allocatedUserBytes, 0)
        XCTAssertGreaterThan(cloud.placeholderBytes, cloud.allocatedUserBytes)
        XCTAssertFalse(cloud.safeAction.localizedCaseInsensitiveContains("delete"))
    }

    func testIncidentReportPersistenceAndDiagnosticCleanupSeparation() throws {
        let home = try temporaryHome(); let store = IncidentStore(home: home.path)
        let status = DiskStatus(immediatelyFreeBytes: 8_000_000_000, availableForWorkBytes: 9_000_000_000, state: .fresh, measuredAt: Date())
        let sample = RecorderCapacitySample(status: status, trigger: "Synthetic")
        var incident = StorageIncident(trigger: .manual, before: sample)
        incident.after = RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: 7_000_000_000, availableForWorkBytes: 8_000_000_000, state: .fresh, measuredAt: Date()), trigger: "Synthetic")
        incident.measurements = [PathMeasurement(path: "~/Library/Caches/Synthetic", classification: .cache, allocatedBytes: 20, logicalBytes: 40)]
        let urls = try StorageIncidentReportWriter.write(incident, store: store)
        XCTAssertEqual(urls.count, 3)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse(incident.measurements.contains { $0.classification == .cache && $0.path.contains("CleanupManifest") })
    }

    func testReservePathCannotTargetAnyOtherLocation() throws {
        let home = try temporaryHome()
        let allowed = URL(fileURLWithPath: home.path).appendingPathComponent(EmergencyReserveController.relativePath)
        XCTAssertTrue(EmergencyReserveController.isOnlyAllowedPath(allowed, home: home.path))
        XCTAssertFalse(EmergencyReserveController.isOnlyAllowedPath(home.appendingPathComponent("Documents/reserve.bin"), home: home.path))
        let low = RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: 2_000_000_000, availableForWorkBytes: 2_000_000_000, state: .fresh, measuredAt: Date()), trigger: "Synthetic")
        XCTAssertEqual(EmergencyReserveController.eligibility(status: low, incidentActive: false, stableSince: Date().addingTimeInterval(-3_000)), "Pending Safe Conditions")
    }

    private func temporaryHome() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerTests-\(UUID().uuidString)", isDirectory: true); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url }
    private func recoveryIncident(_ recovery: FilesystemEventRecovery?) -> StorageIncident { let measuredAt = Date(timeIntervalSince1970: 1_000); let status = DiskStatus(immediatelyFreeBytes: 9_000_000_000, availableForWorkBytes: 9_000_000_000, state: .fresh, measuredAt: measuredAt); return StorageIncident(trigger: .manual, before: RecorderCapacitySample(status: status, trigger: "test", now: measuredAt), filesystemEventRecovery: recovery) }
    private func reportTexts(_ incident: StorageIncident) throws -> (String, Data) { let home = try temporaryHome(); let urls = try StorageIncidentReportWriter.write(incident, store: IncidentStore(home: home.path)); return (try String(contentsOf: urls.first { $0.pathExtension == "md" }!), try Data(contentsOf: urls.first { $0.pathExtension == "json" }!)) }
    func testRecoveryReportCompleteMarkdown() throws { let r = FilesystemEventRecovery(outcome: .resumedCompletely, storedCheckpointEventID: 9, requestedResumeEventID: 9, watchedVolumeIdentity: "vol", eventsReplayed: 2, evidenceCompleteness: .complete); XCTAssertTrue(try reportTexts(recoveryIncident(r)).0.contains("## Filesystem event recovery")) }
    func testRecoveryReportGapMarkdown() throws { let r = FilesystemEventRecovery(outcome: .resumedWithBoundedGap, missingIntervalStart: Date(timeIntervalSince1970: 1), missingIntervalEnd: Date(timeIntervalSince1970: 2), evidenceCompleteness: .partial); let text = try reportTexts(recoveryIncident(r)).0; XCTAssertTrue(text.contains("Partial")); XCTAssertTrue(text.contains("Missing interval")) }
    func testRecoveryReportDroppedEventsMarkdown() throws { let r = FilesystemEventRecovery(outcome: .eventsDropped, userEventsDropped: true, kernelEventsDropped: true); XCTAssertTrue(try reportTexts(recoveryIncident(r)).0.contains("user true, kernel true")) }
    func testRecoveryReportStatesNoByteMeasurement() throws { XCTAssertTrue(try reportTexts(recoveryIncident(FilesystemEventRecovery())).0.contains("does not measure byte growth")) }
    func testRecoveryReportJSONContainsRecovery() throws { let data = try reportTexts(recoveryIncident(FilesystemEventRecovery())).1; XCTAssertNotNil(try JSONSerialization.jsonObject(with: data) as? [String: Any]); XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("filesystemEventRecovery")) }
    func testRecoveryReportLargeEventIDsRoundTrip() throws { let value: UInt64 = 9_007_199_254_740_991; let r = FilesystemEventRecovery(outcome: .resumedCompletely, storedCheckpointEventID: value, requestedResumeEventID: value); let data = try reportTexts(recoveryIncident(r)).1; let decoded = try JSONDecoder.withISO8601.decode(StorageIncident.self, from: data); XCTAssertEqual(decoded.filesystemEventRecovery?.storedCheckpointEventID, value) }
    func testOlderIncidentJSONDecodesWithoutRecovery() throws { let data = try JSONEncoder().encode(recoveryIncident(nil)); var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]; object.removeValue(forKey: "filesystemEventRecovery"); let legacy = try JSONSerialization.data(withJSONObject: object); XCTAssertNil(try JSONDecoder().decode(StorageIncident.self, from: legacy).filesystemEventRecovery) }
    func testRecoveryReportFailureStillWrites() throws { let r = FilesystemEventRecovery(outcome: .historyUnavailable, evidenceCompleteness: .partial); XCTAssertFalse(try reportTexts(recoveryIncident(r)).0.isEmpty) }
}

private final class RecoveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [String] = []
    private(set) var checkpoints: [FSEventsCheckpoint] = []
    var appendError: Error?
    var checkpointError: Error?

    func append(_ value: String) {
        lock.lock()
        calls.append(value)
        lock.unlock()
    }

    func record(_ checkpoint: FSEventsCheckpoint) throws {
        lock.lock()
        defer { lock.unlock() }
        calls.append("checkpoint")
        if let checkpointError { throw checkpointError }
        checkpoints.append(checkpoint)
    }

    func recordEvidence() throws {
        lock.lock()
        defer { lock.unlock() }
        calls.append("evidence")
        if let appendError { throw appendError }
    }
}

private final class StreamFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    var configurations: [FSEventsStreamConfiguration] = []
    var deliveries: [FSEventsStreamDelivery] = []
    var lifecycle: [String] = []
    var startResults: [Bool] = []
    var creationFails = false

    func make(_ configuration: FSEventsStreamConfiguration, delivery: @escaping FSEventsStreamDelivery) -> (any FSEventsStreamHandle)? {
        lock.lock()
        defer { lock.unlock() }
        lifecycle.append("create")
        configurations.append(configuration)
        deliveries.append(delivery)
        if creationFails { return nil }
        let result = startResults.isEmpty ? true : startResults.removeFirst()
        return FakeStreamHandle(probe: self, startResult: result)
    }

    func record(_ value: String) {
        lock.lock()
        lifecycle.append(value)
        lock.unlock()
    }

    func deliver(_ events: [FSEventEvidence], index: Int = 0) {
        lock.lock()
        let delivery = deliveries[index]
        lock.unlock()
        delivery(events)
    }
}

private final class ReplayLoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var evidenceWrites = 0
    private var checkpointWrites = 0

    func recordEvidence() {
        lock.lock()
        evidenceWrites += 1
        lock.unlock()
    }

    func recordCheckpoint() {
        lock.lock()
        checkpointWrites += 1
        lock.unlock()
    }

    var counts: (evidence: Int, checkpoints: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (evidenceWrites, checkpointWrites)
    }
}

private final class FakeStreamHandle: FSEventsStreamHandle, @unchecked Sendable {
    private let probe: StreamFactoryProbe
    private let startResult: Bool

    init(probe: StreamFactoryProbe, startResult: Bool) {
        self.probe = probe
        self.startResult = startResult
    }

    func start() -> Bool { probe.record("start"); return startResult }
    func stop() { probe.record("stop") }
    func invalidate() { probe.record("invalidate") }
    func release() { probe.record("release") }
}

#if !os(Linux)
@MainActor
#endif
final class FSEventsStreamFactoryTests: XCTestCase {
    private func home() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerStream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }

    private func status(_ volume: String = "volume-A") -> DiskStatus {
        DiskStatus(filesystem: volume, immediatelyFreeBytes: 20_000_000_000, availableForWorkBytes: 20_000_000_000, state: .fresh, measuredAt: Date(timeIntervalSince1970: 1_000))
    }

    private func dependencies(checkpoint: FSEventsCheckpoint, stream: StreamFactoryProbe) -> FSEventsRecoveryDependencies {
        FSEventsRecoveryDependencies(
            now: { Date(timeIntervalSince1970: 1_100) },
            currentVolumeIdentity: { $0.filesystem },
            loadCheckpoint: { _ in (checkpoint, false) },
            saveCheckpoint: { try $0.saveCheckpoint($1) },
            appendEvidence: { try $0.appendEvent($1) },
            preserveCorruptCheckpoint: { _, _ in true },
            makeStream: { stream.make($0, delivery: $1) }
        )
    }

    func testProductionRecorderPassesResumeRootsStartsOnceAndAvoidsCompetingStream() throws {
        let stream = StreamFactoryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 77, roots: ["/one", "/two"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try home().path), recoveryDependencies: dependencies(checkpoint: checkpoint, stream: stream))
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        XCTAssertEqual(stream.configurations.count, 1)
        XCTAssertEqual(stream.configurations.first?.startingEventID, 77)
        XCTAssertEqual(stream.configurations.first?.roots, ["/one", "/two"])
        XCTAssertEqual(stream.lifecycle.filter { $0 == "start" }.count, 1)
    }

    func testProductionRecorderStopsInvalidatesAndReleasesBeforeReplacement() throws {
        let stream = StreamFactoryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 77, roots: ["/one"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try home().path), recoveryDependencies: dependencies(checkpoint: checkpoint, stream: stream))
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        recorder.restartRecoveryStreamForTesting(from: 88, roots: ["/replacement"])
        XCTAssertEqual(stream.lifecycle, ["create", "start", "stop", "invalidate", "release", "create", "start"])
        XCTAssertEqual(stream.configurations.last?.startingEventID, 88)
    }

    func testInjectedReplayAndFlagsUseProductionAcceptancePath() async throws {
        let stream = StreamFactoryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/one"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try home().path), recoveryDependencies: dependencies(checkpoint: checkpoint, stream: stream))
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        #if os(macOS)
        let flags = [
            UInt32(kFSEventStreamEventFlagUserDropped),
            UInt32(kFSEventStreamEventFlagKernelDropped),
            UInt32(kFSEventStreamEventFlagRootChanged)
        ]
        #else
        let flags: [UInt32] = [0, 0, 0]
        #endif
        stream.deliver([
            FSEventEvidence(eventID: 11, path: "/one/a", flags: flags[0], volume: "volume-A", ancestor: "/one"),
            FSEventEvidence(eventID: 12, path: "/one/b", flags: flags[1], volume: "volume-A", ancestor: "/one"),
            FSEventEvidence(eventID: 13, path: "/one/c", flags: flags[2], volume: "volume-A", ancestor: "/one")
        ])
        let replayDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while recorder.lastEventID != 13, ContinuousClock.now < replayDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(recorder.lastEventID, 13)
        #if os(macOS)
        XCTAssertTrue(recorder.filesystemEventRecoveryState.userEventsDropped)
        XCTAssertTrue(recorder.filesystemEventRecoveryState.kernelEventsDropped)
        XCTAssertTrue(recorder.filesystemEventRecoveryState.rootChanged)
        XCTAssertEqual(recorder.filesystemEventRecoveryState.evidenceCompleteness, .partial)
        #else
        XCTAssertFalse(recorder.filesystemEventRecoveryState.userEventsDropped)
        XCTAssertFalse(recorder.filesystemEventRecoveryState.kernelEventsDropped)
        XCTAssertFalse(recorder.filesystemEventRecoveryState.rootChanged)
        XCTAssertEqual(recorder.filesystemEventRecoveryState.evidenceCompleteness, .complete)
        #endif
        stream.deliver([FSEventEvidence(eventID: 13, path: "/one/c", flags: 0, volume: "volume-A", ancestor: "/one")])
        let duplicateDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while recorder.filesystemEventRecoveryState.duplicatesSuppressed == 0, ContinuousClock.now < duplicateDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(recorder.filesystemEventRecoveryState.duplicatesSuppressed, 0)
    }

    func testCreationAndStartFailuresRemainOperationalAndRestartWorks() throws {
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/one"])
        let creation = StreamFactoryProbe()
        creation.creationFails = true
        let creationRecorder = StorageIncidentRecorder(store: IncidentStore(home: try home().path), recoveryDependencies: dependencies(checkpoint: checkpoint, stream: creation))
        creationRecorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        XCTAssertEqual(creationRecorder.status, .partialCoverage)
        XCTAssertTrue(creationRecorder.coverage.contains("creation failed"))

        let starting = StreamFactoryProbe()
        starting.startResults = [false, true]
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try home().path), recoveryDependencies: dependencies(checkpoint: checkpoint, stream: starting))
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        XCTAssertEqual(recorder.status, .partialCoverage)
        recorder.restartRecoveryStreamForTesting(from: 10, roots: checkpoint.roots)
        XCTAssertEqual(starting.lifecycle.suffix(2), ["create", "start"])
        XCTAssertTrue(recorder.coverage.contains("replay active"))
    }

    func testSleepWakeLifecycleAndVolumeChangeAvoidOldResumeID() throws {
        let stream = StreamFactoryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 55, roots: ["/one"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try home().path), recoveryDependencies: dependencies(checkpoint: checkpoint, stream: stream))
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)
        recorder.beforeSleep(status: status())
        XCTAssertEqual(stream.lifecycle.suffix(3), ["stop", "invalidate", "release"])
        recorder.afterWake(status: status("volume-B"))
        XCTAssertNotEqual(stream.configurations.last?.startingEventID, 55)
        XCTAssertEqual(recorder.lastEventID, 0)
    }

    func testStreamCallbacksCannotCreateCleanupAuthority() {
        XCTAssertNotEqual(String(describing: FSEventEvidence.self), String(describing: CleanupPlan.self))
        XCTAssertNotEqual(String(describing: FSEventsStreamHandle.self), String(describing: PreviewAuthorization.self))
    }

    func testTenThousandEventReplayYieldsMainActorAndBatchesPersistence() async throws {
        let stream = StreamFactoryProbe()
        let probe = ReplayLoadProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/one"])
        let dependencies = FSEventsRecoveryDependencies(
            now: { Date(timeIntervalSince1970: 1_100) },
            currentVolumeIdentity: { $0.filesystem },
            loadCheckpoint: { _ in (checkpoint, false) },
            saveCheckpoint: { _, _ in probe.recordCheckpoint() },
            appendEvidence: { _, _ in probe.recordEvidence() },
            preserveCorruptCheckpoint: { _, _ in true },
            makeStream: { stream.make($0, delivery: $1) }
        )
        let recorder = StorageIncidentRecorder(
            store: IncidentStore(home: try home().path),
            recoveryDependencies: dependencies
        )
        recorder.startRecovery(sample: status(), roots: checkpoint.roots, startStream: true)

        let events = (11...10_010).map {
            FSEventEvidence(eventID: UInt64($0), path: "/one/\($0)", flags: 0, volume: "volume-A", ancestor: "/one")
        }
        let heartbeat = expectation(description: "main actor heartbeat")
        let started = ContinuousClock.now
        stream.deliver(events)
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 30)
        let stall = started.duration(to: .now)

        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var maximumHeartbeatInterval = Duration.zero
        while recorder.lastEventID != 10_010, ContinuousClock.now < deadline {
            let heartbeatStarted = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(10))
            maximumHeartbeatInterval = max(maximumHeartbeatInterval, heartbeatStarted.duration(to: .now))
        }

        let counts = probe.counts
        XCTAssertLessThan(stall, .milliseconds(250), "FSEvents replay monopolized the main actor for \(stall).")
        XCTAssertLessThan(maximumHeartbeatInterval, .milliseconds(100), "A replay batch stalled the main actor for \(maximumHeartbeatInterval).")
        XCTAssertEqual(recorder.lastEventID, 10_010)
        XCTAssertEqual(counts.evidence, 10_000)
        XCTAssertLessThanOrEqual(counts.checkpoints, 100, "Checkpoint persistence must be bounded by 100-event replay batches.")
        XCTAssertLessThanOrEqual(recorder.replayPublicationCount, 5, "Observable replay publication must be substantially below event count.")
        XCTAssertLessThanOrEqual(
            recorder.operations.filter { $0.type == "FSEvents recovery" }.count,
            1,
            "Recovery Activity must be coalesced instead of inserting one entry per event."
        )
        print("DEXCLEANER_REPLAY_METRICS synthetic_events=10000 initial_main_actor_stall=\(stall) max_heartbeat_interval=\(maximumHeartbeatInterval) checkpoint_writes=\(counts.checkpoints) ui_publications=\(recorder.replayPublicationCount)")
    }

    func testCopiedSupportStateReplaysResponsivelyWhenFixtureIsProvided() async throws {
        guard let fixtureHome = ProcessInfo.processInfo.environment["DEXCLEANER_SUPPORT_FIXTURE_HOME"] else {
            throw XCTSkip("Set DEXCLEANER_SUPPORT_FIXTURE_HOME to the isolated copied support-state fixture.")
        }
        let source = URL(fileURLWithPath: fixtureHome, isDirectory: true)
        let copy = try home()
        try FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: source, to: copy)

        let store = IncidentStore(home: copy.path)
        let loaded = store.readCheckpoint()
        let checkpoint = try XCTUnwrap(loaded.0)
        XCTAssertFalse(loaded.1)
        XCTAssertFalse(checkpoint.cleanShutdown)
        XCTAssertEqual(store.load([DiagnosticOperation].self, named: "activity-v1.json", fallback: []).count, 100)

        let stream = StreamFactoryProbe()
        let probe = ReplayLoadProbe()
        let dependencies = FSEventsRecoveryDependencies(
            now: { Date(timeIntervalSince1970: 1_100) },
            currentVolumeIdentity: { _ in checkpoint.volumeID },
            loadCheckpoint: { _ in (checkpoint, false) },
            saveCheckpoint: { _, _ in probe.recordCheckpoint() },
            appendEvidence: { _, _ in probe.recordEvidence() },
            preserveCorruptCheckpoint: { _, _ in true },
            makeStream: { stream.make($0, delivery: $1) }
        )
        let recorder = StorageIncidentRecorder(store: store, recoveryDependencies: dependencies)
        recorder.startRecovery(
            sample: DiskStatus(filesystem: checkpoint.volumeID, immediatelyFreeBytes: 20_000_000_000, availableForWorkBytes: 20_000_000_000),
            roots: checkpoint.roots,
            startStream: true
        )

        let events = (1...10_000).map {
            FSEventEvidence(
                eventID: checkpoint.eventID + UInt64($0),
                path: checkpoint.roots[0] + "/fixture-\($0)",
                flags: 0,
                volume: checkpoint.volumeID,
                ancestor: checkpoint.roots[0]
            )
        }
        let heartbeat = expectation(description: "copied-state main actor heartbeat")
        let started = ContinuousClock.now
        stream.deliver(events)
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 30)
        let stall = started.duration(to: .now)

        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var maximumHeartbeatInterval = Duration.zero
        while recorder.lastEventID != events.last?.eventID, ContinuousClock.now < deadline {
            let heartbeatStarted = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(10))
            maximumHeartbeatInterval = max(maximumHeartbeatInterval, heartbeatStarted.duration(to: .now))
        }

        XCTAssertLessThan(stall, .milliseconds(250), "Copied valid support state caused a \(stall) main-actor stall.")
        XCTAssertLessThan(maximumHeartbeatInterval, .milliseconds(100), "Copied-state replay batch stalled the main actor for \(maximumHeartbeatInterval).")
        XCTAssertEqual(recorder.lastEventID, events.last?.eventID)
        XCTAssertLessThanOrEqual(probe.counts.checkpoints, 100)
        XCTAssertLessThanOrEqual(recorder.replayPublicationCount, 5)
        print("DEXCLEANER_REPLAY_METRICS copied_state_events=10000 initial_main_actor_stall=\(stall) max_heartbeat_interval=\(maximumHeartbeatInterval) checkpoint_writes=\(probe.counts.checkpoints) ui_publications=\(recorder.replayPublicationCount)")
    }
}

#if !os(Linux)
@MainActor
#endif
private struct ReplayResponsivenessHarness {
    let home: URL
    let recorder: StorageIncidentRecorder
    let stream: StreamFactoryProbe
    let probe: ReplayLoadProbe
    let checkpoint: FSEventsCheckpoint

    static func make(existingOperations: [DiagnosticOperation] = []) throws -> ReplayResponsivenessHarness {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerResponsive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = IncidentStore(home: home.path)
        if !existingOperations.isEmpty { try store.save(existingOperations, named: "activity-v1.json") }
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/one"])
        let stream = StreamFactoryProbe()
        let probe = ReplayLoadProbe()
        let dependencies = FSEventsRecoveryDependencies(
            now: { Date(timeIntervalSince1970: 1_100) },
            currentVolumeIdentity: { $0.filesystem },
            loadCheckpoint: { _ in (checkpoint, false) },
            saveCheckpoint: { _, _ in probe.recordCheckpoint() },
            appendEvidence: { _, _ in probe.recordEvidence() },
            preserveCorruptCheckpoint: { _, _ in true },
            makeStream: { stream.make($0, delivery: $1) }
        )
        let recorder = StorageIncidentRecorder(store: store, recoveryDependencies: dependencies)
        recorder.startRecovery(
            sample: DiskStatus(filesystem: "volume-A", immediatelyFreeBytes: 20_000_000_000, availableForWorkBytes: 20_000_000_000),
            roots: checkpoint.roots,
            startStream: true
        )
        return ReplayResponsivenessHarness(home: home, recorder: recorder, stream: stream, probe: probe, checkpoint: checkpoint)
    }

    func events(count: Int, duplicate: Bool = false) -> [FSEventEvidence] {
        (1...count).map {
            FSEventEvidence(
                eventID: duplicate ? checkpoint.eventID : checkpoint.eventID + UInt64($0),
                path: "/one/\($0)",
                flags: 0,
                volume: checkpoint.volumeID,
                ancestor: "/one"
            )
        }
    }

    func waitForReplay(eventID: UInt64, timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while recorder.lastEventID != eventID, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

#if !os(Linux)
@MainActor
#endif
final class HangReproductionTests: XCTestCase {
    func testCopiedFixtureCarriesTheValidHeavyStateThatTriggeredTheHang() throws {
        guard let fixtureHome = ProcessInfo.processInfo.environment["DEXCLEANER_SUPPORT_FIXTURE_HOME"] else {
            throw XCTSkip("Set DEXCLEANER_SUPPORT_FIXTURE_HOME to the isolated copied support-state fixture.")
        }
        let store = IncidentStore(home: fixtureHome)
        let checkpoint = try XCTUnwrap(store.readCheckpoint().0)
        let activity = store.load([DiagnosticOperation].self, named: "activity-v1.json", fallback: [])
        let events = store.directory.appendingPathComponent("events-v1.jsonl")
        let size = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: events.path)[.size] as? NSNumber)?.int64Value)
        XCTAssertFalse(checkpoint.cleanShutdown)
        XCTAssertEqual(activity.count, 100)
        XCTAssertGreaterThan(size, 40_000_000)
    }
}

#if !os(Linux)
@MainActor
#endif
final class MainThreadResponsivenessTests: XCTestCase {
    func testRecorderCallbackReturnsToMainActorWithin250Milliseconds() async throws {
        let harness = try ReplayResponsivenessHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.home) }
        let heartbeat = expectation(description: "main actor")
        let started = ContinuousClock.now
        harness.stream.deliver(harness.events(count: 10_000))
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 2)
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(250))
        try await harness.waitForReplay(eventID: 10_010)
        XCTAssertLessThanOrEqual(harness.recorder.replayPublicationCount, 5)
    }
}

#if !os(Linux)
@MainActor
#endif
final class MenuBarResponsivenessTests: XCTestCase {
    func testMenuCommandHeartbeatIsServicedWithinOneSecondDuringReplay() async throws {
        let harness = try ReplayResponsivenessHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.home) }
        let serviced = expectation(description: "menu command")
        let started = ContinuousClock.now
        harness.stream.deliver(harness.events(count: 10_000))
        Task { @MainActor in serviced.fulfill() }
        await fulfillment(of: [serviced], timeout: 2)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        try await harness.waitForReplay(eventID: 10_010)
    }
}

#if !os(Linux)
@MainActor
#endif
final class WindowResponsivenessTests: XCTestCase {
    func testWindowAndQuitCommandHeartbeatsRemainServiceableDuringReplay() async throws {
        let harness = try ReplayResponsivenessHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.home) }
        let window = expectation(description: "window command")
        let quit = expectation(description: "quit command")
        let started = ContinuousClock.now
        harness.stream.deliver(harness.events(count: 10_000))
        Task { @MainActor in window.fulfill(); quit.fulfill() }
        await fulfillment(of: [window, quit], timeout: 2)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        try await harness.waitForReplay(eventID: 10_010)
    }
}

#if !os(Linux)
@MainActor
#endif
final class FSEventsReplayStressTests: XCTestCase {
    func testDuplicateHeavyReplayIsBoundedWithoutCheckpointAmplification() async throws {
        let harness = try ReplayResponsivenessHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.home) }
        harness.stream.deliver(harness.events(count: 10_000, duplicate: true))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while harness.recorder.filesystemEventRecoveryState.duplicatesSuppressed != 10_000,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(harness.recorder.filesystemEventRecoveryState.duplicatesSuppressed, 10_000)
        XCTAssertEqual(harness.probe.counts.checkpoints, 0)
        XCTAssertLessThanOrEqual(harness.recorder.replayPublicationCount, 5)
    }
}

#if !os(Linux)
@MainActor
#endif
final class ActivityCenterCoalescingTests: XCTestCase {
    func testReplayUpdatesOneSessionEntryWithoutDisplacingExistingHistory() async throws {
        let existing = (0..<99).map {
            DiagnosticOperation(
                type: "Historical \($0)", phase: "Complete", state: .complete,
                startedAt: Date(timeIntervalSince1970: TimeInterval($0)), endedAt: Date(timeIntervalSince1970: TimeInterval($0)),
                processed: 1, total: 1, bytes: 0, summary: "Retained", reportPath: nil
            )
        }
        let harness = try ReplayResponsivenessHarness.make(existingOperations: existing)
        defer { try? FileManager.default.removeItem(at: harness.home) }
        harness.stream.deliver(harness.events(count: 10_000))
        try await harness.waitForReplay(eventID: 10_010)
        XCTAssertEqual(harness.recorder.operations.filter { $0.type == "FSEvents recovery" }.count, 1)
        XCTAssertEqual(harness.recorder.operations.filter { $0.type.hasPrefix("Historical") }.count, 99)
        XCTAssertEqual(harness.recorder.operations.first?.processed, 10_000)
    }
}

#if !os(Linux)
@MainActor
#endif
final class SupportStateCompatibilityTests: XCTestCase {
    func testEmptyAndMalformedActivityStateLoadWithoutBlockingRecovery() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerSupportCompatibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = IncidentStore(home: home.path)
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{malformed".utf8).write(to: store.directory.appendingPathComponent("activity-v1.json"), options: .atomic)
        let recorder = StorageIncidentRecorder(store: store)
        XCTAssertTrue(recorder.operations.isEmpty)
        XCTAssertTrue(recorder.incidents.isEmpty)
    }
}

#if !os(Linux)
@MainActor
#endif
final class FSEventsRecoveryTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func status(volume: String = "volume-A") -> DiskStatus {
        DiskStatus(filesystem: volume, immediatelyFreeBytes: 20_000_000_000, availableForWorkBytes: 21_000_000_000, state: .fresh, measuredAt: Date(timeIntervalSince1970: 500))
    }

    private func dependencies(checkpoint: FSEventsCheckpoint?, corrupt: Bool = false, replayAvailable: Bool = true, probe: RecoveryProbe, now: Date = Date(timeIntervalSince1970: 1_000)) -> FSEventsRecoveryDependencies {
        FSEventsRecoveryDependencies(
            now: { now },
            currentVolumeIdentity: { $0.filesystem },
            loadCheckpoint: { _ in (checkpoint, corrupt) },
            saveCheckpoint: { _, value in try probe.record(value) },
            appendEvidence: { _, _ in try probe.recordEvidence() },
            preserveCorruptCheckpoint: { _, _ in probe.append("preserve"); return true },
            replayAvailable: { _ in replayAvailable }
        )
    }

    func testFSEventsRecoveryCleanResumeUsesInjectedClockVolumeAndRoots() throws {
        let probe = RecoveryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 40, eventTimestamp: Date(timeIntervalSince1970: 900), roots: ["/watched"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try temporaryHome().path), recoveryDependencies: dependencies(checkpoint: checkpoint, probe: probe))
        recorder.startRecovery(sample: status(), roots: ["/watched"])
        XCTAssertEqual(recorder.lastEventID, 40)
        XCTAssertEqual(recorder.status, .recording)
        XCTAssertTrue(recorder.coverage.contains("40"))
        XCTAssertEqual(recorder.operations.first?.state, .complete)
    }

    func testFSEventsRecoveryVolumeRootHistoryInvalidAndCorruptOutcomesRequireBaseline() throws {
        let home = try temporaryHome()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 40, roots: ["/old"])
        for (volume, roots, available, expected) in [
            ("volume-B", ["/old"], true, "Volume changed"),
            ("volume-A", ["/new"], true, "Root changed"),
            ("volume-A", ["/old"], false, "History unavailable")
        ] {
            let probe = RecoveryProbe()
            let recorder = StorageIncidentRecorder(store: IncidentStore(home: home.path), recoveryDependencies: dependencies(checkpoint: checkpoint, replayAvailable: available, probe: probe))
            recorder.startRecovery(sample: status(volume: volume), roots: roots)
            XCTAssertEqual(recorder.lastEventID, 0)
            XCTAssertTrue(recorder.coverage.contains(expected))
            XCTAssertEqual(recorder.status, .partialCoverage)
        }
        let corruptProbe = RecoveryProbe()
        let corruptRecorder = StorageIncidentRecorder(store: IncidentStore(home: home.path), recoveryDependencies: dependencies(checkpoint: nil, corrupt: true, probe: corruptProbe))
        corruptRecorder.startRecovery(sample: status(), roots: ["/old"])
        XCTAssertEqual(corruptProbe.calls.first, "preserve")
        XCTAssertTrue(corruptRecorder.coverage.contains("Corrupt checkpoint preserved"))
    }

    func testFSEventsRecoveryPersistsEvidenceBeforeCheckpointAndSuppressesReplay() throws {
        let probe = RecoveryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/watched"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try temporaryHome().path), recoveryDependencies: dependencies(checkpoint: checkpoint, probe: probe))
        recorder.startRecovery(sample: status(), roots: ["/watched"])
        let event = FSEventEvidence(eventID: 11, timestamp: Date(timeIntervalSince1970: 1_001), path: "/watched/a", flags: 0, volume: "volume-A", ancestor: "/watched")
        recorder.acceptRecoveryEvent(event)
        XCTAssertEqual(Array(probe.calls.suffix(2)), ["evidence", "checkpoint"])
        XCTAssertEqual(recorder.lastEventID, 11)
        recorder.acceptRecoveryEvent(event)
        XCTAssertEqual(recorder.lastEventID, 11)
        XCTAssertTrue(recorder.coverage.contains("duplicates suppressed"))
    }

    func testFSEventsRecoveryEvidenceAndCheckpointFailuresNeverAdvanceMemory() throws {
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/watched"])
        let event = FSEventEvidence(eventID: 11, path: "/watched/a", flags: 0, volume: "volume-A", ancestor: "/watched")

        let evidenceProbe = RecoveryProbe()
        evidenceProbe.appendError = CocoaError(.fileWriteUnknown)
        let evidenceRecorder = StorageIncidentRecorder(store: IncidentStore(home: try temporaryHome().path), recoveryDependencies: dependencies(checkpoint: checkpoint, probe: evidenceProbe))
        evidenceRecorder.startRecovery(sample: status(), roots: ["/watched"])
        evidenceRecorder.acceptRecoveryEvent(event)
        XCTAssertEqual(evidenceRecorder.lastEventID, 10)
        XCTAssertEqual(evidenceProbe.calls, ["evidence"])
        XCTAssertEqual(evidenceRecorder.operations.first?.state, .failed)

        let checkpointProbe = RecoveryProbe()
        checkpointProbe.checkpointError = CocoaError(.fileWriteUnknown)
        let checkpointRecorder = StorageIncidentRecorder(store: IncidentStore(home: try temporaryHome().path), recoveryDependencies: dependencies(checkpoint: checkpoint, probe: checkpointProbe))
        checkpointRecorder.startRecovery(sample: status(), roots: ["/watched"])
        checkpointRecorder.acceptRecoveryEvent(event)
        XCTAssertEqual(checkpointRecorder.lastEventID, 10)
        XCTAssertEqual(checkpointProbe.calls, ["evidence", "checkpoint"])
    }

    func testFSEventsRecoverySleepAndWakeUseInjectedPersistenceAndExposeMissingInterval() throws {
        let probe = RecoveryProbe()
        let checkpoint = FSEventsCheckpoint(volumeID: "volume-A", deviceID: "volume-A", eventID: 10, roots: ["/watched"])
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: try temporaryHome().path), recoveryDependencies: dependencies(checkpoint: checkpoint, probe: probe))
        recorder.startRecovery(sample: status(), roots: ["/watched"])
        recorder.beforeSleep(status: status())
        XCTAssertTrue(probe.calls.contains("checkpoint"))
        recorder.afterWake(status: status(volume: "volume-B"))
        XCTAssertEqual(recorder.status, .partialCoverage)
        XCTAssertTrue(recorder.coverage.contains("volume changed"))
    }
}

final class RepeatedPatternTests: XCTestCase {
    private func incident(index: Int, path: String? = nil, category: DiagnosticClassification = .unresolved, trigger: String = "Synthetic", wake: String = "Active", complete: EvidenceCompleteness = .complete) -> StorageIncident {
        let date = Date(timeIntervalSince1970: TimeInterval(10_000 + index * 3_600))
        let before = RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: 20_000, availableForWorkBytes: 20_000, state: .fresh, measuredAt: date), trigger: trigger, wakeState: wake, now: date)
        var value = StorageIncident(startedAt: date, trigger: .manual, before: before, completeness: complete)
        value.after = RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: Int64(19_000 - index * 100), availableForWorkBytes: 20_000, state: .fresh, measuredAt: date.addingTimeInterval(60)), trigger: "after", now: date.addingTimeInterval(60))
        if let path { value.measurements = [PathMeasurement(path: path, classification: category, allocatedBytes: 1_000)] }
        return value
    }

    private func withLoss(_ incident: StorageIncident, _ loss: Int64) -> StorageIncident {
        var value = incident
        let free = value.before.immediatelyFreeBytes ?? 20_000
        let date = value.startedAt.addingTimeInterval(60)
        value.after = RecorderCapacitySample(
            status: DiskStatus(immediatelyFreeBytes: free - loss, availableForWorkBytes: free - loss, state: .fresh, measuredAt: date),
            trigger: "after",
            now: date
        )
        return value
    }

    func testRepeatedPatternClassifiesPathBuildWakeLaunchAndInsufficientHistory() {
        let path = (0..<4).map { incident(index: $0, path: "/tmp/Project/.build/\($0)", category: .buildOutput) }
        XCTAssertEqual(RepeatedPatternClassifier.classify(path).kind, .repeatedBuildOutput)
        XCTAssertEqual(RepeatedPatternClassifier.classify(path).confidence, PatternConfidence.strong.rawValue)
        let wake = (0..<3).map { incident(index: $0, wake: "Woke") }
        XCTAssertEqual(RepeatedPatternClassifier.classify(wake).kind, .repeatedAfterWake)
        let launch = (0..<3).map { incident(index: $0, trigger: "Application launch") }
        XCTAssertEqual(RepeatedPatternClassifier.classify(launch).kind, .repeatedAfterLaunch)
        XCTAssertEqual(RepeatedPatternClassifier.classify([incident(index: 0)]).kind, .insufficientHistory)
    }

    func testRepeatedPatternClassifiesOwnerScheduleProviderSwapAndConflict() {
        var owner = (0..<3).map { incident(index: $0) }
        for index in owner.indices {
            owner[index].processes = [ProcessEvidence(name: "Builder", executable: "/bin/builder", bundleID: "test.builder", path: nil, confidence: .possibleContributor, detail: "Synthetic")]
        }
        XCTAssertEqual(RepeatedPatternClassifier.classify(owner).kind, .repeatedApplicationGrowth)
        var scheduled = (0..<3).map { incident(index: $0) }
        for index in scheduled.indices {
            scheduled[index].tasks = [ScheduledTaskEvidence(label: "test.task", program: "/bin/true", schedule: "Hourly", path: "/tmp/task.plist", confidence: .possibleContributor, detail: "Synthetic")]
        }
        XCTAssertEqual(RepeatedPatternClassifier.classify(scheduled).kind, .repeatedScheduledOverlap)
        var provider = (0..<3).map { incident(index: $0) }
        for index in provider.indices {
            provider[index].cloud = [CloudProviderEvidence(provider: "SyntheticCloud", accountLabel: nil, domainIdentifier: nil, root: "/tmp/cloud", state: "Downloaded", logicalBytes: 1, allocatedUserBytes: 1, placeholderBytes: 0, downloadedBytes: 1, pinnedBytes: 0, cacheBytes: 0, databaseBytes: 0, completeness: .complete, safeAction: "Reveal")]
        }
        XCTAssertEqual(RepeatedPatternClassifier.classify(provider).kind, .repeatedProviderGrowth)
        var swap = (0..<3).map { incident(index: $0) }
        for index in swap.indices { swap[index].system.swapBytes = 1_000 }
        XCTAssertEqual(RepeatedPatternClassifier.classify(swap).kind, .repeatedSwapOnly)
        let conflict = (0..<3).map { incident(index: $0, complete: .partial) }
        XCTAssertEqual(RepeatedPatternClassifier.classify(conflict).kind, .conflicting)
    }

    func testRepeatedPatternPersistsAndReportsWithoutCleanupAuthority() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerPattern-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let history = (0..<3).map { incident(index: $0, path: "/tmp/cache") }
        var latest = history[0]
        latest.repeatedPatterns = [RepeatedPatternClassifier.classify(history)]
        let urls = try StorageIncidentReportWriter.write(latest, store: IncidentStore(home: home.path))
        let markdown = try String(contentsOf: urls.first { $0.pathExtension == "md" }!)
        let json = try String(contentsOf: urls.first { $0.pathExtension == "json" }!)
        XCTAssertTrue(markdown.contains("## Repeated patterns"))
        XCTAssertTrue(json.contains("repeatedPatterns"))
        XCTAssertTrue(markdown.contains("not authorized for cleanup"))
    }

    func testRepeatedPatternReducedPreservesRetentionAndChangingChildren() {
        var history = [
            withLoss(incident(index: 0, path: "/tmp/Owner/cache/session/one"), 4_000),
            withLoss(incident(index: 1, path: "/tmp/Owner/cache/session/two"), 1_800),
            withLoss(incident(index: 2, path: "/tmp/Owner/cache/session/three"), 1_500)
        ]
        history[1].retentionControlState = "Keep last 7 days installed"
        let result = RepeatedPatternClassifier.classify(history)
        XCTAssertEqual(result.kind, .recurrenceReduced)
        XCTAssertEqual(result.trend, "Decreasing")
        XCTAssertEqual(result.retentionControl, "Keep last 7 days installed")
        XCTAssertEqual(result.occurrences, 3)
    }

    func testRepeatedPatternStoppedAfterSufficientQuietInterval() {
        var history = (0..<3).map { incident(index: $0, path: "/tmp/Owner/cache/session/\($0)") }
        var quiet = incident(index: 3, path: "/tmp/Unrelated/item")
        quiet.startedAt = history[2].startedAt.addingTimeInterval(8 * 86_400)
        history.append(quiet)
        let result = RepeatedPatternClassifier.classify(history, now: quiet.startedAt)
        XCTAssertEqual(result.kind, .recurrenceStopped)
        XCTAssertTrue(result.supporting.joined().contains("seven-day"))
    }

    func testRepeatedPatternCoincidenceConflictAndDeterministicRanking() {
        let coincidence = (0..<4).map { incident(index: $0) }
        XCTAssertEqual(RepeatedPatternClassifier.classify(coincidence).kind, .none)

        var ranked = (0..<4).map { incident(index: $0) }
        for index in ranked.indices {
            ranked[index].measurements = [
                PathMeasurement(path: "/tmp/B/cache/session/\(index)"),
                PathMeasurement(path: "/tmp/A/cache/session/\(index)")
            ]
        }
        XCTAssertTrue(RepeatedPatternClassifier.classify(ranked).normalizedPath?.contains("/A") == true)

        var contradictory = ranked
        contradictory[0].completeness = .failed
        XCTAssertEqual(RepeatedPatternClassifier.classify(contradictory).evidenceCompleteness, .partial)
    }
}

final class LocalCloudComparisonTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerCompare-\(UUID().uuidString)")
        let local = root.appendingPathComponent("Local")
        let cloud = root.appendingPathComponent("Cloud")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        return (root, local, cloud)
    }

    func testLocalCloudComparisonNamesMetadataHashesAndMirrorMode() throws {
        let (root, local, cloud) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic").classification, .nameOnly)
        let date = Date(timeIntervalSince1970: 2_000)
        for name in ["a", "b", "c"] {
            let left = local.appendingPathComponent(name)
            let right = cloud.appendingPathComponent(name)
            try Data("same-\(name)".utf8).write(to: left)
            try Data("same-\(name)".utf8).write(to: right)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: left.path)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: right.path)
        }
        let strong = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic")
        XCTAssertEqual(strong.classification, .strong)
        XCTAssertEqual(strong.hashesMatched, 3)
        XCTAssertGreaterThan(strong.hashBytesRead, 0)
        let mirror = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic", providerMode: .mirrored)
        XCTAssertEqual(mirror.classification, .intentionallyMirrored)
    }

    func testLocalCloudComparisonRefusesSymlinksLowSpaceCancellationAndBounds() throws {
        let (root, local, cloud) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("a".utf8).write(to: local.appendingPathComponent("a"))
        try Data("a".utf8).write(to: cloud.appendingPathComponent("a"))
        try FileManager.default.createSymbolicLink(atPath: local.appendingPathComponent("escape").path, withDestinationPath: "/tmp")
        let symlink = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic")
        XCTAssertEqual(symlink.symlinksSkipped, 1)
        let low = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic", lowSpace: true)
        XCTAssertEqual(low.coverage, .unavailable)
        XCTAssertEqual(low.hashBytesRead, 0)
        let cancelled = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic", isCancelled: { true })
        XCTAssertEqual(cancelled.coverage, .cancelled)
        let limited = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic", limits: LocalCloudComparisonLimits(maximumFiles: 1, maximumHashBytes: 1, maximumDuration: 60, maximumDifferences: 1))
        XCTAssertFalse(limited.limitsReached.isEmpty)
        XCTAssertLessThanOrEqual(limited.filesSampled, 1)
    }

    func testLocalCloudComparisonGitCheckoutsNeverBecomeDuplicatesAndDispositionIsPassive() throws {
        let (root, local, cloud) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: local.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloud.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let result = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic")
        XCTAssertEqual(result.classification, .separateCheckout)
        var passive = result
        passive.disposition = .intentionallySeparate
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.appendingPathComponent(".git").path))
        XCTAssertEqual(passive.disposition, .intentionallySeparate)
    }

    func testComparatorInjectedStableIdentifiersStrengthenWithoutHashing() throws {
        let (root, local, cloud) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a", "b", "c"] {
            try Data(name.utf8).write(to: local.appendingPathComponent(name))
            try Data(name.utf8).write(to: cloud.appendingPathComponent(name))
        }
        let dependencies = LocalCloudComparisonDependencies(
            metadata: { url in
                guard var value = LocalCloudComparator.liveMetadata(for: url) else { return nil }
                if value.isRegularFile { value.stableIdentifier = "stable-\(url.lastPathComponent)" }
                return value
            },
            readResidentData: { _ in XCTFail("Stable identifier comparison must not require hashing"); return nil }
        )
        let limits = LocalCloudComparisonLimits(hashResidentFiles: false)
        let result = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic", limits: limits, dependencies: dependencies)
        XCTAssertEqual(result.classification, .strong)
        XCTAssertEqual(result.stableIdentifiersMatched, 3)
        XCTAssertEqual(result.hashBytesRead, 0)
    }

    func testComparatorInjectedPlaceholderDatalessBoundaryAndIdentifierDisagreementAreRefused() throws {
        let (root, local, cloud) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["placeholder", "dataless", "boundary", "ordinary"] {
            try Data(name.utf8).write(to: local.appendingPathComponent(name))
            try Data(name.utf8).write(to: cloud.appendingPathComponent(name))
        }
        let readProbe = RecoveryProbe()
        let dependencies = LocalCloudComparisonDependencies(
            metadata: { url in
                guard var value = LocalCloudComparator.liveMetadata(for: url) else { return nil }
                value.filesystemIdentity = url.lastPathComponent == "boundary" ? "other-volume" : "root-volume"
                if url.lastPathComponent == "placeholder" { value.placeholder = true }
                if url.lastPathComponent == "dataless" { value.dataless = true }
                if url.lastPathComponent == "ordinary", value.isRegularFile {
                    value.stableIdentifier = url.path.contains("/Local/") ? "left" : "right"
                }
                return value
            },
            readResidentData: { url in readProbe.append(url.lastPathComponent); return try? Data(contentsOf: url) }
        )
        let result = LocalCloudComparator.compare(local: local, cloud: cloud, provider: "Synthetic", dependencies: dependencies)
        XCTAssertEqual(result.placeholdersSkipped, 2)
        XCTAssertEqual(result.datalessFilesSkipped, 2)
        XCTAssertEqual(result.filesystemBoundariesRefused, 2)
        XCTAssertEqual(result.stableIdentifiersMatched, 0)
        XCTAssertFalse(readProbe.calls.contains("placeholder"))
        XCTAssertFalse(readProbe.calls.contains("dataless"))
        XCTAssertFalse(readProbe.calls.contains("boundary"))
    }
}

final class EmergencyReserveTests: XCTestCase {
    private func home() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerReserve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testEmergencyReserveCreatesPhysicalExactFileAndReleasesToWaiting() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try EmergencyReserveController.create(injectedHome: root, freeBytes: 20_000_000_000, stable: true, incidentActive: false, target: 65_536, chunkBytes: 4_096)
        let reserve = root.appendingPathComponent(EmergencyReserveController.relativePath)
        XCTAssertEqual(created.state, .ready)
        XCTAssertGreaterThanOrEqual(created.allocatedBytes, 65_536)
        XCTAssertTrue(EmergencyReserveController.isOnlyAllowedPath(reserve, home: root.path))
        let released = try EmergencyReserveController.release(injectedHome: root)
        XCTAssertEqual(released.state, .waiting)
        XCTAssertGreaterThan(released.releasedBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reserve.path))
    }

    func testEmergencyReserveRefusesUnsafeConditionsAndAnotherPath() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try EmergencyReserveController.create(injectedHome: root, freeBytes: 2_000_000_000, stable: true, incidentActive: false, target: 4_096).state, .pending)
        XCTAssertEqual(try EmergencyReserveController.create(injectedHome: root, freeBytes: 20_000_000_000, stable: false, incidentActive: false, target: 4_096).state, .pending)
        XCTAssertEqual(try EmergencyReserveController.create(injectedHome: root, freeBytes: 20_000_000_000, stable: true, incidentActive: true, target: 4_096).state, .pending)
        XCTAssertEqual(try EmergencyReserveController.create(injectedHome: root, freeBytes: 20_000_000_000, stable: true, incidentActive: false, activeOperation: true, target: 4_096).state, .pending)
        XCTAssertFalse(EmergencyReserveController.isOnlyAllowedPath(root.appendingPathComponent("Documents/reserve.bin"), home: root.path))
    }

    func testEmergencyReserveReleaseRejectsSymlinkAndNonDexCleanerOwnership() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let reserve = root.appendingPathComponent(EmergencyReserveController.relativePath)
        try FileManager.default.createDirectory(at: reserve.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: reserve, withDestinationURL: root.appendingPathComponent("outside"))
        let result = try EmergencyReserveController.release(injectedHome: root)
        XCTAssertEqual(result.state, .failed)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: reserve.path))
    }

    func testEmergencyReserveCancellationRemovesTemporaryAndNeverFinalizes() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(
            try EmergencyReserveController.create(
                injectedHome: root,
                freeBytes: 20_000_000_000,
                stable: true,
                incidentActive: false,
                target: 65_536,
                chunkBytes: 4_096,
                isCancelled: { true }
            )
        ) { XCTAssertTrue($0 is CancellationError) }
        let probe = RecoveryProbe()
        XCTAssertThrowsError(
            try EmergencyReserveController.create(
                injectedHome: root,
                freeBytes: 20_000_000_000,
                stable: true,
                incidentActive: false,
                target: 65_536,
                chunkBytes: 4_096,
                isCancelled: {
                    probe.append("poll")
                    return probe.calls.count >= 4
                }
            )
        ) { XCTAssertTrue($0 is CancellationError) }
        let directory = root.appendingPathComponent(EmergencyReserveController.relativePath).deletingLastPathComponent()
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertFalse(leftovers.contains("reserve.bin"))
        XCTAssertFalse(leftovers.contains { $0.hasSuffix(".tmp") })
    }

    func testEmergencyReserveReleaseUsesRemeasurementAndMarksUnavailableMeasurementPartial() throws {
        let measuredRoot = try home()
        defer { try? FileManager.default.removeItem(at: measuredRoot) }
        _ = try EmergencyReserveController.create(injectedHome: measuredRoot, freeBytes: 20_000_000_000, stable: true, incidentActive: false, target: 16_384, chunkBytes: 4_096)
        let measured = try EmergencyReserveController.release(injectedHome: measuredRoot, measuredFreeBefore: 100_000, measuredFreeAfter: { 112_345 })
        XCTAssertEqual(measured.releasedBytes, 12_345)
        XCTAssertEqual(measured.measurementCompleteness, .complete)

        let partialRoot = try home()
        defer { try? FileManager.default.removeItem(at: partialRoot) }
        _ = try EmergencyReserveController.create(injectedHome: partialRoot, freeBytes: 20_000_000_000, stable: true, incidentActive: false, target: 16_384, chunkBytes: 4_096)
        let partial = try EmergencyReserveController.release(injectedHome: partialRoot, measuredFreeBefore: 100_000, measuredFreeAfter: { nil })
        XCTAssertEqual(partial.measurementCompleteness, .partial)
        XCTAssertNotNil(partial.failureReason)
        XCTAssertGreaterThan(partial.releasedBytes, 0)
    }

    func testEmergencyReserveRefusesNonRegularFinalPath() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let reserve = root.appendingPathComponent(EmergencyReserveController.relativePath)
        _ = try EmergencyReserveController.create(injectedHome: root, freeBytes: 20_000_000_000, stable: true, incidentActive: false, target: 4_096, chunkBytes: 4_096)
        try FileManager.default.removeItem(at: reserve)
        try FileManager.default.createDirectory(at: reserve, withIntermediateDirectories: true)
        let result = try EmergencyReserveController.release(injectedHome: root)
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reserve.path))
    }

    func testEmergencyReserveRejectsInvalidOwnershipRecord() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try EmergencyReserveController.create(injectedHome: root, freeBytes: 20_000_000_000, stable: true, incidentActive: false, target: 4_096, chunkBytes: 4_096)
        let state = root
            .appendingPathComponent(EmergencyReserveController.relativePath)
            .deletingLastPathComponent()
            .appendingPathComponent("reserve-state-v1.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
        object["owner"] = "Another application"
        try JSONSerialization.data(withJSONObject: object).write(to: state, options: .atomic)
        let result = try EmergencyReserveController.release(injectedHome: root)
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(EmergencyReserveController.relativePath).path))
    }
}

#if !os(Linux)
@MainActor
#endif
final class DiagnosticCancellationTests: XCTestCase {
    private func home() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerCancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testCancellationStateIsIdempotentAndCompletionIsRetained() throws {
        let root = try home()
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: root.path))
        let operation = recorder.beginDiagnosticOperation(type: "Local/cloud comparison", phase: "Hashing", total: 10)
        recorder.requestCancellation()
        recorder.requestCancellation()
        XCTAssertEqual(recorder.operations.first?.state, .cancelling)
        recorder.finishDiagnosticOperation(operation, state: .cancelled, summary: "Partial evidence retained; no cleanup authority.")
        recorder.requestCancellation()
        XCTAssertEqual(recorder.operations.first?.state, .cancelled)
        XCTAssertTrue(recorder.operations.first?.summary.contains("no cleanup authority") == true)
    }

    func testFocusedInvestigationCancellationRetainsMeasuredEvidenceAndActivity() throws {
        let root = try home()
        let measuredA = root.appendingPathComponent("A")
        let measuredB = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: measuredA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: measuredB, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: measuredA.appendingPathComponent("item"))
        let dependencies = FSEventsRecoveryDependencies(
            now: { Date(timeIntervalSince1970: 1_000) },
            currentVolumeIdentity: { $0.filesystem },
            loadCheckpoint: { _ in (nil, false) },
            saveCheckpoint: { _, _ in },
            appendEvidence: { _, _ in },
            preserveCorruptCheckpoint: { _, _ in true },
            systemSnapshot: { SystemAccounting() }
        )
        let recorder = StorageIncidentRecorder(store: IncidentStore(home: root.path), recoveryDependencies: dependencies)
        let status = DiskStatus(immediatelyFreeBytes: 20_000, availableForWorkBytes: 20_000, state: .fresh, measuredAt: Date(timeIntervalSince1970: 1_000))
        recorder.investigateNow(status: status)
        let probe = RecoveryProbe()
        recorder.investigateChangedRoots([measuredA.path, measuredB.path], isCancelled: {
            probe.append("poll")
            return probe.calls.count >= 2
        })
        XCTAssertEqual(recorder.activeIncident?.measurements.count, 1)
        XCTAssertEqual(recorder.activeIncident?.completeness, .partial)
        XCTAssertEqual(recorder.operations.first?.state, .cancelled)
        XCTAssertTrue(recorder.operations.first?.summary.contains("retained") == true)
    }
}

final class DeepTraceTests: XCTestCase {
    func testDeepTraceAuthorizationDenialTimeoutCancellationFilteringAndRedaction() {
        XCTAssertEqual(DeepTraceController.synthetic(lines: [], authorized: false).state, .requiresAuthorization)
        XCTAssertEqual(DeepTraceController.synthetic(lines: [], authorized: false, denied: true).state, .authorizationDenied)
        let lines = [
            "writer WRITE path=/incident/file --token abc",
            "noise READ path=/incident/file",
            "other WRITE path=/unrelated/file"
        ]
        let result = DeepTraceController.synthetic(lines: lines, authorized: true, timeout: 70, incidentPaths: ["/incident"])
        XCTAssertEqual(result.state, .partial)
        XCTAssertEqual(result.duration, 60)
        XCTAssertEqual(result.relevantOperations, 1)
        XCTAssertTrue(result.redacted)
        XCTAssertFalse(result.summary.contains("abc"))
        let cancelled = DeepTraceController.synthetic(lines: lines, authorized: true, cancelled: true)
        XCTAssertEqual(cancelled.coverage, .cancelled)
    }

    func testDeepTraceCodableAndReportRemainDiagnosticOnly() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let sample = RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: 10, availableForWorkBytes: 10, state: .fresh, measuredAt: date), trigger: "Synthetic", now: date)
        var incident = StorageIncident(trigger: .manual, before: sample)
        incident.deepTraceEvidence = DeepTraceController.synthetic(lines: ["writer WRITE path=/tmp/a"], authorized: true, now: date)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerTrace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let urls = try StorageIncidentReportWriter.write(incident, store: IncidentStore(home: home.path))
        let markdown = try String(contentsOf: urls.first { $0.pathExtension == "md" }!)
        let json = try String(contentsOf: urls.first { $0.pathExtension == "json" }!)
        XCTAssertTrue(markdown.contains("## Deep incident trace"))
        XCTAssertTrue(json.contains("deepTraceEvidence"))
        XCTAssertTrue(markdown.contains("diagnostic only"))
    }

    func testDeepTraceProductionRunnerHonorsInjectedCancellation() {
        let result = DeepTraceController.runBounded(
            incidentPaths: ["/fixture"],
            requestedDuration: 5,
            executable: URL(fileURLWithPath: "/usr/bin/yes"),
            isCancelled: { true }
        )
        XCTAssertEqual(result.coverage, .cancelled)
        XCTAssertEqual(result.state, .partial)
    }
}

final class IncidentCompatibilityTests: XCTestCase {
    func testIncidentDecodesWhenAllCompletionFieldsAreAbsent() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let incident = StorageIncident(trigger: .manual, before: RecorderCapacitySample(status: DiskStatus(immediatelyFreeBytes: 10, availableForWorkBytes: 10, state: .fresh, measuredAt: date), trigger: "Synthetic", now: date))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(incident)) as! [String: Any]
        for key in ["filesystemEventRecovery", "repeatedPatterns", "localCloudComparisons", "emergencyReserveActivity", "deepTraceEvidence"] {
            object.removeValue(forKey: key)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StorageIncident.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.repeatedPatterns)
        XCTAssertNil(decoded.localCloudComparisons)
        XCTAssertNil(decoded.emergencyReserveActivity)
        XCTAssertNil(decoded.deepTraceEvidence)
    }

    func testIncidentAllEvidenceLargeValuesPartialFailedAndReportsRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let before = RecorderCapacitySample(
            status: DiskStatus(immediatelyFreeBytes: Int64.max - 1_000, availableForWorkBytes: Int64.max - 1_000, state: .fresh, measuredAt: date),
            trigger: "Synthetic",
            now: date
        )
        var incident = StorageIncident(trigger: .manual, before: before, completeness: .partial, coverageGaps: ["Synthetic partial subsystem"])
        incident.after = RecorderCapacitySample(
            status: DiskStatus(immediatelyFreeBytes: Int64.max - 5_000, availableForWorkBytes: Int64.max - 5_000, state: .fresh, measuredAt: date.addingTimeInterval(1)),
            trigger: "Synthetic completion",
            now: date.addingTimeInterval(1)
        )
        incident.filesystemEventRecovery = FilesystemEventRecovery(
            outcome: .eventsDropped,
            storedCheckpointEventID: UInt64.max - 1,
            requestedResumeEventID: UInt64.max - 1,
            watchedVolumeIdentity: "fixture",
            watchedRoots: ["/fixture/private-name"],
            userEventsDropped: true,
            evidenceCompleteness: .partial,
            detail: "Partial recovery retained"
        )
        let pattern = RepeatedPattern(
            kind: .recurrenceReduced,
            confidence: PatternConfidence.probable.rawValue,
            incidents: [incident],
            normalizedPath: "/fixture",
            supporting: ["Later incident smaller"],
            retentionControl: "Keep last 7 days"
        )
        incident.repeatedPatterns = [pattern]
        incident.localCloudComparisons = [CopyComparisonResult(
            localRoot: "/fixture/local",
            cloudRoot: "/fixture/cloud",
            provider: "Synthetic",
            providerMode: .ordinary,
            classification: .incomplete,
            confidence: "Cancelled bounded comparison",
            comparisonStartedAt: date,
            comparisonEndedAt: date.addingTimeInterval(1),
            filesSampled: 1,
            directoriesExamined: 1,
            placeholdersSkipped: 1,
            datalessFilesSkipped: 1,
            symlinksSkipped: 0,
            filesystemBoundariesRefused: 1,
            filesMatched: 0,
            filesDiffering: 0,
            bytesRead: Int64.max - 4_096,
            hashBytesRead: Int64.max - 4_096,
            localPhysicalAllocation: Int64.max - 8_192,
            cloudPhysicalAllocation: Int64.max - 8_192,
            localLogicalBytes: Int64.max - 4_096,
            cloudLogicalBytes: Int64.max - 4_096,
            matchingRelativePaths: [],
            differingRelativePaths: [],
            stableIdentifiersMatched: 0,
            hashesMatched: 0,
            coverage: .cancelled,
            limitsReached: ["Cancellation requested"],
            cancelled: true,
            lowSpace: false,
            reason: "Partial evidence retained; no contents included.",
            safeActions: ["Reveal both locations"],
            disposition: .undecided
        )]
        incident.emergencyReserveActivity = EmergencyReserveStatus(
            state: .failed,
            targetBytes: Int64.max - 2_048,
            eligibilityReason: "Failed closed",
            failureReason: "Synthetic failure",
            measurementCompleteness: .failed
        )
        incident.deepTraceEvidence = DeepTraceController.synthetic(lines: ["writer WRITE path=/fixture/private-name"], authorized: true, cancelled: true, incidentPaths: ["/fixture"], now: date)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(incident)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StorageIncident.self, from: data)
        XCTAssertEqual(decoded.filesystemEventRecovery?.storedCheckpointEventID, UInt64.max - 1)
        XCTAssertEqual(decoded.localCloudComparisons?.first?.hashBytesRead, Int64.max - 4_096)
        XCTAssertEqual(decoded.emergencyReserveActivity?.targetBytes, Int64.max - 2_048)
        XCTAssertEqual(decoded.deepTraceEvidence?.coverage, .cancelled)

        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerCompatibility-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let reports = try StorageIncidentReportWriter.write(decoded, store: IncidentStore(home: home.path))
        let markdown = try String(contentsOf: reports.first { $0.pathExtension == "md" }!)
        let json = try String(contentsOf: reports.first { $0.pathExtension == "json" }!)
        for section in ["Filesystem event recovery", "Repeated patterns", "Local and cloud comparison", "Emergency reserve", "Deep incident trace"] {
            XCTAssertTrue(markdown.contains(section))
        }
        XCTAssertTrue(markdown.contains("Diagnostic only"))
        XCTAssertTrue(markdown.contains("Cancelled"))
        for field in ["filesystemEventRecovery", "repeatedPatterns", "localCloudComparisons", "emergencyReserveActivity", "deepTraceEvidence"] {
            XCTAssertTrue(json.contains(field))
        }
        XCTAssertFalse(markdown.contains("file contents"))
    }

    func testMalformedOptionalEvidenceFieldFailsClosedUnderCurrentSchemaPolicy() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let incident = StorageIncident(
            trigger: .manual,
            before: RecorderCapacitySample(
                status: DiskStatus(immediatelyFreeBytes: 10, availableForWorkBytes: 10, state: .fresh, measuredAt: date),
                trigger: "Synthetic",
                now: date
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(incident)) as! [String: Any]
        object["deepTraceEvidence"] = ["state": 42]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(StorageIncident.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}

final class UICertificationTests: XCTestCase {
    private func configuredExecutable() -> URL? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return [root.appendingPathComponent(".build-final/debug/DexCleaner"), root.appendingPathComponent(".build-final/arm64-apple-macosx/debug/DexCleaner"), root.appendingPathComponent(".build-1_3_1-release-gate/debug/DexCleaner"), root.appendingPathComponent(".build-1_3_1-release-gate/arm64-apple-macosx/debug/DexCleaner")].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func testProductionStorageIncidentsViewRendersEightNonblankPNGStates() throws {
        #if !os(macOS)
        throw XCTSkip("Production SwiftUI rendering is certified by the macOS CI job.")
        #endif
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let executableCandidates = [
            root.appendingPathComponent(".build-final/debug/DexCleaner"),
            root.appendingPathComponent(".build-final/arm64-apple-macosx/debug/DexCleaner"),
            root.appendingPathComponent(".build-1_3_1-release-gate/debug/DexCleaner"),
            root.appendingPathComponent(".build-1_3_1-release-gate/arm64-apple-macosx/debug/DexCleaner")
        ]
        guard let executable = executableCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            return XCTFail("The built DexCleaner executable was not found in a configured scratch path.")
        }
        let output = fileManager.temporaryDirectory
            .appendingPathComponent("DexCleaner-UICertification-\(UUID().uuidString)", isDirectory: true)
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["DEXCLEANER_UI_CERTIFICATION_OUTPUT"] = output.path
        process.environment = environment
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let finished = expectation(description: "Production renderer exits")
        process.terminationHandler = { _ in finished.fulfill() }
        wait(for: [finished], timeout: 120)
        if process.isRunning { process.terminate() }
        let errors = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, errors)

        let manifestURL = output.appendingPathComponent("render-manifest.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        let manifest = try XCTUnwrap(object as? [[String: Any]])
        XCTAssertEqual(manifest.count, 8)
        XCTAssertEqual((try fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)).filter { $0.pathExtension == "png" }.count, 8)
        for item in manifest {
            XCTAssertEqual(item["productionView"] as? String, "StorageIncidentsView")
            XCTAssertEqual(item["reduceMotion"] as? Bool, true)
            XCTAssertGreaterThan(item["width"] as? Int ?? 0, 0)
            XCTAssertGreaterThan(item["height"] as? Int ?? 0, 0)
            XCTAssertGreaterThan(item["pngBytes"] as? Int ?? 0, 10_000)
            XCTAssertGreaterThan(item["meaningfulPixelBytes"] as? Int ?? 0, 5_000)
            XCTAssertFalse((item["renderedText"] as? [String] ?? []).isEmpty)
        }
        let recognized = manifest.flatMap { $0["renderedText"] as? [String] ?? [] }.joined(separator: " ")
        for label in ["Storage Incidents", "Activity Center", "Emergency reserve", "Deep incident trace", "Local and cloud comparison", "Repeated patterns", "Cancel", "Complete", "Partial", "Failed"] {
            XCTAssertTrue(recognized.localizedCaseInsensitiveContains(label), "Rendered pixels did not contain expected label: \(label)")
        }
        let metadata = try fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".accessibility.txt") }
        XCTAssertEqual(metadata.count, 8)
        XCTAssertTrue(try metadata.allSatisfy { try String(contentsOf: $0).contains("Reduce Motion: enabled") })
        let pngData = try fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .map { try Data(contentsOf: $0) }
        XCTAssertGreaterThan(Set(pngData).count, 5, "The deterministic production states must produce materially different renders.")
    }

    func testCleanupCampaignViewRendersNonblankPNGAndAccessibilityContract() throws {
        #if !os(macOS)
        throw XCTSkip("Production SwiftUI rendering is certified by the macOS CI job.")
        #endif
        let executable = try XCTUnwrap(configuredExecutable(), "The built DexCleaner executable was not found in a configured scratch path.")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleaner-Campaign-Certification-\(UUID().uuidString)", isDirectory: true)
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["DEXCLEANER_CAMPAIGN_UI_CERTIFICATION_OUTPUT"] = output.path
        process.environment = environment
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let finished = expectation(description: "Campaign renderer exits")
        process.terminationHandler = { _ in finished.fulfill() }
        wait(for: [finished], timeout: 120)
        if process.isRunning { process.terminate() }
        XCTAssertEqual(process.terminationStatus, 0, String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        let png = output.appendingPathComponent("cleanup-campaign.png")
        XCTAssertGreaterThan((try Data(contentsOf: png)).count, 10_000)
        let accessibility = try String(contentsOf: output.appendingPathComponent("cleanup-campaign.accessibility.txt"))
        for text in ["Evidence-driven cleanup campaign", "STOP recommended", "Review Findings", "Re-audit Campaign", "Exact selection and Preview remain required"] { XCTAssertTrue(accessibility.contains(text)) }
    }
}

final class OperationStateTests: XCTestCase {
    func testOperationStateExposesTruthfulElapsedCountsAndIndeterminateTotal() {
        let start = Date(timeIntervalSince1970: 100)
        let operation = DiagnosticOperation(type: "Synthetic diagnostic", phase: "Measuring", state: .running, startedAt: start, endedAt: nil, processed: 3, total: nil, bytes: 4_096, summary: "Running", reportPath: nil, currentSafePath: "/tmp/fixture", lastMeaningfulProgress: start, cancellable: true)
        XCTAssertEqual(operation.elapsed(at: start.addingTimeInterval(5)), 5)
        XCTAssertNil(operation.total)
        XCTAssertEqual(operation.processed, 3)
        XCTAssertTrue(operation.cancellable == true)
        XCTAssertEqual(DiagnosticOperationState.allTestStates.count, 9)
    }
}

final class ActivityCenterTests: XCTestCase {
    func testActivityCenterRetentionLimitAndCompletionSummaryAreCodable() throws {
        let start = Date(timeIntervalSince1970: 100)
        let operations = (0..<100).map {
            DiagnosticOperation(type: "Operation \($0)", phase: "Complete", state: .complete, startedAt: start, endedAt: start.addingTimeInterval(1), processed: 1, total: 1, bytes: 0, summary: "Retained completion summary", reportPath: nil)
        }
        let data = try JSONEncoder().encode(operations)
        let decoded = try JSONDecoder().decode([DiagnosticOperation].self, from: data)
        XCTAssertEqual(decoded.count, 100)
        XCTAssertEqual(decoded.first?.summary, "Retained completion summary")
    }
}

final class DiagnosticCleanupSeparationTests: XCTestCase {
    func testAllCompletionEvidenceRemainsOutsideCleanupAuthorizationModels() {
        let evidenceTypeNames = [
            String(describing: FilesystemEventRecovery.self),
            String(describing: RepeatedPattern.self),
            String(describing: CopyComparisonResult.self),
            String(describing: EmergencyReserveStatus.self),
            String(describing: DeepTraceEvidence.self)
        ]
        XCTAssertFalse(evidenceTypeNames.contains(String(describing: CleanupPlan.self)))
        XCTAssertFalse(evidenceTypeNames.contains(String(describing: PreviewAuthorization.self)))
    }
}

private extension DiagnosticOperationState {
    static var allTestStates: [DiagnosticOperationState] {
        [.idle, .preparing, .running, .waiting, .cancelling, .cancelled, .partial, .failed, .complete]
    }
}

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
