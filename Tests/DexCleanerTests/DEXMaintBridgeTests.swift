import Foundation
import XCTest
@testable import DexCleanerCore

final class DEXMaintBridgeTests: XCTestCase {
    final class ScriptedRunner: @unchecked Sendable {
        private let lock = NSLock()
        private var statusCalls = 0
        private(set) var launchctlCalls = 0

        func run(_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> ShellResult {
            lock.lock()
            defer { lock.unlock() }

            if executable == "/bin/launchctl" {
                launchctlCalls += 1
                return ShellResult(status: 0, stdout: "", stderr: "", timedOut: false, durationSeconds: 0)
            }

            statusCalls += 1
            let json: String
            switch statusCalls {
            case 1, 2:
                json = Self.statusJSON(watcherRunning: false, runID: "maint-macbook-20260930T000000Z-aaaaaaaa")
            case 3:
                json = Self.statusJSON(watcherRunning: true, runID: "maint-macbook-20260930T000000Z-aaaaaaaa")
            default:
                json = Self.statusJSON(watcherRunning: false, runID: "maint-macbook-20260930T010000Z-bbbbbbbb")
            }
            return ShellResult(status: 0, stdout: json, stderr: "", timedOut: false, durationSeconds: 0)
        }

        static func statusJSON(watcherRunning: Bool, runID: String) -> String {
            """
            {
              "schema_version": 1,
              "status": "ok",
              "observed_at": "2026-09-30T01:00:00Z",
              "kernel_version": "2.3.1",
              "policy_version": "2.3.0",
              "target": "macbook",
              "immediately_free_bytes": 15000000000,
              "available_for_work_bytes": 16000000000,
              "pressure": "LOW",
              "target_free_bytes": 32212254720,
              "watcher_running": \(watcherRunning ? "true" : "false"),
              "watcher_pid": null,
              "last_run": {
                "run_id": "\(runID)",
                "created_at": "2026-09-30T01:00:00Z",
                "status": "WATCHED",
                "pressure": "LOW",
                "action_count": 2,
                "accounted_candidate_bytes": 1000,
                "measured_reclaim_bytes": 700,
                "deleted_open_bytes": 123,
                "reboot_recommended": false,
                "protected_or_blocked_count": 4
              }
            }
            """
        }
    }

    func testStatusUsesInstalledLaunchAgentAsAuthorityPointer() throws {
        let fixture = try makeFixture()
        let runner = ScriptedRunner()
        let bridge = DEXMaintBridge(
            homePath: fixture.home.path,
            userID: 501,
            runner: { executable, arguments, timeout in runner.run(executable, arguments, timeout) },
            sleeper: { _ in }
        )

        let status = try bridge.status()

        XCTAssertEqual(status.kernelVersion, "2.3.1")
        XCTAssertEqual(status.policyVersion, "2.3.0")
        XCTAssertEqual(status.pressure, "LOW")
        XCTAssertEqual(status.lastRun?.measuredReclaimBytes, 700)
        XCTAssertEqual(runner.launchctlCalls, 0)
    }

    func testRunNowKickstartsLaunchAgentAndWaitsForNewRun() throws {
        let fixture = try makeFixture()
        let runner = ScriptedRunner()
        let bridge = DEXMaintBridge(
            homePath: fixture.home.path,
            userID: 501,
            runner: { executable, arguments, timeout in runner.run(executable, arguments, timeout) },
            sleeper: { _ in }
        )

        let status = try bridge.runNowAndWait(timeout: 2, pollInterval: 0)

        XCTAssertEqual(runner.launchctlCalls, 1)
        XCTAssertFalse(status.watcherRunning)
        XCTAssertEqual(status.lastRun?.runId, "maint-macbook-20260930T010000Z-bbbbbbbb")
    }

    func testInvalidLaunchAgentFailsClosedBeforeExecutingStatus() throws {
        let fixture = try makeFixture(programArguments: ["/usr/bin/python3", "/tmp/not-dexmaint.py", "inspect"])
        let runner = ScriptedRunner()
        let bridge = DEXMaintBridge(
            homePath: fixture.home.path,
            userID: 501,
            runner: { executable, arguments, timeout in runner.run(executable, arguments, timeout) },
            sleeper: { _ in }
        )

        XCTAssertThrowsError(try bridge.status()) { error in
            XCTAssertTrue(error.localizedDescription.contains("invalid"))
        }
        XCTAssertEqual(runner.launchctlCalls, 0)
    }

    private func makeFixture(programArguments: [String]? = nil) throws -> (home: URL, python: URL, kernel: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DexMaintBridgeTests-\(UUID().uuidString)", isDirectory: true)
        let launchAgents = root.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)

        let python = root.appendingPathComponent("python")
        let kernel = root.appendingPathComponent("dexmaint_remote.py")
        FileManager.default.createFile(atPath: python.path, contents: Data("#!/bin/sh\n".utf8))
        FileManager.default.createFile(atPath: kernel.path, contents: Data("# fixture\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)

        let args = programArguments ?? [
            python.path,
            kernel.path,
            "watch",
            "--target",
            "macbook",
            "--apply-auto",
        ]
        let plist: [String: Any] = [
            "Label": DEXMaintBridge.label,
            "ProgramArguments": args,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgents.appendingPathComponent("\(DEXMaintBridge.label).plist"))

        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return (root, python, kernel)
    }
}
