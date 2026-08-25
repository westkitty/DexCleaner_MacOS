import Foundation

public struct DiskScanner {
    public static let mandatoryExcludedLargeFileRelativePaths = [
        "Library", ".Trash", ".cache", ".git", "Projects", "Developer", "Applications",
        "Documents", "Downloads", "Desktop", "Movies", "Pictures",
        "Dropbox", "OneDrive", "Google Drive"
    ]

    public let home: String
    public let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    public let excludedLargeFileRelativePaths: [String]
    private let cache: ScanCache

    public init(
        home: String = NSHomeDirectory(),
        cache: ScanCache? = nil,
        excludedLargeFileRelativePaths: [String] = []
    ) {
        self.home = SafetyEngine.lexicalNormalize(home)
        self.cache = cache ?? ScanCache(home: home)
        let additions = excludedLargeFileRelativePaths.compactMap(ManifestValidator.canonicalRelativePath)
        self.excludedLargeFileRelativePaths = Array(Set(Self.mandatoryExcludedLargeFileRelativePaths + additions)).sorted()
    }

    public func scan() -> ScanSnapshot {
        let started = Date()
        var items: [ScanItem] = []
        var issues: [ScanIssue] = []
        var warnings: [String] = []

        let status = diskStatus(issues: &issues)
        switch status.state {
        case .disputed:
            issues.append(ScanIssue(kind: .measurement, area: "Storage capacity", detail: status.detail))
        case .partial:
            issues.append(ScanIssue(kind: .filesystem, area: "Storage capacity", detail: status.detail))
        case .failed:
            issues.append(ScanIssue(kind: .commandFailure, area: "Storage capacity", detail: status.detail))
        case .fresh, .cached:
            break
        }
        if !CleanupCatalog.isAvailable {
            let detail = CleanupCatalog.validationErrors.joined(separator: " ")
            issues.append(ScanIssue(kind: .manifest, area: "Cleanup authority", detail: detail))
            warnings.append("Cleanup is disabled because the bundled manifest is unavailable or invalid.")
        } else {
            for entry in CleanupCatalog.cleanableEntries where !currentTaskIsCancelled {
                if let item = scanCatalogEntry(entry, issues: &issues) { items.append(item) }
            }
        }

        if !currentTaskIsCancelled { items.append(contentsOf: builtInAuditTargets(issues: &issues)) }
        if !currentTaskIsCancelled { items.append(contentsOf: protectedPathMarkers()) }

        let diagnostics: [PermissionDiagnostic]
        if currentTaskIsCancelled {
            diagnostics = []
        } else {
            diagnostics = PermissionDiagnostics.evaluate(home: home)
            items.append(contentsOf: permissionDiagnosticItems(from: diagnostics))
            if diagnostics.contains(where: { $0.status == "Access limited" }) {
                issues.append(ScanIssue(kind: .permission, area: "Protected macOS folders", detail: "At least one protected sample folder could not be listed."))
            }
        }

        items.sort {
            if $0.action != $1.action { return $0.action == .moveToTrash }
            if $0.group != $1.group { return $0.group < $1.group }
            if $0.risk.sortRank != $1.risk.sortRank { return $0.risk.sortRank < $1.risk.sortRank }
            return $0.sizeBytes > $1.sizeBytes
        }
        cache.save()

        if currentTaskIsCancelled {
            issues.append(ScanIssue(kind: .cancellation, area: "Scan", detail: "The scan was cancelled before all areas completed."))
        }
        let hasUsableData = status.availableForWorkBytes != nil || items.contains(where: { $0.sizeBytes > 0 })
        let completeness = Self.determineCompleteness(
            cancelled: currentTaskIsCancelled,
            hasUsableData: hasUsableData,
            issues: issues
        )

        return ScanSnapshot(
            timestamp: Date(),
            diskStatus: status,
            items: items,
            storageSummaries: storageSummaries(from: items),
            permissionDiagnostics: diagnostics,
            warnings: warnings,
            issues: issues,
            completeness: completeness,
            scanDurationSeconds: Date().timeIntervalSince(started),
            policyVersion: CleanupCatalog.policyVersion,
            manifestChecksum: CleanupCatalog.manifestChecksum,
            appVersion: appVersion,
            accessStatus: PermissionDiagnostics.summary(diagnostics)
        )
    }

    public func scanCatalogEntry(_ entry: CatalogEntry, issues: inout [ScanIssue]) -> ScanItem? {
        let path = URL(fileURLWithPath: home).appendingPathComponent(entry.relativePath).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let measurement = measuredSize(path: path, timeout: 15, area: entry.displayName, issues: &issues) else { return nil }
        var item = ScanItem(
            manifestID: entry.id,
            path: path,
            displayName: entry.displayName,
            group: entry.group,
            category: entry.category,
            risk: entry.risk,
            sizeBytes: measurement.bytes,
            explanation: entry.explanation,
            recoveryNote: entry.recoveryNote,
            action: entry.action,
            isSelected: false,
            measuredAt: measurement.date,
            measurementSource: measurement.source,
            owningProcessRunning: ProcessDetector.owningProcessIsRunning(forGroup: entry.group)
        )
        let decision = SafetyEngine.decision(for: item, home: home)
        if !decision.allowed {
            item.risk = .forbidden
            item.action = .auditOnly
            item.explanation += " Cleanup blocked: \(decision.reason)"
            item.recoveryNote = "No cleanup action is available until the authority problem is corrected."
        } else if let identity = FileIdentity.capture(path: item.path) {
            item.evidence = CandidateEvidenceFactory.exactManifest(item: item, identity: identity, home: home, observedAt: measurement.date)
        }
        return item
    }

    public func diskStatus(issues: inout [ScanIssue]) -> DiskStatus {
        StorageCapacityProvider.measure()
    }

    public func gitTemporaryPackAuditItems(issues: inout [ScanIssue]) -> [ScanItem] {
        let roots = ["Projects", "Developer", "src", "go", "esp"].map { URL(fileURLWithPath: home).appendingPathComponent($0) }
        var found: [ScanItem] = []
        for root in roots where !currentTaskIsCancelled && FileManager.default.fileExists(atPath: root.path) {
            let result = Shell.run("/usr/bin/find", [root.path, "-path", "*/.git/objects/pack/tmp_pack_*", "-type", "f", "-mmin", "+60", "-print"], timeout: 20)
            recordCommandProblem(result, area: "Git temporary-pack audit at \(root.path)", issues: &issues)
            for rawLine in result.stdout.split(separator: "\n") where !currentTaskIsCancelled {
                let path = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty, let measurement = measuredSize(path: path, timeout: 5, area: "Git temporary-pack audit", issues: &issues) else { continue }
                found.append(ScanItem(
                    manifestID: "git-temporary-pack-audit",
                    path: path,
                    displayName: "Git temporary pack",
                    group: "Git",
                    category: .gitTemporaryPack,
                    risk: .auditOnly,
                    sizeBytes: measurement.bytes,
                    explanation: "Read-only finding inside .git/objects/pack. DexCleaner does not alter Git internals.",
                    recoveryNote: "Inspect repository state and use Git's own maintenance commands if intervention is required.",
                    action: .auditOnly,
                    isSelected: false,
                    measuredAt: measurement.date,
                    measurementSource: measurement.source
                ))
            }
        }
        return found
    }

    public func builtInAuditTargets(issues: inout [ScanIssue]) -> [ScanItem] {
        let definitions: [(String, String, String, CleanupCategory, RiskLevel, String, String)] = [
            ("xcode-derived-data-audit", "Library/Developer/Xcode/DerivedData", "Xcode DerivedData", .developerCache, .caution, "Large build artifacts. Audit only because rebuild cost and active project state must be considered.", "Review in Xcode or Finder. DexCleaner will not clean this broad build root."),
            ("cloud-storage-audit", "Library/CloudStorage", "Cloud storage root", .cloudStorage, .forbidden, "Cloud-backed files are protected from cleanup authority.", "Manage local copies through Finder or the cloud provider.")
        ]
        return definitions.compactMap { id, relativePath, name, category, risk, explanation, recovery in
            let path = URL(fileURLWithPath: home).appendingPathComponent(relativePath).path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return ScanItem(
                manifestID: id,
                path: path,
                displayName: name,
                group: category == .cloudStorage ? "Cloud Storage" : "Xcode",
                category: category,
                risk: risk,
                sizeBytes: 0,
                explanation: explanation,
                recoveryNote: recovery,
                action: .auditOnly,
                isSelected: false,
                measuredAt: nil,
                measurementSource: .notMeasured
            )
        }
    }

    public func protectedPathMarkers() -> [ScanItem] {
        let protectedRelativePaths = [
            (".cache", "Hidden cache root"), (".antigravity", "Antigravity state"),
            (".antigravity_archive", "Antigravity archive"),
            ("Library/Application Support/Antigravity", "Antigravity Application Support"),
            ("Library/Keychains", "Keychains"), ("Documents", "User Documents"),
            ("Downloads", "User Downloads"), ("Desktop", "Desktop"),
            ("Projects", "Project source trees"), ("Pictures", "Pictures"),
            ("Movies", "Movies"), ("Dropbox", "Dropbox"), ("OneDrive", "OneDrive"),
            ("Google Drive", "Google Drive")
        ]
        return protectedRelativePaths.compactMap { relativePath, label in
            let path = URL(fileURLWithPath: home).appendingPathComponent(relativePath).path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let cloud = ["Dropbox", "OneDrive", "Google Drive"].contains(relativePath)
            return ScanItem(
                manifestID: "protected-\(relativePath.replacingOccurrences(of: "/", with: "-"))",
                path: path,
                displayName: "Protected: \(label)",
                group: cloud ? "Cloud Storage" : "Protected User Data",
                category: cloud ? .cloudStorage : .protected,
                risk: .forbidden,
                sizeBytes: 0,
                explanation: "Presence marker only. This broad user or app-state path is never cleanup authority.",
                recoveryNote: "Review manually in Finder or the owning application.",
                action: .auditOnly,
                isSelected: false,
                measurementSource: .notMeasured
            )
        }
    }

    public func auditUsageItems(issues: inout [ScanIssue]) -> [ScanItem] {
        let roots: [(String, String, Int)] = [
            (home, "Home top-level usage", 20),
            (URL(fileURLWithPath: home).appendingPathComponent("Library").path, "Library top-level usage", 20),
            (URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support").path, "Application Support usage", 30)
        ]
        var findings: [ScanItem] = []
        for (rootPath, title, limit) in roots where !currentTaskIsCancelled {
            findings.append(contentsOf: auditChildren(rootPath: rootPath, title: title, limit: limit, issues: &issues))
        }
        return findings
    }

    public func auditChildren(rootPath: String, title: String, limit: Int, issues: inout [ScanIssue]) -> [ScanItem] {
        guard FileManager.default.fileExists(atPath: rootPath) else { return [] }
        let rootURL = URL(fileURLWithPath: rootPath)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsPackageDescendants])
        } catch {
            issues.append(ScanIssue(kind: .permission, area: title, detail: error.localizedDescription))
            return []
        }
        let minimumBytes: Int64 = 100 * 1024 * 1024
        var findings: [ScanItem] = []
        for url in urls where !currentTaskIsCancelled {
            if shouldSkipAuditChild(url, under: rootURL) { continue }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            guard let measurement = measuredSize(path: url.path, timeout: 8, area: "\(title): \(url.lastPathComponent)", issues: &issues), measurement.bytes >= minimumBytes else { continue }
            findings.append(ScanItem(
                manifestID: "storage-map",
                path: url.path,
                displayName: "\(title): \(url.lastPathComponent)",
                group: "Storage Map",
                category: .storageMap,
                risk: .auditOnly,
                sizeBytes: measurement.bytes,
                explanation: "Read-only size finding. This is not a cleanup candidate.",
                recoveryNote: "Use Reveal in Finder or the owning app. DexCleaner will not delete storage-map findings.",
                action: .auditOnly,
                isSelected: false,
                measuredAt: measurement.date,
                measurementSource: measurement.source
            ))
        }
        return Array(findings.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    public func largeFileAuditItems(issues: inout [ScanIssue]) -> [ScanItem] {
        var args = [home, "("]
        for (index, relative) in excludedLargeFileRelativePaths.enumerated() {
            if index > 0 { args.append("-o") }
            let path = URL(fileURLWithPath: home).appendingPathComponent(relative).path
            args.append(contentsOf: ["-path", path])
            args.append("-o")
            args.append(contentsOf: ["-path", path + "/*"])
        }
        args.append("-o")
        args.append(contentsOf: ["-path", "*/.git", "-o", "-path", "*/.git/*"])
        args.append(contentsOf: [")", "-prune", "-o", "-type", "f", "-size", "+500M", "-print0"])
        let result = Shell.run("/usr/bin/find", args, timeout: 30)
        recordCommandProblem(result, area: "Large-file audit", issues: &issues)
        let paths = result.stdout.split(separator: "\0").map(String.init).filter { !$0.isEmpty }
        var findings: [ScanItem] = []
        for path in paths.prefix(100) where !currentTaskIsCancelled {
            guard let measurement = measuredSize(path: path, timeout: 5, area: "Large file \(path)", issues: &issues) else { continue }
            findings.append(ScanItem(
                manifestID: "large-file-audit",
                path: path,
                displayName: "Large file: \(URL(fileURLWithPath: path).lastPathComponent)",
                group: "Large Files",
                category: .auditOnly,
                risk: .auditOnly,
                sizeBytes: measurement.bytes,
                explanation: "Read-only large-file finding outside default excluded roots.",
                recoveryNote: "Review manually and back up user content before deleting outside DexCleaner.",
                action: .auditOnly,
                isSelected: false,
                measuredAt: measurement.date,
                measurementSource: measurement.source
            ))
        }
        return Array(findings.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(30))
    }

    public func extensionBreakdownItems(from largeFiles: [ScanItem]) -> [ScanItem] {
        Dictionary(grouping: largeFiles) { item in
            let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
            return ext.isEmpty ? "no extension" : ".\(ext)"
        }.map { ext, items in
            ScanItem(
                manifestID: "extension-breakdown",
                path: "extension://\(ext)",
                displayName: "Large-file extension total: \(ext)",
                group: "Extension Breakdown",
                category: .extensionBreakdown,
                risk: .auditOnly,
                sizeBytes: items.reduce(0) { $0 + $1.sizeBytes },
                explanation: "Read-only summary based on the current large-file audit.",
                recoveryNote: "Inspect individual large-file findings. DexCleaner never deletes by extension.",
                action: .auditOnly,
                isSelected: false,
                measuredAt: Date(),
                measurementSource: .fresh
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public func permissionDiagnosticItems(from diagnostics: [PermissionDiagnostic]) -> [ScanItem] {
        diagnostics.map { diagnostic in
            ScanItem(
                manifestID: "permission-diagnostic",
                path: "permission://\(diagnostic.title)",
                displayName: diagnostic.title,
                group: "Access Checks",
                category: .permissionDiagnostic,
                risk: diagnostic.status == "Access limited" ? .caution : .auditOnly,
                sizeBytes: 0,
                explanation: "\(diagnostic.status): \(diagnostic.detail)",
                recoveryNote: diagnostic.remediation,
                action: .auditOnly,
                isSelected: false,
                measurementSource: .notMeasured
            )
        }
    }

    public func storageSummaries(from items: [ScanItem]) -> [StorageSummaryItem] {
        let cleanableBytes = items.filter { $0.isCleanable }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        var summaries = [
            StorageSummaryItem(label: "Cleanable exact targets", bytes: cleanableBytes, detail: "Non-overlapping exact manifest-authorized targets only.")
        ]
        let grouped = Dictionary(grouping: items.filter { $0.isCleanable && $0.sizeBytes > 0 }, by: { $0.group })
        summaries.append(contentsOf: grouped.map { group, groupItems in
            StorageSummaryItem(label: "Cleanable · \(group)", bytes: groupItems.reduce(0) { $0 + $1.sizeBytes }, detail: "Exact cleanable targets in this group.")
        }.sorted { $0.bytes > $1.bytes })
        return summaries
    }

    static func determineCompleteness(cancelled: Bool, hasUsableData: Bool, issues: [ScanIssue]) -> ScanCompleteness {
        if cancelled { return .cancelled }
        if !hasUsableData && !issues.isEmpty { return .failed }
        return issues.isEmpty ? .complete : .partial
    }

    private func shouldSkipAuditChild(_ url: URL, under rootURL: URL) -> Bool {
        let normalizedRoot = SafetyEngine.lexicalNormalize(rootURL.path)
        let normalizedHome = SafetyEngine.lexicalNormalize(home)
        let library = URL(fileURLWithPath: normalizedHome).appendingPathComponent("Library").path
        let applicationSupport = URL(fileURLWithPath: library).appendingPathComponent("Application Support").path

        let excludedNames: Set<String>
        switch normalizedRoot {
        case normalizedHome:
            excludedNames = [
                "Library", ".Trash", ".cache", ".git", "Projects", "Developer", "Applications",
                "Documents", "Downloads", "Desktop", "Movies", "Pictures",
                "Dropbox", "OneDrive", "Google Drive"
            ]
        case SafetyEngine.lexicalNormalize(library):
            excludedNames = ["CloudStorage", "Application Support", "Keychains", "Mail", "Messages", "Safari", "Developer"]
        case SafetyEngine.lexicalNormalize(applicationSupport):
            excludedNames = ["Antigravity", "BraveSoftware", "Google", "Claude"]
        default:
            excludedNames = []
        }
        return excludedNames.contains(url.lastPathComponent)
    }

    private struct Measurement {
        var bytes: Int64
        var date: Date
        var source: MeasurementSource
    }

    private func measuredSize(path: String, timeout: TimeInterval, area: String, issues: inout [ScanIssue]) -> Measurement? {
        if let cached = cache.cachedRecord(path: path) {
            return Measurement(bytes: cached.sizeBytes, date: cached.scannedAt, source: .cache)
        }
        let result = Shell.run("/usr/bin/du", ["-sk", path], timeout: timeout)
        recordCommandProblem(result, area: area, issues: &issues)
        guard result.status == 0 else { return nil }
        let first = result.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first
        guard let value = first, let kb = Int64(value) else {
            issues.append(ScanIssue(kind: .commandFailure, area: area, detail: "du output could not be parsed."))
            return nil
        }
        let date = Date()
        let bytes = kb * 1024
        cache.store(path: path, sizeBytes: bytes, scannedAt: date)
        return Measurement(bytes: bytes, date: date, source: .fresh)
    }

    private func recordCommandProblem(_ result: ShellResult, area: String, issues: inout [ScanIssue]) {
        if result.cancelled {
            issues.append(ScanIssue(kind: .cancellation, area: area, detail: "The command was cancelled."))
        } else if result.timedOut {
            issues.append(ScanIssue(kind: .timeout, area: area, detail: "The command exceeded its time limit."))
        } else if result.status != 0 {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            issues.append(ScanIssue(kind: .commandFailure, area: area, detail: detail.isEmpty ? "Command exited with status \(result.status)." : detail))
        }
    }

    private var currentTaskIsCancelled: Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }
}
