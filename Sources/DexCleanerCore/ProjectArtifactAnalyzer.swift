import Foundation

public enum ProjectEcosystem: String, Codable, Hashable, Sendable {
    case node = "Node"
    case rust = "Rust"
    case generic = "Generic"
}

public enum ProjectArtifactKind: String, Codable, Hashable, Sendable {
    case nodeModules = "node_modules"
    case rustTarget = "target"
    case genericBuild = "build"
    case genericDist = "dist"

    var ruleID: String {
        switch self {
        case .nodeModules: return "project.node.node_modules"
        case .rustTarget: return "project.rust.target"
        case .genericBuild: return "project.generic.build"
        case .genericDist: return "project.generic.dist"
        }
    }

    var supportsCleanup: Bool { self == .nodeModules || self == .rustTarget }
}

public enum ProjectArtifactDisposition: String, Codable, Hashable, Sendable {
    case actionable = "Actionable"
    case review = "Review required"
    case protected = "Protected"
    case unknown = "Unknown"
}

public struct ProjectArtifactFinding: Codable, Hashable, Sendable {
    public var path: String
    public var workspaceRoot: String?
    public var gitRoot: String?
    public var ecosystem: ProjectEcosystem
    public var kind: ProjectArtifactKind
    public var disposition: ProjectArtifactDisposition
    public var logicalBytes: Int64?
    public var allocatedBytes: Int64?
    public var reason: String
    public var evidence: CandidateEvidenceBundle?

    public var scanItem: ScanItem {
        let actionable = disposition == .actionable && evidence?.isActionable == true
        return ScanItem(
            manifestID: evidence?.candidateID,
            path: path,
            displayName: "\(ecosystem.rawValue) \(kind.rawValue)",
            group: "Project artifacts",
            category: .developerCache,
            risk: actionable ? .safe : .auditOnly,
            sizeBytes: logicalBytes ?? 0,
            explanation: reason,
            recoveryNote: ecosystem == .node ? "Restore dependencies with the workspace package manager." : (ecosystem == .rust ? "Rebuild the Rust workspace with Cargo." : "Generic build outputs remain review-only."),
            action: actionable ? .moveToTrash : .auditOnly,
            isSelected: false,
            measuredAt: Date(),
            measurementSource: logicalBytes == nil ? .notMeasured : .fresh,
            owningProcessRunning: false,
            evidence: evidence
        )
    }
}

public struct ProjectArtifactScanResult: Codable, Sendable {
    public var findings: [ProjectArtifactFinding]
    public var completeness: ScanCompleteness
    public var directoriesVisited: Int
    public var issues: [ScanIssue]

    public init(findings: [ProjectArtifactFinding], completeness: ScanCompleteness, directoriesVisited: Int, issues: [ScanIssue]) {
        self.findings = findings
        self.completeness = completeness
        self.directoriesVisited = directoriesVisited
        self.issues = issues
    }
}

public struct ProjectArtifactScanLimits: Sendable {
    public var maximumDepth: Int
    public var maximumDirectories: Int
    public var maximumArtifacts: Int
    public var maximumMeasuredEntries: Int
    public var deadlineSeconds: TimeInterval

    public init(maximumDepth: Int = 8, maximumDirectories: Int = 5_000, maximumArtifacts: Int = 500, maximumMeasuredEntries: Int = 100_000, deadlineSeconds: TimeInterval = 30) {
        self.maximumDepth = maximumDepth
        self.maximumDirectories = maximumDirectories
        self.maximumArtifacts = maximumArtifacts
        self.maximumMeasuredEntries = maximumMeasuredEntries
        self.deadlineSeconds = deadlineSeconds
    }
}

public struct ProjectArtifactAnalyzer {
    public static let adapterVersion = "1.0.0"
    public static let adapterChecksum = StableFingerprint.fnv1a("project-artifact-adapter|node_modules|rust-target|git-ignored|git-untracked|workspace-authority|no-symlinks|bounded-measurement|v1")

    public let home: String
    public let limits: ProjectArtifactScanLimits

    public init(home: String = NSHomeDirectory(), limits: ProjectArtifactScanLimits = ProjectArtifactScanLimits()) {
        self.home = SafetyEngine.lexicalNormalize(home)
        self.limits = limits
    }

    public func scan(
        root: URL,
        allowCleanup: Bool = false,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> ProjectArtifactScanResult {
        let normalizedRoot = SafetyEngine.lexicalNormalize(root.path)
        guard normalizedRoot == home || normalizedRoot.hasPrefix(home + "/") else {
            return ProjectArtifactScanResult(findings: [], completeness: .failed, directoriesVisited: 0, issues: [ScanIssue(kind: .filesystem, area: "Project artifact discovery", detail: "Discovery root is outside the current user's home.")])
        }
        let started = Date()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else {
            return ProjectArtifactScanResult(findings: [], completeness: .failed, directoriesVisited: 0, issues: [ScanIssue(kind: .filesystem, area: normalizedRoot, detail: "Project discovery could not enumerate the requested root.")])
        }

        var findings: [ProjectArtifactFinding] = []
        var issues: [ScanIssue] = []
        var directoriesVisited = 0
        var limited = false
        var cancelled = false

        while let url = enumerator.nextObject() as? URL {
            if isCancelled() {
                cancelled = true
                enumerator.skipDescendants()
                break
            }
            if Date().timeIntervalSince(started) > limits.deadlineSeconds {
                limited = true
                issues.append(ScanIssue(kind: .timeout, area: normalizedRoot, detail: "Project discovery reached its \(limits.deadlineSeconds)-second deadline."))
                enumerator.skipDescendants()
                break
            }
            let depth = url.pathComponents.count - root.pathComponents.count
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.name ?? url.lastPathComponent
            if values?.isSymbolicLink == true {
                if let kind = artifactKind(for: name) {
                    findings.append(refusedFinding(path: url.path, kind: kind, reason: "Symlinked project artifacts never receive cleanup authority."))
                }
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true else { continue }
            directoriesVisited += 1
            if depth > limits.maximumDepth || directoriesVisited > limits.maximumDirectories {
                limited = true
                enumerator.skipDescendants()
                continue
            }
            if shouldPrune(name: name) {
                enumerator.skipDescendants()
                continue
            }
            guard let kind = artifactKind(for: name) else { continue }
            enumerator.skipDescendants()
            if findings.count >= limits.maximumArtifacts {
                limited = true
                issues.append(ScanIssue(kind: .measurement, area: normalizedRoot, detail: "Project artifact result limit was reached."))
                break
            }
            findings.append(analyzeCandidate(url: url, kind: kind, allowCleanup: allowCleanup, isCancelled: isCancelled))
        }

        if cancelled {
            issues.append(ScanIssue(kind: .cancellation, area: normalizedRoot, detail: "Project artifact discovery was cancelled; partial read-only findings were retained."))
        } else if limited && issues.isEmpty {
            issues.append(ScanIssue(kind: .measurement, area: normalizedRoot, detail: "Project discovery bounds limited coverage."))
        }
        let completeness: ScanCompleteness = cancelled ? .cancelled : (limited ? .partial : .complete)
        return ProjectArtifactScanResult(findings: findings, completeness: completeness, directoriesVisited: directoriesVisited, issues: issues)
    }

    public static func provenance(for kind: ProjectArtifactKind) -> RuleProvenance {
        RuleProvenance(ruleID: kind.ruleID, ruleVersion: adapterVersion, sourceKind: .dedicatedAdapter, sourceVersion: adapterVersion, sourceChecksum: adapterChecksum)
    }

    public static func validateAuthority(path: String, kind: ProjectArtifactKind, home: String) -> SafetyDecision {
        let normalizedPath = SafetyEngine.lexicalNormalize(path)
        let normalizedHome = SafetyEngine.lexicalNormalize(home)
        guard normalizedPath.hasPrefix(normalizedHome + "/") else { return SafetyDecision(allowed: false, reason: "Project artifact is outside the current user's home.") }
        let rootDecision = projectRootDecision(path: normalizedPath, home: normalizedHome)
        guard rootDecision.allowed else { return rootDecision }
        guard URL(fileURLWithPath: normalizedPath).lastPathComponent == kind.rawValue else { return SafetyDecision(allowed: false, reason: "Project artifact basename does not match its adapter rule.") }
        guard !SafetyEngine.containsSymlinkComponent(path: normalizedPath, home: normalizedHome) else { return SafetyDecision(allowed: false, reason: "Project artifact or an ancestor is a symlink.") }
        guard !normalizedPath.split(separator: "/").contains(where: { [".git", ".hg", ".svn"].contains(String($0)) }) else { return SafetyDecision(allowed: false, reason: "Repository metadata is protected.") }

        let candidate = URL(fileURLWithPath: normalizedPath)
        let workspace = candidate.deletingLastPathComponent()
        guard workspaceAuthority(kind: kind, workspace: workspace) else { return SafetyDecision(allowed: false, reason: "Recognized workspace authority is missing or invalid.") }
        guard let gitRoot = gitRoot(for: workspace), normalizedPath.hasPrefix(gitRoot + "/") else { return SafetyDecision(allowed: false, reason: "A containing Git workspace could not be established.") }
        guard gitPathState(path: normalizedPath, gitRoot: gitRoot) == .ignoredUntracked else { return SafetyDecision(allowed: false, reason: "Project artifact is tracked, not ignored, or Git state is unavailable.") }
        return SafetyDecision(allowed: true, reason: "Dedicated adapter proved an exact ignored, untracked, rebuildable project artifact.")
    }

    private func analyzeCandidate(url: URL, kind: ProjectArtifactKind, allowCleanup: Bool, isCancelled: @Sendable () -> Bool) -> ProjectArtifactFinding {
        let workspace = url.deletingLastPathComponent()
        guard Self.workspaceAuthority(kind: kind, workspace: workspace) else {
            return refusedFinding(path: url.path, kind: kind, reason: "Artifact name matched, but recognized workspace authority is missing or invalid.")
        }
        guard let gitRoot = Self.gitRoot(for: workspace) else {
            return refusedFinding(path: url.path, kind: kind, workspace: workspace.path, reason: "Workspace exists, but Git ownership and tracked/ignored state are unavailable.")
        }
        let gitState = Self.gitPathState(path: url.path, gitRoot: gitRoot)
        guard gitState == .ignoredUntracked else {
            let reason = gitState == .tracked ? "Artifact is tracked by Git and is protected." : "Artifact is not ignored or Git state is unavailable."
            return refusedFinding(path: url.path, kind: kind, workspace: workspace.path, gitRoot: gitRoot, disposition: gitState == .tracked ? .protected : .review, reason: reason)
        }
        let measurement = measure(url: url, isCancelled: isCancelled)
        guard measurement.complete else {
            return ProjectArtifactFinding(path: url.path, workspaceRoot: workspace.path, gitRoot: gitRoot, ecosystem: ecosystem(for: kind), kind: kind, disposition: .unknown, logicalBytes: measurement.logical, allocatedBytes: measurement.allocated, reason: measurement.reason, evidence: nil)
        }
        guard let identity = FileIdentity.capture(path: url.path) else {
            return refusedFinding(path: url.path, kind: kind, workspace: workspace.path, gitRoot: gitRoot, disposition: .unknown, reason: "Filesystem identity could not be captured.")
        }
        let candidateID = "adapter:\(kind.ruleID):\(StableFingerprint.fnv1a(SafetyEngine.lexicalNormalize(url.path)))"
        let observed = Date()
        let adapterDecision = Self.projectRootDecision(path: url.path, home: home)
        let cleanupEnabled = allowCleanup && kind.supportsCleanup && adapterDecision.allowed
        let protection: ProtectionDecision = cleanupEnabled ? .actionable : .review
        let evidence = CandidateEvidenceBundle(
            candidateID: candidateID,
            path: url.path,
            identity: identity,
            ownership: .userScoped,
            protection: protection,
            rebuildability: kind.supportsCleanup ? .proven : .unknown,
            risk: cleanupEnabled ? .safe : .auditOnly,
            records: [
                CandidateEvidenceRecord(kind: .identity, source: "FileManager attributes", observedAt: observed, completeness: .complete, detail: "Captured physical identity for the exact artifact directory."),
                CandidateEvidenceRecord(kind: .authority, source: kind == .nodeModules ? "package.json" : "Cargo.toml", observedAt: observed, completeness: .complete, detail: "Recognized \(ecosystem(for: kind).rawValue) workspace authority at \(workspace.path)."),
                CandidateEvidenceRecord(kind: .ownership, source: "Git", observedAt: observed, completeness: .complete, detail: "Containing Git root: \(gitRoot)."),
                CandidateEvidenceRecord(kind: .protection, source: "Git", observedAt: observed, completeness: .complete, detail: "Exact artifact is ignored and untracked; repository metadata was not traversed."),
                CandidateEvidenceRecord(kind: .rebuildability, source: "Dedicated project adapter", observedAt: observed, completeness: .complete, detail: kind == .nodeModules ? "Workspace dependency installation can recreate node_modules." : (kind == .rustTarget ? "Cargo can rebuild the default target directory." : "Generic build output semantics are not sufficient for cleanup authority.")),
                CandidateEvidenceRecord(kind: .measurement, source: "Bounded filesystem enumeration", observedAt: observed, completeness: .complete, detail: "Logical \(measurement.logical ?? 0) bytes; allocated \(measurement.allocated ?? 0) bytes.")
            ],
            provenance: Self.provenance(for: kind)
        )
        let disposition: ProjectArtifactDisposition = cleanupEnabled && evidence.isActionable ? .actionable : .review
        let reason = disposition == .actionable ? "Proven generated project artifact. Exact preview and final preflight are still required." : (kind.supportsCleanup ? (allowCleanup && !adapterDecision.allowed ? adapterDecision.reason : (cleanupEnabled ? "Cleanup evidence failed closed: \(evidence.actionabilityProblems.joined(separator: ", "))." : "Evidence is complete, but this discovery run is read-only.")) : "Generic build and dist outputs remain review-only because ecosystem-specific rebuildability is not proven.")
        return ProjectArtifactFinding(path: url.path, workspaceRoot: workspace.path, gitRoot: gitRoot, ecosystem: ecosystem(for: kind), kind: kind, disposition: disposition, logicalBytes: measurement.logical, allocatedBytes: measurement.allocated, reason: reason, evidence: evidence)
    }

    private func measure(url: URL, isCancelled: @Sendable () -> Bool) -> (logical: Int64?, allocated: Int64?, complete: Bool, reason: String) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else { return (nil, nil, false, "Artifact measurement could not start.") }
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var entries = 0
        while let child = enumerator.nextObject() as? URL {
            if isCancelled() { return (logical, allocated, false, "Artifact measurement was cancelled.") }
            entries += 1
            if entries > limits.maximumMeasuredEntries { return (logical, allocated, false, "Artifact measurement reached its entry bound.") }
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { return (logical, allocated, false, "Artifact measurement encountered unreadable state.") }
            if values.isSymbolicLink == true { return (logical, allocated, false, "Artifact contains a symlink and remains review-only.") }
            if values.isRegularFile == true {
                logical += Int64(values.fileSize ?? 0)
                allocated += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return (logical, allocated, true, "Complete bounded measurement.")
    }

    private func refusedFinding(path: String, kind: ProjectArtifactKind, workspace: String? = nil, gitRoot: String? = nil, disposition: ProjectArtifactDisposition = .review, reason: String) -> ProjectArtifactFinding {
        ProjectArtifactFinding(path: path, workspaceRoot: workspace, gitRoot: gitRoot, ecosystem: ecosystem(for: kind), kind: kind, disposition: disposition, logicalBytes: nil, allocatedBytes: nil, reason: reason, evidence: nil)
    }

    private func ecosystem(for kind: ProjectArtifactKind) -> ProjectEcosystem {
        switch kind {
        case .nodeModules: return .node
        case .rustTarget: return .rust
        case .genericBuild, .genericDist: return .generic
        }
    }

    private func artifactKind(for name: String) -> ProjectArtifactKind? {
        ProjectArtifactKind(rawValue: name)
    }

    private func shouldPrune(name: String) -> Bool {
        [".git", ".hg", ".svn", ".build", ".swiftpm", "DerivedData"].contains(name) || (name.hasPrefix(".") && name != ".")
    }

    private enum GitPathState { case ignoredUntracked, tracked, unavailable }

    private static func workspaceAuthority(kind: ProjectArtifactKind, workspace: URL) -> Bool {
        switch kind {
        case .nodeModules:
            let manifest = workspace.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: manifest),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return ["name", "workspaces", "packageManager", "dependencies", "devDependencies"].contains { object[$0] != nil }
        case .rustTarget:
            let manifest = workspace.appendingPathComponent("Cargo.toml")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
            return text.contains("[package]") || text.contains("[workspace]")
        case .genericBuild, .genericDist:
            let package = workspace.appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: package),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               !object.isEmpty { return true }
            let cargo = workspace.appendingPathComponent("Cargo.toml")
            guard let text = try? String(contentsOf: cargo, encoding: .utf8) else { return false }
            return text.contains("[package]") || text.contains("[workspace]")
        }
    }

    private static func gitRoot(for workspace: URL) -> String? {
        let result = Shell.run("/usr/bin/git", ["-C", workspace.path, "rev-parse", "--show-toplevel"], timeout: 3)
        guard result.status == 0 else { return nil }
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : SafetyEngine.lexicalNormalize(root)
    }

    private static func projectRootDecision(path: String, home: String) -> SafetyDecision {
        let normalizedPath = SafetyEngine.lexicalNormalize(path)
        let normalizedHome = SafetyEngine.lexicalNormalize(home)
        let allowedRoots = ["Projects", "Developer", "src"].map { normalizedHome + "/" + $0 }
        guard allowedRoots.contains(where: { normalizedPath.hasPrefix($0 + "/") }) else {
            return SafetyDecision(allowed: false, reason: "Project artifact is outside the dedicated project roots.")
        }
        return SafetyDecision(allowed: true, reason: "Project artifact is inside a dedicated project root.")
    }

    private static func gitPathState(path: String, gitRoot: String) -> GitPathState {
        let physicalPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        let physicalRoot = URL(fileURLWithPath: gitRoot).resolvingSymlinksInPath().standardizedFileURL.path
        let relativePrefix = physicalRoot.hasSuffix("/") ? physicalRoot : physicalRoot + "/"
        guard physicalPath.hasPrefix(relativePrefix) else { return .unavailable }
        let relative = String(physicalPath.dropFirst(relativePrefix.count))
        let tracked = Shell.run("/usr/bin/git", ["-C", physicalRoot, "ls-files", "--", relative], timeout: 3)
        if tracked.status == 0 && !tracked.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .tracked }
        let ignored = Shell.run("/usr/bin/git", ["-C", physicalRoot, "check-ignore", "-q", "--", relative], timeout: 3)
        return ignored.status == 0 ? .ignoredUntracked : .unavailable
    }
}

public enum ProjectArtifactSafetyAdapter {
    public static func decision(for item: ScanItem, home: String) -> SafetyDecision {
        guard let evidence = item.evidence,
              evidence.provenance.sourceKind == .dedicatedAdapter,
              evidence.isActionable,
              evidence.candidateID == item.manifestID,
              evidence.risk == item.risk,
              evidence.path == item.path,
              let kind = kind(forRuleID: evidence.provenance.ruleID),
              evidence.provenance == ProjectArtifactAnalyzer.provenance(for: kind) else {
            return SafetyDecision(allowed: false, reason: "Dedicated project evidence is missing, incomplete, or stale.")
        }
        return ProjectArtifactAnalyzer.validateAuthority(path: item.path, kind: kind, home: home)
    }

    public static func decision(for item: CleanupPlanItem, home: String) -> SafetyDecision {
        guard let evidence = item.evidence,
              evidence.provenance.sourceKind == .dedicatedAdapter,
              evidence.isActionable,
              evidence.candidateID == item.manifestID,
              evidence.identity == item.identity,
              evidence.path == item.path,
              let kind = kind(forRuleID: evidence.provenance.ruleID),
              evidence.provenance == ProjectArtifactAnalyzer.provenance(for: kind) else {
            return SafetyDecision(allowed: false, reason: "Previewed project evidence is missing, incomplete, or stale.")
        }
        return ProjectArtifactAnalyzer.validateAuthority(path: item.path, kind: kind, home: home)
    }

    private static func kind(forRuleID ruleID: String) -> ProjectArtifactKind? {
        ProjectArtifactKind.allCases.first { $0.ruleID == ruleID }
    }
}

private extension ProjectArtifactKind {
    static var allCases: [ProjectArtifactKind] { [.nodeModules, .rustTarget, .genericBuild, .genericDist] }
}
