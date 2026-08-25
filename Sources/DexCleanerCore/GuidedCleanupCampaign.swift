import Foundation

public enum CampaignDomain: String, Codable, CaseIterable, Hashable, Sendable {
    case manifest = "Exact manifest caches"
    case projects = "Generated project artifacts"
    case homebrew = "Homebrew staging"
    case managed = "System and cloud managed resources"
    case backups = "Backups and rollback generations"
    case duplicates = "Exact duplicates"
    case capabilities = "Models, SDKs, environments, and toolchains"
}

public struct CampaignDomainSummary: Codable, Hashable, Sendable {
    public var domain: CampaignDomain
    public var completeness: ScanCompleteness
    public var findingCount: Int
    public var actionableCount: Int
    public var detail: String
}

public struct GuidedCampaignResult: Sendable {
    public var campaignID: UUID
    public var scanID: UUID
    public var snapshot: ScanSnapshot
    public var domains: [CampaignDomainSummary]
    public var progress: CampaignProgressSnapshot
    public var stopRecommendation: StopRecommendation
}

public struct GuidedCleanupCampaign {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = SafetyEngine.lexicalNormalize(home)
    }

    public func run(campaignID: UUID = UUID(), excludedLargeFileRelativePaths: [String] = [], isCancelled: @Sendable () -> Bool = { false }) -> GuidedCampaignResult {
        let started = Date()
        var snapshot = DiskScanner(home: home, excludedLargeFileRelativePaths: excludedLargeFileRelativePaths).scan()
        var domains: [CampaignDomainSummary] = [
            CampaignDomainSummary(domain: .manifest, completeness: snapshot.completeness, findingCount: snapshot.items.count, actionableCount: snapshot.items.filter(\.isCleanable).count, detail: "Existing exact-manifest and read-only storage scan completed without selecting anything.")
        ]

        var projectFindings: [ProjectArtifactFinding] = []
        var projectIssues: [ScanIssue] = []
        var projectStates: [ScanCompleteness] = []
        for relative in ["Projects", "Developer", "src"] {
            if isCancelled() { break }
            let root = URL(fileURLWithPath: home).appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let result = ProjectArtifactAnalyzer(home: home).scan(root: root, allowCleanup: true, isCancelled: isCancelled)
            projectFindings.append(contentsOf: result.findings)
            projectIssues.append(contentsOf: result.issues)
            projectStates.append(result.completeness)
        }
        snapshot.items.append(contentsOf: projectFindings.map(\.scanItem))
        snapshot.issues.append(contentsOf: projectIssues)
        let projectCompleteness: ScanCompleteness = isCancelled() ? .cancelled : (projectStates.contains(.partial) ? .partial : (projectStates.contains(.failed) ? .failed : .complete))
        domains.append(CampaignDomainSummary(domain: .projects, completeness: projectCompleteness, findingCount: projectFindings.count, actionableCount: projectFindings.filter { $0.disposition == .actionable }.count, detail: "Only proven ignored/untracked Node node_modules and Rust target directories under dedicated project roots can become actionable."))

        let capabilitySpecs: [(String, CapabilityEcosystem, CapabilityRole)] = [
            (".gradle", .gradle, .globalCache),
            ("Library/Developer/Xcode/Archives", .xcode, .installedCapability),
            (".konan", .kotlinNative, .installedCapability),
            (".pyenv", .python, .installedCapability),
            (".ollama/models/blobs", .aiModel, .sharedBlobStore)
        ]
        var capabilityFindings: [CapabilityFinding] = []
        for (relative, ecosystem, role) in capabilitySpecs {
            let path = URL(fileURLWithPath: home).appendingPathComponent(relative).path
            if FileManager.default.fileExists(atPath: path) { capabilityFindings.append(CapabilityClassifier.classify(path: path, ecosystem: ecosystem, role: role)) }
        }
        snapshot.items.append(contentsOf: capabilityFindings.map(\.scanItem))
        domains.append(CampaignDomainSummary(domain: .capabilities, completeness: .complete, findingCount: capabilityFindings.count, actionableCount: 0, detail: "Installed/default/project-required capabilities and shared model blobs remain protected or review-only."))
        domains.append(CampaignDomainSummary(domain: .managed, completeness: .complete, findingCount: snapshot.items.filter { ManagedResourceClassifier.classify(path: $0.path).kind != .unmanaged }.count, actionableCount: 0, detail: "Typed FileProvider, cloud, and system ownership is a mandatory refusal layer."))
        domains.append(CampaignDomainSummary(domain: .homebrew, completeness: .partial, findingCount: 0, actionableCount: 0, detail: "Dedicated staging cleanup requires an exact verified Homebrew layout. Unsupported or unavailable layouts remain unknown; broad Homebrew roots are never inferred."))
        domains.append(CampaignDomainSummary(domain: .backups, completeness: .partial, findingCount: 0, actionableCount: 0, detail: "Backup pruning requires an explicitly configured family and format-specific isolated restore proof; no broad backup traversal was attempted."))
        domains.append(CampaignDomainSummary(domain: .duplicates, completeness: .partial, findingCount: 0, actionableCount: 0, detail: "Duplicate analysis requires an explicit bounded user-selected scope and remains review-only without semantic authority."))

        snapshot.items = CleanupCampaignEvaluator.reranked(snapshot.items).map { item in
            var copy = item
            copy.isSelected = false
            return copy
        }
        if isCancelled() {
            snapshot.completeness = .cancelled
            snapshot.issues.append(ScanIssue(kind: .cancellation, area: "Guided cleanup campaign", detail: "Campaign scan was cancelled; partial findings remain non-selected."))
        } else if domains.contains(where: { $0.completeness == .failed }) {
            snapshot.completeness = .partial
        }
        snapshot.scanDurationSeconds = Date().timeIntervalSince(started)
        let stop = CleanupCampaignEvaluator.recommendation(items: snapshot.items)
        let progress = CampaignProgressSnapshot(phase: "Campaign audit", state: snapshot.completeness == .cancelled ? .cancelled : (snapshot.completeness == .failed ? .failed : .completed), candidatesConsidered: snapshot.items.count, filesExamined: snapshot.items.count, bytesExamined: snapshot.items.reduce(0) { $0 + $1.sizeBytes }, filesHashed: 0, bytesHashed: 0, partialResultCount: domains.filter { $0.completeness == .partial }.count, startedAt: started, heartbeatAt: Date())
        return GuidedCampaignResult(campaignID: campaignID, scanID: UUID(), snapshot: snapshot, domains: domains, progress: progress, stopRecommendation: stop)
    }
}
