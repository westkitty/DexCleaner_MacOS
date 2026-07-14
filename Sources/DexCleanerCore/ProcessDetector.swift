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
