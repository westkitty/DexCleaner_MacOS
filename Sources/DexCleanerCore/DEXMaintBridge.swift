import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct DEXMaintRunSummary: Codable, Hashable, Sendable {
    public var runId: String
    public var createdAt: String?
    public var status: String?
    public var pressure: String?
    public var actionCount: Int
    public var accountedCandidateBytes: Int64
    public var measuredReclaimBytes: Int64
    public var deletedOpenBytes: Int64?
    public var rebootRecommended: Bool
    public var protectedOrBlockedCount: Int
}

public struct DEXMaintStatus: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var status: String
    public var observedAt: String
    public var kernelVersion: String
    public var policyVersion: String
    public var target: String
    public var immediatelyFreeBytes: Int64
    public var availableForWorkBytes: Int64?
    public var pressure: String
    public var targetFreeBytes: Int64
    public var watcherRunning: Bool
    public var watcherPid: Int?
    public var lastRun: DEXMaintRunSummary?
}

public enum DEXMaintTriggerResult: String, Hashable, Sendable {
    case triggered
    case alreadyRunning
}

public enum DEXMaintBridgeError: LocalizedError, Sendable {
    case launchAgentMissing(String)
    case launchAgentInvalid(String)
    case statusCommandFailed(String)
    case statusDecodeFailed(String)
    case kickstartFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .launchAgentMissing(let path):
            return "Storage Guardian is not installed at \(path)."
        case .launchAgentInvalid(let detail):
            return "Storage Guardian launch configuration is invalid: \(detail)"
        case .statusCommandFailed(let detail):
            return "Storage Guardian status failed: \(detail)"
        case .statusDecodeFailed(let detail):
            return "Storage Guardian returned invalid status: \(detail)"
        case .kickstartFailed(let detail):
            return "Storage Guardian could not be started: \(detail)"
        case .timedOut:
            return "Storage Guardian did not finish within the allowed wait window."
        }
    }
}

private struct DEXMaintLaunchAgentDefinition: Decodable {
    let label: String
    let programArguments: [String]

    enum CodingKeys: String, CodingKey {
        case label = "Label"
        case programArguments = "ProgramArguments"
    }
}

public struct DEXMaintBridge: @unchecked Sendable {
    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> ShellResult
    public typealias Sleeper = @Sendable (_ seconds: TimeInterval) -> Void

    public static let label = "com.stinkyweasel.dexmaint.watch"

    private let homePath: String
    private let userID: UInt32
    private let runner: Runner
    private let sleeper: Sleeper

    public init(
        homePath: String = NSHomeDirectory(),
        userID: UInt32 = getuid(),
        runner: @escaping Runner = { executable, arguments, timeout in
            Shell.run(executable, arguments, timeout: timeout)
        },
        sleeper: @escaping Sleeper = { seconds in
            Thread.sleep(forTimeInterval: seconds)
        }
    ) {
        self.homePath = homePath
        self.userID = userID
        self.runner = runner
        self.sleeper = sleeper
    }

    public static var production: DEXMaintBridge { DEXMaintBridge() }

    public func status() throws -> DEXMaintStatus {
        let definition = try launchAgentDefinition()
        let python = definition.programArguments[0]
        let kernel = definition.programArguments[1]
        let result = runner(python, [kernel, "status", "--target", "macbook"], 8)
        guard !result.timedOut, !result.cancelled, result.status == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DEXMaintBridgeError.statusCommandFailed(detail.isEmpty ? "exit status \(result.status)" : detail)
        }

        let data = Data(result.stdout.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let decoded = try decoder.decode(DEXMaintStatus.self, from: data)
            guard decoded.schemaVersion == 1, decoded.status == "ok", decoded.target == "macbook" else {
                throw DEXMaintBridgeError.statusDecodeFailed("unexpected schema, status, or target")
            }
            return decoded
        } catch let error as DEXMaintBridgeError {
            throw error
        } catch {
            throw DEXMaintBridgeError.statusDecodeFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func trigger() throws -> DEXMaintTriggerResult {
        let current = try status()
        if current.watcherRunning {
            return .alreadyRunning
        }
        let result = runner(
            "/bin/launchctl",
            ["kickstart", "gui/\(userID)/\(Self.label)"],
            10
        )
        guard !result.timedOut, !result.cancelled, result.status == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DEXMaintBridgeError.kickstartFailed(detail.isEmpty ? "exit status \(result.status)" : detail)
        }
        return .triggered
    }

    public func runNowAndWait(
        timeout: TimeInterval = 15 * 60,
        pollInterval: TimeInterval = 2
    ) throws -> DEXMaintStatus {
        let baseline = try status()
        let baselineRunID = baseline.lastRun?.runId
        let startedRunning = baseline.watcherRunning
        _ = try trigger()

        let deadline = Date().addingTimeInterval(timeout)
        var observedRunning = startedRunning
        while Date() < deadline {
            sleeper(pollInterval)
            let current = try status()
            if current.watcherRunning {
                observedRunning = true
                continue
            }
            if current.lastRun?.runId != baselineRunID {
                return current
            }
            if !observedRunning {
                continue
            }
        }
        throw DEXMaintBridgeError.timedOut
    }

    private func launchAgentDefinition() throws -> DEXMaintLaunchAgentDefinition {
        let url = URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw DEXMaintBridgeError.launchAgentMissing(url.path)
        }

        let definition: DEXMaintLaunchAgentDefinition
        do {
            definition = try PropertyListDecoder().decode(
                DEXMaintLaunchAgentDefinition.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw DEXMaintBridgeError.launchAgentInvalid(error.localizedDescription)
        }

        guard definition.label == Self.label else {
            throw DEXMaintBridgeError.launchAgentInvalid("unexpected label \(definition.label)")
        }
        let arguments = definition.programArguments
        guard arguments.count >= 6,
              arguments[2] == "watch",
              arguments[3] == "--target",
              arguments[4] == "macbook",
              arguments.contains("--apply-auto") else {
            throw DEXMaintBridgeError.launchAgentInvalid("unexpected ProgramArguments")
        }
        guard arguments[0].hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: arguments[0]) else {
            throw DEXMaintBridgeError.launchAgentInvalid("configured Python executable is unavailable")
        }
        guard arguments[1].hasPrefix("/"),
              FileManager.default.isReadableFile(atPath: arguments[1]) else {
            throw DEXMaintBridgeError.launchAgentInvalid("configured DEX//MAINT kernel is unavailable")
        }
        return definition
    }
}
