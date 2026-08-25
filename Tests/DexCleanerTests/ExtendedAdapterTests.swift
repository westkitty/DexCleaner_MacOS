import Foundation
import XCTest
@testable import DexCleanerCore

final class ExtendedAdapterTests: XCTestCase {
    private func temporaryRoot(_ label: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleaner-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testHomebrewExactStagingProofAndNormalPreviewPath() throws {
        let home = try temporaryRoot("Homebrew")
        let prefix = home.appendingPathComponent("Library/Caches/Homebrew")
        let staging = prefix.appendingPathComponent("staging")
        let candidate = staging.appendingPathComponent("download-1")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let layout = HomebrewLayoutEvidence(prefix: prefix.path, stagingRoot: staging.path, installedRoots: [prefix.appendingPathComponent("Cellar").path, prefix.appendingPathComponent("Caskroom").path], managerExecutable: "/opt/homebrew/bin/brew", managerAvailable: true, managerIdentityVerified: true)

        let finding = HomebrewStagingAdapter.analyze(candidate: candidate, layout: layout, managerActive: false, openState: .closed, allowCleanup: true)
        XCTAssertEqual(finding.disposition, .actionable)
        var item = finding.scanItem
        item.isSelected = true
        let preview = CleanupRunner(home: home.path, openFileChecker: ExactOpenFileChecker { _ in .closed }).previewSelected([item])
        XCTAssertNotNil(preview.plan)
        XCTAssertEqual(preview.plan?.items.first?.evidence?.provenance.ruleID, HomebrewStagingAdapter.ruleID)
    }

    func testHomebrewInstalledBroadActiveAndUnknownLayoutsFailClosed() throws {
        let home = try temporaryRoot("HomebrewRefusal")
        let prefix = home.appendingPathComponent("brew")
        let staging = prefix.appendingPathComponent("staging")
        let candidate = staging.appendingPathComponent("one")
        let installed = prefix.appendingPathComponent("Cellar/pkg")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let layout = HomebrewLayoutEvidence(prefix: prefix.path, stagingRoot: staging.path, installedRoots: [prefix.appendingPathComponent("Cellar").path], managerExecutable: "brew", managerAvailable: true, managerIdentityVerified: true)
        XCTAssertEqual(HomebrewStagingAdapter.analyze(candidate: prefix, layout: layout, managerActive: false, openState: .closed, allowCleanup: true).disposition, .protected)
        XCTAssertEqual(HomebrewStagingAdapter.analyze(candidate: installed, layout: layout, managerActive: false, openState: .closed, allowCleanup: true).disposition, .protected)
        XCTAssertEqual(HomebrewStagingAdapter.analyze(candidate: candidate, layout: layout, managerActive: true, openState: .closed, allowCleanup: true).disposition, .protected)
        var unavailable = layout
        unavailable.managerIdentityVerified = false
        XCTAssertEqual(HomebrewStagingAdapter.analyze(candidate: candidate, layout: unavailable, managerActive: false, openState: .closed, allowCleanup: true).disposition, .unknown)
    }

    func testFileProviderAndCloudOwnershipOverrideAgeAndSize() {
        let paths = [
            "/Users/test/Library/Application Support/FileProvider/FPCK/huge-old.tmp",
            "/Users/test/Library/Mobile Documents/data",
            "/Users/test/Library/CloudStorage/GoogleDrive/data",
            "/Users/test/Library/Application Support/DriveFS/state"
        ]
        for path in paths {
            let classification = ManagedResourceClassifier.classify(path: path)
            XCTAssertEqual(classification.protection, .protected)
            let item = ScanItem(path: path, displayName: "Old cache-looking file", category: .exactCache, risk: .safe, sizeBytes: Int64.max, explanation: "Synthetic", action: .moveToTrash, isSelected: true)
            XCTAssertFalse(SafetyEngine.decision(for: item, home: "/Users/test").allowed)
        }
    }

    func testGitBundleRequiresIsolatedRestoreAndCoverage() throws {
        let root = try temporaryRoot("GitBundle")
        let repository = root.appendingPathComponent("source")
        let bundle = root.appendingPathComponent("retained.bundle")
        XCTAssertEqual(Shell.run("/usr/bin/git", ["init", "-b", "main", repository.path]).status, 0)
        try Data("proof\n".utf8).write(to: repository.appendingPathComponent("proof.txt"))
        XCTAssertEqual(Shell.run("/usr/bin/git", ["-C", repository.path, "add", "proof.txt"]).status, 0)
        XCTAssertEqual(Shell.run("/usr/bin/git", ["-C", repository.path, "-c", "user.name=DexCleaner Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"]).status, 0)
        XCTAssertEqual(Shell.run("/usr/bin/git", ["-C", repository.path, "bundle", "create", bundle.path, "main"]).status, 0)

        let valid = BackupRestorabilityValidator.validateGitBundle(at: bundle, requiredRef: "refs/heads/main")
        XCTAssertTrue(valid.isRestorable)
        let missing = BackupRestorabilityValidator.validateGitBundle(at: bundle, requiredRef: "refs/heads/missing")
        XCTAssertFalse(missing.requiredContentVerified)
        XCTAssertEqual(BackupRestorabilityValidator.retentionDecision(older: valid, retained: missing).disposition, .protected)
        XCTAssertEqual(BackupRestorabilityValidator.retentionDecision(older: valid, retained: valid).disposition, .supersededReviewCandidate)
    }

    func testApplicationBackupsPreserveUniqueVersionsAndBrokenReplacementBlocks() throws {
        let root = try temporaryRoot("AppBackup")
        func app(_ name: String, version: String, executable: Bool = true) throws -> URL {
            let url = root.appendingPathComponent("\(name).app")
            let macOS = url.appendingPathComponent("Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fixture", "CFBundleExecutable": "Fixture", "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
            if executable { try Data("binary".utf8).write(to: macOS.appendingPathComponent("Fixture")) }
            return url
        }
        let old = BackupRestorabilityValidator.validateApplication(at: try app("old", version: "1"), expectedBundleIdentifier: "com.example.fixture")
        let newer = BackupRestorabilityValidator.validateApplication(at: try app("new", version: "2"), expectedBundleIdentifier: "com.example.fixture")
        let broken = BackupRestorabilityValidator.validateApplication(at: try app("broken", version: "3", executable: false), expectedBundleIdentifier: "com.example.fixture")
        XCTAssertEqual(BackupRestorabilityValidator.retentionDecision(older: old, retained: newer).disposition, .retain)
        XCTAssertEqual(BackupRestorabilityValidator.retentionDecision(older: old, retained: broken).disposition, .protected)
    }

    func testDuplicateAnalysisCollapsesHardlinksAndNeverAutoSelectsByHash() throws {
        let root = try temporaryRoot("Duplicates")
        let first = root.appendingPathComponent("first.bin")
        let alias = root.appendingPathComponent("alias.bin")
        let second = root.appendingPathComponent("second.bin")
        try Data(repeating: 7, count: 4_096).write(to: first)
        try FileManager.default.linkItem(at: first, to: alias)
        try Data(repeating: 7, count: 4_096).write(to: second)
        let roles = [first.path: DuplicateSemanticRole.authoritative, second.path: .updaterCache]
        let result = ExactDuplicateAnalyzer().analyze(files: [first, alias, second], scopeRoot: root, semanticRoles: roles)
        XCTAssertEqual(result.sets.count, 1)
        XCTAssertEqual(result.sets.first?.objects.count, 2)
        XCTAssertEqual(result.aliasesCollapsed, 1)
        XCTAssertEqual(result.sets.first?.reviewOnly, true)
        XCTAssertNil(result.sets.first?.physicalReclaimBytes)
    }

    func testDuplicateCancellationAndBoundsRemainExplicit() throws {
        let root = try temporaryRoot("DuplicateCancel")
        let first = root.appendingPathComponent("one")
        let second = root.appendingPathComponent("two")
        try Data("same".utf8).write(to: first)
        try Data("same".utf8).write(to: second)
        XCTAssertEqual(ExactDuplicateAnalyzer().analyze(files: [first, second], scopeRoot: root, isCancelled: { true }).completeness, .cancelled)
        XCTAssertEqual(ExactDuplicateAnalyzer(maximumFiles: 1).analyze(files: [first, second], scopeRoot: root).completeness, .partial)
    }

    func testCapabilitiesAndSharedModelBlobsRemainNonActionable() {
        let protected = CapabilityClassifier.classify(path: "/models/blobs", ecosystem: .aiModel, role: .sharedBlobStore)
        XCTAssertEqual(protected.disposition, .protected)
        let referenced = CapabilityClassifier.classify(path: "/toolchains/swift", ecosystem: .toolchain, role: .installedCapability, isDefault: true, projectReferenced: true)
        XCTAssertEqual(referenced.disposition, .protected)
        let generated = CapabilityClassifier.classify(path: "/project/.gradle", ecosystem: .gradle, role: .generatedProjectOutput)
        XCTAssertEqual(generated.disposition, .review)
    }
}
