import Foundation
import XCTest
@testable import DexCleanerCore

final class ProjectArtifactAnalyzerTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerProjectTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        return home
    }

    @discardableResult
    private func git(_ arguments: [String], at root: URL) -> ShellResult {
        let result = Shell.run("/usr/bin/git", ["-C", root.path] + arguments, timeout: 5)
        XCTAssertEqual(result.status, 0, result.stderr)
        return result
    }

    private func makeRepository(home: URL) throws -> URL {
        let repository = home.appendingPathComponent("Projects/fixture")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        git(["init", "-q"], at: repository)
        let ignore = "node_modules/\ntarget/\nbuild/\ndist/\n"
        try ignore.write(to: repository.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        return repository
    }

    private func makeNodeWorkspace(_ root: URL, name: String = "node") throws -> URL {
        let workspace = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try "{\"name\":\"fixture\",\"workspaces\":[\"packages/*\"]}".write(to: workspace.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try Data(repeating: 1, count: 32).write(to: workspace.appendingPathComponent("node_modules/package.bin"))
        return workspace
    }

    private func makeRustWorkspace(_ root: URL, name: String = "rust") throws -> URL {
        let workspace = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("target"), withIntermediateDirectories: true)
        try "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\n".write(to: workspace.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try Data(repeating: 2, count: 48).write(to: workspace.appendingPathComponent("target/object.o"))
        return workspace
    }

    func testReadOnlyDiscoveryFindsNodeAndRustWithoutCleanupAuthority() throws {
        let home = try temporaryHome()
        let repository = try makeRepository(home: home)
        _ = try makeNodeWorkspace(repository)
        _ = try makeRustWorkspace(repository)

        let result = ProjectArtifactAnalyzer(home: home.path).scan(root: home.appendingPathComponent("Projects"), allowCleanup: false)
        XCTAssertEqual(result.completeness, .complete)
        XCTAssertEqual(Set(result.findings.map(\.kind)), Set([.nodeModules, .rustTarget]))
        XCTAssertTrue(result.findings.allSatisfy { $0.disposition == .review })
        XCTAssertTrue(result.findings.allSatisfy { $0.scanItem.action == .auditOnly && !$0.scanItem.isCleanable })
    }

    func testProvenNodeAndRustArtifactsCanEnterPreviewOnlyWhenPromotionIsEnabled() throws {
        let home = try temporaryHome()
        let repository = try makeRepository(home: home)
        _ = try makeNodeWorkspace(repository)
        _ = try makeRustWorkspace(repository)
        let result = ProjectArtifactAnalyzer(home: home.path).scan(root: home.appendingPathComponent("Projects"), allowCleanup: true)
        let items = result.findings.map(\.scanItem).map { item -> ScanItem in
            var selected = item
            selected.isSelected = true
            return selected
        }

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy(\.isCleanable), result.findings.map(\.reason).joined(separator: "\n"))
        let runner = CleanupRunner(home: home.path, openFileChecker: ExactOpenFileChecker { _ in .closed })
        let plan = try XCTUnwrap(runner.previewSelected(items).plan)
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertTrue(plan.items.allSatisfy { $0.evidence?.provenance.sourceKind == .dedicatedAdapter })
        XCTAssertTrue(runner.preflight(plan: plan).allowed)
    }

    func testTrackedGenericBuildIsProtectedAndNeverPromoted() throws {
        let home = try temporaryHome()
        let repository = try makeRepository(home: home)
        let workspace = try makeNodeWorkspace(repository)
        let build = workspace.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("generated".utf8).write(to: build.appendingPathComponent("keep.txt"))
        git(["add", "-f", "node/build/keep.txt"], at: repository)

        let result = ProjectArtifactAnalyzer(home: home.path).scan(root: home.appendingPathComponent("Projects"), allowCleanup: true)
        let finding = try XCTUnwrap(result.findings.first { SafetyEngine.lexicalNormalize($0.path) == SafetyEngine.lexicalNormalize(build.path) })
        XCTAssertEqual(finding.disposition, .protected)
        XCTAssertEqual(finding.scanItem.action, .auditOnly)
        XCTAssertFalse(finding.scanItem.isCleanable)
    }

    func testMonorepoRootNodeModulesUsesWorkspaceAuthority() throws {
        let home = try temporaryHome()
        let repository = try makeRepository(home: home)
        try "{\"name\":\"monorepo\",\"workspaces\":[\"packages/*\"]}".write(to: repository.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: repository.appendingPathComponent("node_modules"), withIntermediateDirectories: true)

        let result = ProjectArtifactAnalyzer(home: home.path).scan(root: home.appendingPathComponent("Projects"), allowCleanup: true)
        let finding = try XCTUnwrap(result.findings.first { $0.kind == .nodeModules })
        XCTAssertEqual(finding.disposition, .actionable, finding.reason)
        XCTAssertTrue(finding.evidence?.isActionable == true, finding.evidence?.actionabilityProblems.joined(separator: ", ") ?? "missing evidence")
    }

    func testNoWorkspaceAuthoritySymlinkAndHiddenMetadataFailClosed() throws {
        let home = try temporaryHome()
        let repository = try makeRepository(home: home)
        let orphan = repository.appendingPathComponent("orphan/node_modules")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let outside = repository.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let linkedWorkspace = repository.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linkedWorkspace, withIntermediateDirectories: true)
        try "{\"name\":\"linked\"}".write(to: linkedWorkspace.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkedWorkspace.appendingPathComponent("node_modules"), withDestinationURL: outside)
        let hidden = repository.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: hidden.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try "{\"name\":\"hidden\"}".write(to: hidden.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let result = ProjectArtifactAnalyzer(home: home.path).scan(root: home.appendingPathComponent("Projects"), allowCleanup: true)
        XCTAssertEqual(result.findings.first { SafetyEngine.lexicalNormalize($0.path) == SafetyEngine.lexicalNormalize(orphan.path) }?.disposition, .review)
        XCTAssertEqual(result.findings.first { SafetyEngine.lexicalNormalize($0.path) == SafetyEngine.lexicalNormalize(linkedWorkspace.appendingPathComponent("node_modules").path) }?.disposition, .review)
        XCTAssertFalse(result.findings.contains { $0.path.contains("/.hidden/") })
        XCTAssertFalse(result.findings.contains { SafetyEngine.lexicalNormalize($0.path) == SafetyEngine.lexicalNormalize(orphan.path) && $0.scanItem.isCleanable })
    }

    func testIncompleteMeasurementAndCancellationRemainExplicit() throws {
        let home = try temporaryHome()
        let repository = try makeRepository(home: home)
        let workspace = try makeNodeWorkspace(repository)
        try Data(repeating: 3, count: 16).write(to: workspace.appendingPathComponent("node_modules/second.bin"))
        let limits = ProjectArtifactScanLimits(maximumMeasuredEntries: 1)
        let limited = ProjectArtifactAnalyzer(home: home.path, limits: limits).scan(root: home.appendingPathComponent("Projects"), allowCleanup: true)
        let finding = try XCTUnwrap(limited.findings.first { $0.kind == .nodeModules })
        XCTAssertEqual(finding.disposition, .unknown)
        XCTAssertFalse(finding.scanItem.isCleanable)

        let cancelled = ProjectArtifactAnalyzer(home: home.path).scan(root: home.appendingPathComponent("Projects"), allowCleanup: false, isCancelled: { true })
        XCTAssertEqual(cancelled.completeness, .cancelled)
        XCTAssertTrue(cancelled.issues.contains { $0.kind == .cancellation })
    }
}
