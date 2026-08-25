import Foundation

public enum ProcessDetector {
    private static let patternsByGroup: [String: [String]] = [
        "Homebrew": ["brew"],
        "Python": ["pip", "python"],
        "Swift": ["swift", "swift-build", "swift-package"],
        "Node": ["npm", "node"],
        "JavaScript": ["pnpm", "yarn", "node"],
        "CocoaPods": ["pod"],
        "Gradle": ["gradle"],
        "Xcode": ["Xcode", "xcodebuild", "SourceKitService"],
        "Simulator": ["Simulator", "CoreSimulator"],
        "VS Code": ["Visual Studio Code", "Code Helper"]
    ]

    public static func owningProcessIsRunning(forGroup group: String) -> Bool {
        guard let patterns = patternsByGroup[group], !patterns.isEmpty else { return false }
        let expression = patterns.map { "[\($0.prefix(1))]\($0.dropFirst())" }.joined(separator: "|")
        return Shell.run("/usr/bin/pgrep", ["-f", expression], timeout: 2).status == 0
    }
}

public enum ExactOpenFileState: Hashable, Sendable {
    case closed
    case inUse(owners: [String])
    case unavailable(detail: String)
}

public struct ExactOpenFileChecker: @unchecked Sendable {
    private let inspect: @Sendable (String) -> ExactOpenFileState

    public init(inspect: @escaping @Sendable (String) -> ExactOpenFileState) {
        self.inspect = inspect
    }

    public func state(for path: String) -> ExactOpenFileState {
        inspect(path)
    }

    public static let production = ExactOpenFileChecker { path in
        let executable = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return .unavailable(detail: "Exact open-file detector is unavailable.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .unavailable(detail: "Candidate disappeared before open-file inspection.")
        }
        let arguments = isDirectory.boolValue ? ["-Fpc", "+D", path] : ["-Fpc", "--", path]
        let result = Shell.run(executable, arguments, timeout: 5)
        if result.cancelled { return .unavailable(detail: "Exact open-file inspection was cancelled.") }
        if result.timedOut { return .unavailable(detail: "Exact open-file inspection timed out.") }
        if result.status == 1 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .closed
        }
        guard result.status == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(detail: detail.isEmpty ? "Exact open-file inspection failed with status \(result.status)." : detail)
        }
        var owners: [String] = []
        var pid: String?
        for line in result.stdout.split(separator: "\n").map(String.init) {
            if line.hasPrefix("p") { pid = String(line.dropFirst()) }
            if line.hasPrefix("c") {
                let command = String(line.dropFirst())
                owners.append(pid.map { "\(command) (pid \($0))" } ?? command)
            }
        }
        return owners.isEmpty ? .closed : .inUse(owners: Array(Set(owners)).sorted())
    }
}
