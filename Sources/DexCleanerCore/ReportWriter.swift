import Foundation

public enum ReportWriter {
    public static func write(
        report: ScanReport,
        format: ReportFormat = .markdown,
        redaction: PathRedactionMode = .none,
        destinationDirectory: URL? = nil,
        home: String = NSHomeDirectory()
    ) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: report.timestamp).replacingOccurrences(of: ":", with: "-")
        let directory = destinationDirectory ?? defaultDirectory(home: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reportLabel = reportLabel(for: report)
        let modeSlug = reportLabel.lowercased().replacingOccurrences(of: " ", with: "-")
        let ext = format == .markdown ? "md" : "json"
        let suffix = UUID().uuidString.prefix(8)
        let url = directory.appendingPathComponent("DexCleaner-\(modeSlug)-Report-\(stamp)-\(suffix).\(ext)")
        let redacted = redact(report: report, mode: redaction, home: home)

        switch format {
        case .markdown:
            try markdown(redacted).write(to: url, atomically: true, encoding: .utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(redacted).write(to: url, options: .atomic)
        }
        return url
    }

    public static func defaultDirectory(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/DexCleaner/Reports", isDirectory: true)
    }

    public static func write(report: ScanReport, destinationDirectory: URL? = nil) throws -> URL {
        try write(report: report, format: .markdown, destinationDirectory: destinationDirectory)
    }

    private static func markdown(_ report: ScanReport) -> String {
        let formatter = ISO8601DateFormatter()
        let cleanable = report.items.filter { $0.action == .moveToTrash }
        let auditOnly = report.items.filter { $0.action == .auditOnly && $0.category != .protected && $0.category != .cloudStorage }
        let protected = report.items.filter { $0.category == .protected || $0.category == .cloudStorage || $0.risk == .forbidden }
        let selected = report.items.filter { $0.isSelected }
        let blocked = report.results.filter { $0.status == "Blocked" }
        let failed = report.results.filter { $0.status == "Failed" }
        let moved = report.results.filter { $0.status == "Moved to Trash" }

        var text = "# DexCleaner \(reportLabel(for: report)) Report\n\n"
        text += "Generated: \(formatter.string(from: report.timestamp))\n\n"
        text += "## Authority and completeness\n\n"
        text += "- App version: \(report.appVersion)\n"
        text += "- Manifest version: \(report.policyVersion)\n"
        text += "- Manifest checksum: \(report.manifestChecksum)\n"
        text += "- Report mode: \(reportLabel(for: report))\n"
        text += "- Scan completeness: \(report.completeness.rawValue)\n"
        text += "- Scan duration: \(String(format: "%.2f", report.scanDurationSeconds)) seconds\n"
        text += "- Access check: \(report.accessStatus)\n"
        text += "- Cleanup mechanism: Finder Trash only\n"
        text += "- Disk space freed: not asserted; moved items remain in Trash until emptied manually\n"
        text += "- Network and telemetry: none\n\n"

        text += "## Disk\n\n"
        text += "- Filesystem: \(report.diskStatus.filesystem)\n"
        text += "- Total capacity: \(report.diskStatus.size)\n"
        text += "- Available for work: \(report.diskStatus.available)\n"
        text += "- Immediately free: \(format(report.diskStatus.immediatelyFreeBytes))\n"
        text += "- Used estimate: \(report.diskStatus.used)\n"
        text += "- Potentially purgeable: \(format(report.diskStatus.potentiallyPurgeableBytes))\n"
        text += "- Measurement status: \(report.diskStatus.state.rawValue)\n"
        text += "- Measurement source: \(report.diskStatus.source)\n"
        text += "- Measurement detail: \(report.diskStatus.detail)\n"
        if let measuredAt = report.diskStatus.measuredAt {
            text += "- Measured: \(formatter.string(from: measuredAt))\n"
        }
        text += "\n"

        text += "## Summary\n\n"
        text += "- Cleanup candidates: \(cleanable.count)\n"
        text += "- Selected candidates: \(selected.count)\n"
        text += "- Selected estimate: \(ByteCountFormatter.string(fromByteCount: selected.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))\n"
        text += "- Audit-only findings: \(auditOnly.count)\n"
        text += "- Protected presence markers: \(protected.count)\n"
        text += "- Moved to Trash: \(moved.count) items / \(ByteCountFormatter.string(fromByteCount: report.movedToTrashBytes, countStyle: .file))\n"
        text += "- Blocked: \(blocked.count)\n"
        text += "- Failed: \(failed.count)\n\n"

        if let plan = report.cleanupPlan {
            text += "## Immutable cleanup plan\n\n"
            text += "- Plan ID: \(plan.id.uuidString)\n"
            text += "- Created: \(formatter.string(from: plan.createdAt))\n"
            text += "- Manifest version: \(plan.manifestVersion)\n"
            text += "- Manifest checksum: \(plan.manifestChecksum)\n"
            text += "- Selection signature: \(plan.selectionSignature)\n"
            text += "- Expires: \(formatter.string(from: plan.expiresAt))\n"
            text += "- Planned items: \(plan.items.count)\n"
            text += "- Planned bytes: \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))\n\n"
            for item in plan.items {
                text += "- \(item.displayName): `\(escapeBackticks(item.path))` — \(item.safetyReason)\n"
            }
            text += "\n"
        }

        if !report.warnings.isEmpty {
            text += "## Warnings\n\n"
            for warning in report.warnings { text += "- \(warning)\n" }
            text += "\n"
        }

        text += "## Scan issues\n\n"
        if report.issues.isEmpty {
            text += "No scan issues recorded.\n\n"
        } else {
            for issue in report.issues { text += "- \(issue.kind.rawValue) — \(issue.area): \(issue.detail)\n" }
            text += "\n"
        }

        appendStorageSummary(report.storageSummaries, into: &text)
        appendPermissionDiagnostics(report.permissionDiagnostics, into: &text)
        appendGroupedSection("Cleanup candidates", items: cleanable, into: &text)
        appendGroupedSection("Audit-only findings", items: auditOnly, into: &text)
        appendGroupedSection("Protected presence markers", items: protected, into: &text)

        text += "## Results\n\n"
        if report.results.isEmpty {
            text += "No preview or cleanup results.\n\n"
        } else {
            for result in report.results {
                text += "- \(result.status): `\(escapeBackticks(result.path))` — \(result.detail)\n"
            }
            text += "\n"
        }

        text += "## Safety reminder\n\n"
        text += "DexCleaner grants cleanup authority only to exact paths in the validated bundled manifest. Audit findings, protected locations, cloud storage, project trees, Git internals, and user content are not cleanup targets. A moved-to-Trash byte count is not a claim that disk space has been freed.\n"
        return text
    }

    private static func redact(report: ScanReport, mode: PathRedactionMode, home: String) -> ScanReport {
        guard mode == .homeRelative else { return report }
        var copy = report
        let normalizedHome = SafetyEngine.lexicalNormalize(home)

        func redactText(_ text: String) -> String {
            text
                .replacingOccurrences(of: normalizedHome, with: "~")
                .replacingOccurrences(of: home, with: "~")
        }

        func redactPath(_ path: String) -> String {
            guard path.hasPrefix("/") else { return redactText(path) }
            let normalized = SafetyEngine.lexicalNormalize(path)
            guard normalized == normalizedHome || normalized.hasPrefix(normalizedHome + "/") else {
                return redactText(path)
            }
            return "~" + normalized.dropFirst(normalizedHome.count)
        }

        copy.items = copy.items.map { item in
            var value = item
            value.path = redactPath(item.path)
            value.displayName = redactText(item.displayName)
            value.explanation = redactText(item.explanation)
            value.recoveryNote = redactText(item.recoveryNote)
            return value
        }
        copy.results = copy.results.map { result in
            var value = result
            value.path = redactPath(result.path)
            value.detail = redactText(result.detail)
            value.resultingPath = result.resultingPath.map(redactPath)
            return value
        }
        copy.storageSummaries = copy.storageSummaries.map { summary in
            var value = summary
            value.label = redactText(summary.label)
            value.detail = redactText(summary.detail)
            return value
        }
        copy.permissionDiagnostics = copy.permissionDiagnostics.map { diagnostic in
            var value = diagnostic
            value.title = redactText(diagnostic.title)
            value.detail = redactText(diagnostic.detail)
            value.remediation = redactText(diagnostic.remediation)
            return value
        }
        copy.warnings = copy.warnings.map(redactText)
        copy.issues = copy.issues.map { issue in
            var value = issue
            value.area = redactText(issue.area)
            value.detail = redactText(issue.detail)
            return value
        }
        if let plan = copy.cleanupPlan {
            let items = plan.items.map { item in
                CleanupPlanItem(
                    id: item.id,
                    scanItemID: item.scanItemID,
                    manifestID: item.manifestID,
                    path: redactPath(item.path),
                    displayName: redactText(item.displayName),
                    sizeBytes: item.sizeBytes,
                    identity: item.identity,
                    safetyReason: redactText(item.safetyReason),
                    risk: item.risk,
                    action: item.action
                )
            }
            copy.cleanupPlan = CleanupPlan(
                id: plan.id,
                createdAt: plan.createdAt,
                manifestVersion: plan.manifestVersion,
                manifestChecksum: plan.manifestChecksum,
                selectionSignature: "redacted",
                items: items
            )
        }
        return copy
    }

    public static func reportLabel(for report: ScanReport) -> String {
        if report.mode == .cleanup { return "Cleanup" }
        if report.mode == .dryRun { return "Preview" }
        return report.completeness == .notRun ? "Status" : "Scan"
    }

    private static func appendStorageSummary(_ summaries: [StorageSummaryItem], into text: inout String) {
        text += "## Storage summary\n\n"
        if summaries.isEmpty { text += "No measured storage summaries.\n\n"; return }
        for summary in summaries.sorted(by: { $0.bytes > $1.bytes }) {
            text += "- \(summary.label): \(summary.formattedSize) — \(summary.detail)\n"
        }
        text += "\n"
    }

    private static func appendPermissionDiagnostics(_ diagnostics: [PermissionDiagnostic], into text: inout String) {
        text += "## Access checks\n\n"
        if diagnostics.isEmpty { text += "No access checks recorded.\n\n"; return }
        for diagnostic in diagnostics {
            text += "### \(diagnostic.title)\n"
            text += "- Status: \(diagnostic.status)\n"
            text += "- Detail: \(diagnostic.detail)\n"
            text += "- Remediation: \(diagnostic.remediation)\n\n"
        }
    }

    private static func appendGroupedSection(_ title: String, items: [ScanItem], into text: inout String) {
        text += "## \(title)\n\n"
        if items.isEmpty { text += "No items.\n\n"; return }
        let grouped = Dictionary(grouping: items, by: { $0.group })
        for group in grouped.keys.sorted() {
            text += "### Group: \(group)\n\n"
            for item in (grouped[group] ?? []).sorted(by: { $0.sizeBytes > $1.sizeBytes }) { appendItem(item, into: &text) }
        }
    }

    private static func appendItem(_ item: ScanItem, into text: inout String) {
        text += "#### \(item.displayName)\n"
        text += "- Manifest ID: \(item.manifestID ?? "none")\n"
        text += "- Path: `\(escapeBackticks(item.path))`\n"
        text += "- Size: \(item.sizeBytes > 0 ? item.formattedSize : "not measured")\n"
        text += "- Measurement: \(item.measurementSource.rawValue)"
        if let measuredAt = item.measuredAt { text += " at \(ISO8601DateFormatter().string(from: measuredAt))" }
        text += "\n"
        text += "- Category: \(item.category.rawValue)\n"
        text += "- Risk: \(item.risk.rawValue)\n"
        text += "- Action: \(item.action.rawValue)\n"
        text += "- Selected: \(item.isSelected ? "yes" : "no")\n"
        text += "- Owning process appears active: \(item.owningProcessRunning ? "yes" : "no")\n"
        text += "- Explanation: \(item.explanation)\n"
        text += "- Recovery note: \(item.recoveryNote)\n\n"
    }

    private static func escapeBackticks(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "\\`")
    }

    private static func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
