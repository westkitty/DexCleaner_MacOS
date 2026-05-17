import Foundation

public struct ReportWriter {
    public static func write(report: ScanReport, destinationDirectory: URL? = nil) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: report.timestamp).replacingOccurrences(of: ":", with: "-")
        let directory = destinationDirectory
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let modeSlug = report.mode.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        let url = directory.appendingPathComponent("DexCleaner-\(modeSlug)-Report-\(stamp).md")

        let cleanable = report.items.filter { $0.action == .moveToTrash }
        let auditOnly = report.items.filter { $0.action == .auditOnly && $0.category != .protected && $0.category != .cloudStorage }
        let protected = report.items.filter { $0.category == .protected || $0.category == .cloudStorage || $0.risk == .forbidden }
        let selected = report.items.filter { $0.isSelected }
        let skipped = report.results.filter { $0.status == "Skipped" || $0.status == "Blocked in preview" }
        let failed = report.results.filter { $0.status == "Failed" }

        var text = "# DexCleaner \(report.mode.rawValue) Report\n\n"
        text += "Generated: \(formatter.string(from: report.timestamp))\n\n"
        text += "## App and policy\n\n"
        text += "- App version: \(report.appVersion)\n"
        text += "- Safety policy version: \(report.policyVersion)\n"
        text += "- Report mode: \(report.mode.rawValue)\n"
        text += "- Scan duration: \(String(format: "%.2f", report.scanDurationSeconds)) seconds\n"
        text += "- Full Disk Access: \(report.fullDiskAccessStatus)\n"
        text += "- Cleanup mode: Move to Finder Trash only\n"
        text += "- Allowlist mode: exact manifest paths only\n"
        text += "- Network/telemetry: none implemented\n\n"

        text += "## Disk\n\n"
        text += "- Filesystem: \(report.diskStatus.filesystem)\n"
        text += "- Size: \(report.diskStatus.size)\n"
        text += "- Used: \(report.diskStatus.used)\n"
        text += "- Available: \(report.diskStatus.available)\n"
        text += "- Capacity: \(report.diskStatus.capacity)\n\n"

        text += "## Summary\n\n"
        text += "- Cleanup candidates: \(cleanable.count)\n"
        text += "- Selected cleanup candidates: \(selected.count)\n"
        text += "- Selected reclaim: \(ByteCountFormatter.string(fromByteCount: selected.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))\n"
        text += "- Audit-only findings: \(auditOnly.count)\n"
        text += "- Protected/forbidden paths reported: \(protected.count)\n"
        text += "- Cleanup skipped/blocked: \(skipped.count)\n"
        text += "- Cleanup failed: \(failed.count)\n\n"

        if !report.warnings.isEmpty {
            text += "## Warnings\n\n"
            for warning in report.warnings { text += "- \(warning)\n" }
            text += "\n"
        }

        appendStorageSummary(report.storageSummaries, into: &text)
        appendPermissionDiagnostics(report.permissionDiagnostics, into: &text)
        appendGroupedSection("Cleanup candidates", items: cleanable, into: &text)
        appendGroupedSection("Audit-only findings", items: auditOnly, into: &text)
        appendGroupedSection("Protected and forbidden paths", items: protected, into: &text)

        if !report.results.isEmpty {
            text += "## Results\n\n"
            for result in report.results {
                text += "- \(result.status): `\(escapeBackticks(result.path))` — \(result.detail)\n"
            }
            text += "\n"
        }

        text += "## Safety reminder\n\n"
        text += "DexCleaner reports audit-only, caution, cloud, and protected paths so disk pressure is visible without pretending those paths are disposable. Do not convert audit findings into cleanup targets without a separate safety review. The project doctrine is preview-first, exact manifest allowlist, and Finder Trash only.\n"

        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func appendStorageSummary(_ summaries: [StorageSummaryItem], into text: inout String) {
        text += "## Storage summary\n\n"
        if summaries.isEmpty { text += "No storage summaries.\n\n"; return }
        for summary in summaries.sorted(by: { $0.bytes > $1.bytes }) {
            text += "- \(summary.label): \(summary.formattedSize) — \(summary.detail)\n"
        }
        text += "\n"
    }

    private static func appendPermissionDiagnostics(_ diagnostics: [PermissionDiagnostic], into text: inout String) {
        text += "## Permission diagnostics\n\n"
        if diagnostics.isEmpty { text += "No permission diagnostics recorded.\n\n"; return }
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
            for item in (grouped[group] ?? []).sorted(by: { $0.sizeBytes > $1.sizeBytes }) {
                appendItem(item, into: &text)
            }
        }
    }

    private static func appendItem(_ item: ScanItem, into text: inout String) {
        text += "#### \(item.displayName)\n"
        text += "- Manifest ID: \(item.manifestID ?? "none")\n"
        text += "- Path: `\(escapeBackticks(item.path))`\n"
        text += "- Size: \(item.sizeBytes > 0 ? item.formattedSize : "not measured")\n"
        text += "- Category: \(item.category.rawValue)\n"
        text += "- Risk: \(item.risk.rawValue)\n"
        text += "- Action: \(item.action.rawValue)\n"
        text += "- Selected: \(item.isSelected ? "yes" : "no")\n"
        text += "- Explanation: \(item.explanation)\n"
        text += "- Recovery note: \(item.recoveryNote)\n"
        if item.action == .moveToTrash {
            text += "- Safety decision: \(SafetyEngine.decision(for: item).reason)\n"
        } else {
            text += "- Safety decision: Not cleanable by design.\n"
        }
        text += "\n"
    }

    private static func escapeBackticks(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "\\`")
    }
}
