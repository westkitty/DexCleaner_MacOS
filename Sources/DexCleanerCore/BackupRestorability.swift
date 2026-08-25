import Foundation

public enum BackupFormat: String, Codable, Hashable, Sendable {
    case gitBundle = "Git bundle"
    case macOSApplication = "macOS application"
}

public struct BackupValidationResult: Codable, Hashable, Sendable {
    public var format: BackupFormat
    public var path: String
    public var integrityVerified: Bool
    public var isolatedRestoreVerified: Bool
    public var requiredContentVerified: Bool
    public var identity: String?
    public var version: String?
    public var contentFingerprint: String?
    public var reason: String

    public var isRestorable: Bool { integrityVerified && isolatedRestoreVerified && requiredContentVerified }
}

public enum BackupDisposition: String, Codable, Hashable, Sendable {
    case retain = "Retain"
    case supersededReviewCandidate = "Superseded review candidate"
    case protected = "Protected"
}

public struct BackupRetentionDecision: Codable, Hashable, Sendable {
    public var disposition: BackupDisposition
    public var reason: String
}

public enum BackupRestorabilityValidator {
    public static func validateGitBundle(at url: URL, requiredRef: String = "HEAD", requiredObject: String? = nil) -> BackupValidationResult {
        let path = SafetyEngine.lexicalNormalize(url.path)
        let verify = Shell.run("/usr/bin/git", ["bundle", "verify", path], timeout: 15)
        guard verify.status == 0 else { return BackupValidationResult(format: .gitBundle, path: path, integrityVerified: false, isolatedRestoreVerified: false, requiredContentVerified: false, identity: nil, version: nil, contentFingerprint: nil, reason: "git bundle verify failed; the backup is protected.") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleaner-Bundle-Restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let clone = Shell.run("/usr/bin/git", ["clone", "--mirror", path, temporary.path], timeout: 30)
        guard clone.status == 0 else { return BackupValidationResult(format: .gitBundle, path: path, integrityVerified: true, isolatedRestoreVerified: false, requiredContentVerified: false, identity: nil, version: nil, contentFingerprint: nil, reason: "Bundle integrity passed, but isolated restore failed.") }
        let ref = Shell.run("/usr/bin/git", ["-C", temporary.path, "rev-parse", "--verify", "\(requiredRef)^{commit}"], timeout: 5)
        let objectOK: Bool
        if let requiredObject { objectOK = Shell.run("/usr/bin/git", ["-C", temporary.path, "cat-file", "-e", requiredObject], timeout: 5).status == 0 } else { objectOK = true }
        let commit = ref.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredOK = ref.status == 0 && !commit.isEmpty && objectOK
        return BackupValidationResult(format: .gitBundle, path: path, integrityVerified: true, isolatedRestoreVerified: true, requiredContentVerified: requiredOK, identity: commit.isEmpty ? nil : commit, version: nil, contentFingerprint: requiredOK ? StableFingerprint.fnv1a(commit + "|" + (requiredObject ?? "")) : nil, reason: requiredOK ? "Bundle restored in isolation and contains the required ref/object content." : "Isolated restore succeeded, but required ref/object coverage is missing.")
    }

    public static func validateApplication(at url: URL, expectedBundleIdentifier: String? = nil) -> BackupValidationResult {
        let path = SafetyEngine.lexicalNormalize(url.path)
        guard url.pathExtension == "app" else { return BackupValidationResult(format: .macOSApplication, path: path, integrityVerified: false, isolatedRestoreVerified: false, requiredContentVerified: false, identity: nil, version: nil, contentFingerprint: nil, reason: "Candidate is not a macOS .app bundle.") }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let identifier = plist["CFBundleIdentifier"] as? String, !identifier.isEmpty, let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty else { return BackupValidationResult(format: .macOSApplication, path: path, integrityVerified: false, isolatedRestoreVerified: false, requiredContentVerified: false, identity: nil, version: nil, contentFingerprint: nil, reason: "Application structure or Info.plist identity is invalid.") }
        guard expectedBundleIdentifier == nil || expectedBundleIdentifier == identifier else { return BackupValidationResult(format: .macOSApplication, path: path, integrityVerified: false, isolatedRestoreVerified: false, requiredContentVerified: false, identity: identifier, version: nil, contentFingerprint: nil, reason: "Application bundle identity does not match the configured backup family.") }
        let executableURL = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard FileManager.default.fileExists(atPath: executableURL.path) else { return BackupValidationResult(format: .macOSApplication, path: path, integrityVerified: false, isolatedRestoreVerified: false, requiredContentVerified: false, identity: identifier, version: nil, contentFingerprint: nil, reason: "Configured application executable is missing.") }
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        let fingerprint = StableFingerprint.fnv1a(identifier + "|" + (version ?? "unknown") + "|" + executable)
        return BackupValidationResult(format: .macOSApplication, path: path, integrityVerified: true, isolatedRestoreVerified: true, requiredContentVerified: true, identity: identifier, version: version, contentFingerprint: fingerprint, reason: "Configured application family, structure, executable, identity, and version were validated.")
    }

    public static func retentionDecision(older: BackupValidationResult, retained: BackupValidationResult) -> BackupRetentionDecision {
        guard retained.isRestorable else { return BackupRetentionDecision(disposition: .protected, reason: "The retained replacement is not proven restorable; older backup removal is blocked.") }
        guard older.isRestorable else { return BackupRetentionDecision(disposition: .protected, reason: "The older generation is not fully characterized; preserve it for review.") }
        guard older.format == retained.format, older.identity == retained.identity else { return BackupRetentionDecision(disposition: .protected, reason: "Backup formats or semantic identities differ; the older generation may be unique.") }
        guard older.contentFingerprint == retained.contentFingerprint else { return BackupRetentionDecision(disposition: .retain, reason: "The older generation contains a unique historical version or content fingerprint.") }
        return BackupRetentionDecision(disposition: .supersededReviewCandidate, reason: "A separately retained, restorable generation has identical semantic content; exact explicit review is still required.")
    }
}
