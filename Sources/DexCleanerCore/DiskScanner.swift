import Foundation

public struct DiskScanner {
    public let home: String
    public let appVersion = "0.4.0"
    private let cache: ScanCache

    public init(home: String = NSHomeDirectory(), cache: ScanCache? = nil) {
        self.home = home
        self.cache = cache ?? ScanCache(home: home)
    }

    public func scan() -> ScanSnapshot {
        let started = Date()
        var items: [ScanItem] = []
        var warnings: [String] = []
        let status = diskStatus()

        for entry in CleanupCatalog.exactSafeEntries where !Task.isCancelled {
            if let item = scanCatalogEntry(entry) { items.append(item) }
        }
        if !Task.isCancelled { items.append(contentsOf: gitTemporaryPackItems()) }
        if !Task.isCancelled { items.append(contentsOf: protectedPathMarkers()) }
        if !Task.isCancelled { items.append(contentsOf: auditUsageItems()) }

        var largeFiles: [ScanItem] = []
        if !Task.isCancelled {
            largeFiles = largeFileAuditItems()
            items.append(contentsOf: largeFiles)
            items.append(contentsOf: extensionBreakdownItems(from: largeFiles))
        }

        let diagnostics = PermissionDiagnostics.evaluate(home: home)
        if !Task.isCancelled { items.append(contentsOf: permissionDiagnosticItems(from: diagnostics)) }
        if diagnostics.contains(where: { $0.status == "Limited access" }) {
            warnings.append("Full Disk Access appears limited. Some audit areas may be incomplete.")
        }

        items.sort { left, right in
            if left.action != right.action { return left.action == .moveToTrash }
            if left.group != right.group { return left.group < right.group }
            if left.risk.sortRank != right.risk.sortRank { return left.risk.sortRank < right.risk.sortRank }
            return left.sizeBytes > right.sizeBytes
        }
        cache.save()

        return ScanSnapshot(
            timestamp: Date(),
            diskStatus: status,
            items: items,
            storageSummaries: storageSummaries(from: items),
            permissionDiagnostics: diagnostics,
            warnings: warnings,
            scanDurationSeconds: Date().timeIntervalSince(started),
            policyVersion: CleanupCatalog.policyVersion,
            appVersion: appVersion,
            fullDiskAccessStatus: PermissionDiagnostics.summary(diagnostics),
            cancelled: Task.isCancelled
        )
    }

    public func scanCatalogEntry(_ entry: CatalogEntry) -> ScanItem? {
        let path = URL(fileURLWithPath: home).appendingPathComponent(entry.relativePath).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let size = cachedDuSizeBytes(path: path, timeout: entry.risk == .safe ? 15 : 8)
        guard size > 0 || entry.risk == .forbidden else { return nil }
        var item = ScanItem(
            manifestID: entry.id,
            path: path,
            displayName: entry.displayName,
            group: entry.group,
            category: entry.category,
            risk: entry.risk,
            sizeBytes: size,
            explanation: entry.explanation,
            recoveryNote: entry.recoveryNote,
            action: entry.action,
            isSelected: entry.risk == .safe ? entry.defaultSelected : false
        )
        if item.action == .moveToTrash {
            let decision = SafetyEngine.decision(for: item, home: home)
            if !decision.allowed {
                item.risk = .forbidden
                item.isSelected = false
                item.action = .auditOnly
                item.explanation += " SafetyEngine blocked cleanup: \(decision.reason)"
                item.recoveryNote = "No cleanup action allowed by SafetyEngine."
            }
        }
        return item
    }

    public func diskStatus() -> DiskStatus {
        let result = Shell.run("/bin/df", ["-h", "/System/Volumes/Data"], timeout: 5)
        let fallback = result.status == 0 ? result : Shell.run("/bin/df", ["-h"], timeout: 5)
        let output = fallback.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { return DiskStatus() }
        let parts = lines[1].split(separator: " ").map(String.init)
        guard parts.count >= 5 else { return DiskStatus() }
        return DiskStatus(filesystem: parts[0], size: parts[1], used: parts[2], available: parts[3], capacity: parts[4])
    }

    public func duSizeBytes(path: String, timeout: TimeInterval = 10) -> Int64 {
        let result = Shell.run("/usr/bin/du", ["-sk", path], timeout: timeout)
        guard result.status == 0 else { return 0 }
        let first = result.stdout.split(separator: "\t").first ?? result.stdout.split(separator: " ").first
        guard let value = first, let kb = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return kb * 1024
    }

    public func cachedDuSizeBytes(path: String, timeout: TimeInterval = 10) -> Int64 {
        if let cached = cache.cachedSize(path: path) { return cached }
        let size = duSizeBytes(path: path, timeout: timeout)
        if size > 0 { cache.store(path: path, sizeBytes: size) }
        return size
    }

    public func gitTemporaryPackItems(gitProcessChecker: () -> Bool = SafetyEngine.gitProcessIsRunning) -> [ScanItem] {
        let roots = ["Projects", "Developer", "src", "go", "esp"].map { URL(fileURLWithPath: home).appendingPathComponent($0) }
        var found: [ScanItem] = []

        for root in roots where !Task.isCancelled && FileManager.default.fileExists(atPath: root.path) {
            let result = Shell.run(
                "/usr/bin/find",
                [root.path, "-path", "*/.git/objects/pack/tmp_pack_*", "-type", "f", "-mmin", "+10", "-print"],
                timeout: 20
            )
            guard result.status == 0 || !result.stdout.isEmpty else { continue }

            for rawLine in result.stdout.split(separator: "\n") where !Task.isCancelled {
                let path = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { continue }
                let url = URL(fileURLWithPath: path)
                guard url.lastPathComponent.hasPrefix("tmp_pack_") else { continue }
                let packDirectory = url.deletingLastPathComponent()
                let objectsDirectory = packDirectory.deletingLastPathComponent()
                let gitDirectory = objectsDirectory.deletingLastPathComponent()
                guard packDirectory.lastPathComponent == "pack", objectsDirectory.lastPathComponent == "objects", gitDirectory.lastPathComponent == ".git" else { continue }
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
                if let modified = values.contentModificationDate, Date().timeIntervalSince(modified) < SafetyEngine.gitTempPackMinimumAge { continue }
                let size = duSizeBytes(path: url.path, timeout: 5)
                guard size > 0 else { continue }
                let item = ScanItem(
                    manifestID: "git-temporary-pack",
                    path: url.path,
                    displayName: "Abandoned Git temporary pack",
                    group: "Git",
                    category: .gitTemporaryPack,
                    risk: .safe,
                    sizeBytes: size,
                    explanation: "Temporary Git pack file older than 10 minutes. Clean only when no Git process or pack lock is active.",
                    recoveryNote: "Git will recreate pack files during future fetch/gc operations.",
                    action: .moveToTrash,
                    isSelected: false
                )
                if SafetyEngine.decision(for: item, home: home, gitProcessChecker: gitProcessChecker).allowed { found.append(item) }
            }
        }
        return found
    }

    public func protectedPathMarkers() -> [ScanItem] {
        let protectedRelativePaths = [
            (".cache", "Hidden cache root"),
            (".antigravity", "Antigravity state"),
            (".antigravity_archive", "Antigravity archive"),
            ("Library/Application Support/Antigravity", "Antigravity Application Support"),
            ("Library/CloudStorage", "Cloud storage root"),
            ("Library/Keychains", "Keychains"),
            ("Documents", "User Documents"),
            ("Downloads", "User Downloads"),
            ("Desktop", "Desktop"),
            ("Projects", "Project source trees"),
            ("Pictures", "Pictures"),
            ("Movies", "Movies"),
            ("Dropbox", "Dropbox"),
            ("OneDrive", "OneDrive"),
            ("Google Drive", "Google Drive")
        ]

        return protectedRelativePaths.compactMap { relativePath, label in
            let path = URL(fileURLWithPath: home).appendingPathComponent(relativePath).path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let category: CleanupCategory = relativePath.contains("Cloud") || relativePath.contains("Drive") || relativePath == "Dropbox" || relativePath == "OneDrive" ? .cloudStorage : .protected
            return ScanItem(
                manifestID: "protected-\(relativePath.replacingOccurrences(of: "/", with: "-"))",
                path: path,
                displayName: "Protected: \(label)",
                group: category == .cloudStorage ? "Cloud Storage" : "Protected User Data",
                category: category,
                risk: .forbidden,
                sizeBytes: 0,
                explanation: "Detected for reporting only. DexCleaner must never offer this broad user/app-state path in safe cleanup.",
                recoveryNote: "Review manually in Finder or the owning app. DexCleaner will not clean this path.",
                action: .auditOnly,
                isSelected: false
            )
        }
    }

    public func auditUsageItems() -> [ScanItem] {
        let roots: [(String, String, Int)] = [
            (home, "Home top-level usage", 20),
            (URL(fileURLWithPath: home).appendingPathComponent("Library").path, "Library top-level usage", 20),
            (URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support").path, "Application Support usage", 30)
        ]

        var findings: [ScanItem] = []
        for (rootPath, title, limit) in roots where !Task.isCancelled { findings.append(contentsOf: auditChildren(rootPath: rootPath, title: title, limit: limit)) }
        return findings
    }

    public func auditChildren(rootPath: String, title: String, limit: Int) -> [ScanItem] {
        guard FileManager.default.fileExists(atPath: rootPath) else { return [] }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsPackageDescendants]) else { return [] }

        let minimumBytes: Int64 = 100 * 1024 * 1024
        var findings: [ScanItem] = []
        for url in urls where !Task.isCancelled {
            let size = cachedDuSizeBytes(path: url.path, timeout: 8)
            guard size >= minimumBytes else { continue }
            findings.append(ScanItem(
                manifestID: "storage-map",
                path: url.path,
                displayName: "\(title): \(url.lastPathComponent)",
                group: "Storage Map",
                category: .storageMap,
                risk: .auditOnly,
                sizeBytes: size,
                explanation: "Read-only size finding. This is not a cleanup candidate. Review manually before acting.",
                recoveryNote: "Use Reveal in Finder or the owning app. DexCleaner will not delete storage-map findings.",
                action: .auditOnly,
                isSelected: false
            ))
        }
        return Array(findings.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    public func largeFileAuditItems() -> [ScanItem] {
        let result = Shell.run("/usr/bin/find", [home, "-type", "f", "-size", "+500M", "-exec", "/usr/bin/du", "-sk", "{}", "+"], timeout: 30)
        guard result.status == 0 || !result.stdout.isEmpty else { return [] }

        return result.stdout.split(separator: "\n").compactMap { line -> ScanItem? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let kb = Int64(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return ScanItem(
                manifestID: "large-file-audit",
                path: path,
                displayName: "Large file: \(URL(fileURLWithPath: path).lastPathComponent)",
                group: "Large Files",
                category: .auditOnly,
                risk: .auditOnly,
                sizeBytes: kb * 1024,
                explanation: "Read-only large-file finding. DexCleaner will not clean this automatically.",
                recoveryNote: "Review manually. If it is user content, back it up before deleting outside DexCleaner.",
                action: .auditOnly,
                isSelected: false
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(30).map { $0 }
    }

    public func extensionBreakdownItems(from largeFiles: [ScanItem]) -> [ScanItem] {
        let grouped = Dictionary(grouping: largeFiles) { item -> String in
            let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
            return ext.isEmpty ? "no extension" : ".\(ext)"
        }
        return grouped.map { ext, items in
            ScanItem(
                manifestID: "extension-breakdown",
                path: "extension://\(ext)",
                displayName: "Large-file extension total: \(ext)",
                group: "Extension Breakdown",
                category: .extensionBreakdown,
                risk: .auditOnly,
                sizeBytes: items.reduce(0) { $0 + $1.sizeBytes },
                explanation: "Read-only extension breakdown based on large files found during the scan.",
                recoveryNote: "Use the large-file list to inspect individual files. DexCleaner will not delete by extension.",
                action: .auditOnly,
                isSelected: false
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public func permissionDiagnosticItems(from diagnostics: [PermissionDiagnostic]) -> [ScanItem] {
        diagnostics.map { diagnostic in
            ScanItem(
                manifestID: "permission-diagnostic",
                path: "permission://\(diagnostic.title)",
                displayName: diagnostic.title,
                group: "Permissions",
                category: .permissionDiagnostic,
                risk: diagnostic.status == "Limited access" ? .caution : .auditOnly,
                sizeBytes: 0,
                explanation: "\(diagnostic.status): \(diagnostic.detail)",
                recoveryNote: diagnostic.remediation,
                action: .auditOnly,
                isSelected: false
            )
        }
    }

    public func storageSummaries(from items: [ScanItem]) -> [StorageSummaryItem] {
        let cleanableBytes = items.filter { $0.isCleanable }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let auditBytes = items.filter { $0.action == .auditOnly && $0.sizeBytes > 0 }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        var summaries = [
            StorageSummaryItem(label: "Cleanable exact targets", bytes: cleanableBytes, detail: "Safe manifest-approved targets only."),
            StorageSummaryItem(label: "Audit-only visible usage", bytes: auditBytes, detail: "Large findings and caution targets that DexCleaner will not delete.")
        ]
        let grouped = Dictionary(grouping: items.filter { $0.sizeBytes > 0 }, by: { $0.group })
        summaries.append(contentsOf: grouped.map { group, groupItems in
            StorageSummaryItem(label: group, bytes: groupItems.reduce(0) { $0 + $1.sizeBytes }, detail: "Grouped scan findings.")
        }.sorted { $0.bytes > $1.bytes }.prefix(8))
        return summaries
    }
}
