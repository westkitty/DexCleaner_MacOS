import Foundation

public enum DuplicateSemanticRole: String, Codable, Hashable, Sendable {
    case authoritative = "Authoritative copy"
    case updaterCache = "Updater cache copy"
    case archive = "Archive copy"
    case historical = "Historical copy"
    case unknown = "Unknown role"
}

public struct DuplicateObject: Codable, Hashable, Sendable {
    public var physicalIdentity: String
    public var paths: [String]
    public var logicalBytes: Int64
    public var digest: String
    public var role: DuplicateSemanticRole
}

public struct ExactDuplicateSet: Codable, Hashable, Sendable {
    public var digest: String
    public var logicalBytesPerObject: Int64
    public var objects: [DuplicateObject]
    public var reviewOnly: Bool
    public var physicalReclaimBytes: Int64?
    public var explanation: String
}

public struct DuplicateAnalysisResult: Codable, Sendable {
    public var sets: [ExactDuplicateSet]
    public var completeness: ScanCompleteness
    public var filesExamined: Int
    public var filesHashed: Int
    public var bytesHashed: Int64
    public var aliasesCollapsed: Int
    public var issues: [ScanIssue]
}

public struct ExactDuplicateAnalyzer {
    public var maximumFiles: Int
    public var maximumBytesHashed: Int64
    public var minimumFileBytes: Int64

    public init(maximumFiles: Int = 5_000, maximumBytesHashed: Int64 = 10 * 1_024 * 1_024 * 1_024, minimumFileBytes: Int64 = 1) {
        self.maximumFiles = maximumFiles
        self.maximumBytesHashed = maximumBytesHashed
        self.minimumFileBytes = minimumFileBytes
    }

    public func analyze(files: [URL], scopeRoot: URL, semanticRoles: [String: DuplicateSemanticRole] = [:], isCancelled: @Sendable () -> Bool = { false }) -> DuplicateAnalysisResult {
        let root = SafetyEngine.lexicalNormalize(scopeRoot.path)
        var issues: [ScanIssue] = []
        var examined = 0
        var hashed = 0
        var bytesHashed: Int64 = 0
        var aliases = 0
        var limited = false
        var cancelled = false
        var bySize: [Int64: [(URL, FileIdentity)]] = [:]
        for url in files.prefix(maximumFiles + 1) {
            if isCancelled() { cancelled = true; break }
            if examined >= maximumFiles { limited = true; break }
            let path = SafetyEngine.lexicalNormalize(url.path)
            guard path.hasPrefix(root + "/"), let identity = FileIdentity.capture(path: path), identity.fileType == FileAttributeType.typeRegular.rawValue, identity.sizeBytes >= minimumFileBytes else { continue }
            examined += 1
            bySize[identity.sizeBytes, default: []].append((url, identity))
        }
        var objectsByDigest: [String: [DuplicateObject]] = [:]
        for (size, entries) in bySize where entries.count > 1 {
            var physical: [String: (identity: FileIdentity, paths: [String])] = [:]
            for (url, identity) in entries {
                let normalizedPath = SafetyEngine.lexicalNormalize(url.path)
                let key: String
                if let system = identity.systemNumber, let file = identity.fileNumber {
                    key = "\(system):\(file)"
                } else {
                    key = "identity-unavailable:\(normalizedPath)"
                }
                if physical[key] != nil { aliases += 1 }
                physical[key, default: (identity, [])].paths.append(normalizedPath)
            }
            guard physical.count > 1 else { continue }
            for (key, value) in physical {
                if isCancelled() { cancelled = true; break }
                guard bytesHashed + size <= maximumBytesHashed else { limited = true; break }
                let path = value.paths[0]
                guard let digest = digest(path: path) else { issues.append(ScanIssue(kind: .measurement, area: path, detail: "Exact content digest failed.")); continue }
                hashed += 1
                bytesHashed += size
                let role = semanticRoles[path] ?? .unknown
                objectsByDigest[digest, default: []].append(DuplicateObject(physicalIdentity: key, paths: value.paths.sorted(), logicalBytes: size, digest: digest, role: role))
            }
            if cancelled || limited { break }
        }
        let sets = objectsByDigest.compactMap { digest, objects -> ExactDuplicateSet? in
            guard objects.count > 1 else { return nil }
            let hasAuthority = objects.contains { $0.role == .authoritative }
            let hasUpdater = objects.contains { $0.role == .updaterCache }
            let explanation = hasAuthority && hasUpdater ? "Content equality is proven and semantic roles distinguish an authoritative copy from an updater cache; disposal still requires a dedicated action adapter." : "Content equality is proven, but equal bytes do not establish which semantic copy is disposable."
            return ExactDuplicateSet(digest: digest, logicalBytesPerObject: objects[0].logicalBytes, objects: objects.sorted { $0.paths[0] < $1.paths[0] }, reviewOnly: true, physicalReclaimBytes: nil, explanation: explanation)
        }.sorted { $0.logicalBytesPerObject > $1.logicalBytesPerObject }
        if limited { issues.append(ScanIssue(kind: .measurement, area: root, detail: "Duplicate analysis reached its configured file or hashing bound.")) }
        if cancelled { issues.append(ScanIssue(kind: .cancellation, area: root, detail: "Duplicate analysis was cancelled; partial review-only results were retained.")) }
        return DuplicateAnalysisResult(sets: sets, completeness: cancelled ? .cancelled : (limited ? .partial : .complete), filesExamined: examined, filesHashed: hashed, bytesHashed: bytesHashed, aliasesCollapsed: aliases, issues: issues)
    }

    private func digest(path: String) -> String? {
        let candidates = [("/usr/bin/shasum", ["-a", "256", path]), ("/usr/bin/sha256sum", [path])]
        for (executable, arguments) in candidates where FileManager.default.isExecutableFile(atPath: executable) {
            let result = Shell.run(executable, arguments, timeout: 30)
            if result.status == 0, let token = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first { return String(token) }
        }
        return nil
    }
}
