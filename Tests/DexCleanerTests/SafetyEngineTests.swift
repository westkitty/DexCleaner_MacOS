import Foundation
import XCTest
@testable import DexCleanerCore

final class SafetyEngineTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func item(path: String, category: CleanupCategory = .exactCache, risk: RiskLevel = .safe, action: CleanupAction = .moveToTrash) -> ScanItem {
        ScanItem(path: path, displayName: "Test item", category: category, risk: risk, sizeBytes: 1024, explanation: "Test", action: action, isSelected: false)
    }

    func testExactManifestTargetIsAllowed() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let decision = SafetyEngine.decision(for: item(path: target.path), home: home.path, gitProcessChecker: { false })
        XCTAssertTrue(decision.allowed, decision.reason)
    }

    func testBroadRootsAreRejectedEvenWhenMarkedSafe() throws {
        let home = try temporaryHome()
        let paths = [".cache", "Library/Caches", "Library/Application Support", "Library", "Projects", "Documents", "Downloads", "Movies", "Pictures", "Desktop"].map { home.appendingPathComponent($0).path }
        for path in paths {
            let decision = SafetyEngine.decision(for: item(path: path), home: home.path, gitProcessChecker: { false })
            XCTAssertFalse(decision.allowed, "Allowed broad root: \(path)")
        }
    }

    func testUnknownApplicationSupportPathIsRejected() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Application Support/Discord")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let decision = SafetyEngine.decision(for: item(path: target.path), home: home.path, gitProcessChecker: { false })
        XCTAssertFalse(decision.allowed)
    }

    func testProtectedStateFragmentsAreRejected() throws {
        let home = try temporaryHome()
        let protectedPaths = [
            "Library/Application Support/Code/User/workspaceStorage",
            "Library/Application Support/Code/User/globalStorage",
            "Library/Application Support/Code/User/History",
            "Library/Application Support/Google/Chrome/Default/Local Storage",
            "Library/Application Support/Claude/vm_bundles",
            "Library/CloudStorage/Google Drive"
        ].map { home.appendingPathComponent($0).path }
        for path in protectedPaths {
            let decision = SafetyEngine.decision(for: item(path: path), home: home.path, gitProcessChecker: { false })
            XCTAssertFalse(decision.allowed, "Allowed protected path: \(path)")
        }
    }

    func testSymlinkedExactTargetIsRejected() throws {
        let home = try temporaryHome()
        let safeParent = home.appendingPathComponent("Library/Caches")
        let userData = home.appendingPathComponent("Documents/ImportantStuff")
        let symlink = safeParent.appendingPathComponent("Homebrew")
        try FileManager.default.createDirectory(at: safeParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: symlink.path, withDestinationPath: userData.path)
        let decision = SafetyEngine.decision(for: item(path: symlink.path), home: home.path, gitProcessChecker: { false })
        XCTAssertFalse(decision.allowed)
    }

    func testAuditOnlyAndNonSafeItemsAreRejected() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: target.path, risk: .caution), home: home.path, gitProcessChecker: { false }).allowed)
        XCTAssertFalse(SafetyEngine.decision(for: item(path: target.path, action: .auditOnly), home: home.path, gitProcessChecker: { false }).allowed)
    }

    func testStrictGitTemporaryPackIsAllowedOnlyWhenOldUnlockedAndNoGitProcessRuns() throws {
        let home = try temporaryHome()
        let packDir = home.appendingPathComponent("Projects/Example/.git/objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let tmpPack = packDir.appendingPathComponent("tmp_pack_abc123")
        try Data("data".utf8).write(to: tmpPack)
        let oldDate = Date().addingTimeInterval(-SafetyEngine.gitTempPackMinimumAge - 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: tmpPack.path)

        let valid = SafetyEngine.decision(for: item(path: tmpPack.path, category: .gitTemporaryPack), home: home.path, gitProcessChecker: { false })
        XCTAssertTrue(valid.allowed, valid.reason)
        let blockedByProcess = SafetyEngine.decision(for: item(path: tmpPack.path, category: .gitTemporaryPack), home: home.path, gitProcessChecker: { true })
        XCTAssertFalse(blockedByProcess.allowed)
    }

    func testGitTemporaryPackScannerFindsHiddenGitDirectoryPackFiles() throws {
        let home = try temporaryHome()
        let packDir = home.appendingPathComponent("Projects/Example/.git/objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let tmpPack = packDir.appendingPathComponent("tmp_pack_hidden_git")
        try Data("data".utf8).write(to: tmpPack)
        let oldDate = Date().addingTimeInterval(-SafetyEngine.gitTempPackMinimumAge - 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: tmpPack.path)
        let scanner = DiskScanner(home: home.path, cache: ScanCache(home: home.path))
        let found = scanner.gitTemporaryPackItems(gitProcessChecker: { false })
        XCTAssertTrue(found.contains { $0.path == tmpPack.path }, "Scanner must not skip hidden .git directories.")
    }

    func testGitTemporaryPackWithWrongLocationOrRecentAgeIsRejected() throws {
        let home = try temporaryHome()
        let wrongDir = home.appendingPathComponent("Projects/Example/.git/objects")
        try FileManager.default.createDirectory(at: wrongDir, withIntermediateDirectories: true)
        let wrongFile = wrongDir.appendingPathComponent("tmp_pack_abc123")
        try Data("data".utf8).write(to: wrongFile)
        let wrongLocation = SafetyEngine.decision(for: item(path: wrongFile.path, category: .gitTemporaryPack), home: home.path, gitProcessChecker: { false })
        XCTAssertFalse(wrongLocation.allowed)

        let packDir = home.appendingPathComponent("Projects/Example/.git/objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let recentFile = packDir.appendingPathComponent("tmp_pack_recent")
        try Data("data".utf8).write(to: recentFile)
        let recent = SafetyEngine.decision(for: item(path: recentFile.path, category: .gitTemporaryPack), home: home.path, gitProcessChecker: { false })
        XCTAssertFalse(recent.allowed)
    }
}

final class ResearchLedFeatureTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerFeatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func item(path: String, risk: RiskLevel = .safe, action: CleanupAction = .moveToTrash, isSelected: Bool = true) -> ScanItem {
        ScanItem(manifestID: "test", path: path, displayName: "Test item", group: "Tests", category: .exactCache, risk: risk, sizeBytes: 1024, explanation: "Test", recoveryNote: "Test recovery", action: action, isSelected: isSelected)
    }

    func testManifestDecodesRiskTiersAndIds() throws {
        XCTAssertFalse(CleanupCatalog.cleanableEntries.isEmpty)
        XCTAssertTrue(CleanupCatalog.exactSafeEntries.contains { $0.risk == .caution })
        XCTAssertTrue(CleanupCatalog.exactSafeEntries.contains { $0.id == "xcode-derived-data" })
        XCTAssertTrue(CleanupCatalog.cleanableEntries.contains { $0.id == "npm-cache" })
        XCTAssertTrue(CleanupCatalog.cleanableEntries.contains { $0.id == "xcode-module-cache" })
        XCTAssertTrue(CleanupCatalog.cleanableEntries.contains { $0.id == "simulator-cache" })
        XCTAssertTrue(CleanupCatalog.exactSafeEntries.allSatisfy { !$0.id.isEmpty && !$0.group.isEmpty && !$0.recoveryNote.isEmpty })
    }

    func testDryRunDoesNotMoveOrDeleteSafeTarget() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: target.appendingPathComponent("artifact.txt"))
        let runner = CleanupRunner(home: home.path)
        let results = runner.dryRunSelected([item(path: target.path)])
        XCTAssertEqual(results.first?.status, "Would move to Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "Dry run must never move or delete files.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("artifact.txt").path))
    }

    func testCautionAndAuditOnlyItemsAreBlockedInPreview() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let caution = item(path: target.path, risk: .caution, action: .moveToTrash)
        let audit = item(path: target.path, risk: .safe, action: .auditOnly)
        let results = CleanupRunner(home: home.path).dryRunSelected([caution, audit])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.status == "Blocked" })
    }

    func testCloudStorageIsRejectedEvenIfIncorrectlyMarkedSafe() throws {
        let home = try temporaryHome()
        let target = home.appendingPathComponent("Library/CloudStorage/Google Drive")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let decision = SafetyEngine.decision(for: item(path: target.path, risk: .safe, action: .moveToTrash), home: home.path, gitProcessChecker: { false })
        XCTAssertFalse(decision.allowed)
    }

    func testReportIncludesManifestIdRecoveryAndDryRunMode() throws {
        let home = try temporaryHome()
        let reportDir = home.appendingPathComponent("reports")
        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let scanItem = item(path: target.path)
        let report = ScanReport(
            mode: .dryRun,
            timestamp: Date(),
            diskStatus: DiskStatus(filesystem: "testfs", size: "10G", used: "5G", available: "5G", capacity: "50%"),
            items: [scanItem],
            results: CleanupRunner(home: home.path).dryRunSelected([scanItem]),
            storageSummaries: [StorageSummaryItem(label: "Cleanable exact targets", bytes: 1024, detail: "Test")],
            permissionDiagnostics: [PermissionDiagnostic(title: "FDA", status: "Unknown", detail: "Test", remediation: "Test")],
            warnings: ["Test warning"],
            scanDurationSeconds: 0.1,
            policyVersion: "test",
            appVersion: "test",
            fullDiskAccessStatus: "Unknown"
        )
        let url = try ReportWriter.write(report: report, destinationDirectory: reportDir)
        let text = try String(contentsOf: url)
        XCTAssertTrue(text.contains("Dry run preview"))
        XCTAssertTrue(text.contains("Manifest ID"))
        XCTAssertTrue(text.contains("Recovery note"))
        XCTAssertTrue(text.contains("Test warning"))
    }
}
