import AppKit
import DexCleanerCore
import Foundation
import SwiftUI

enum OperationPhase: String, CaseIterable {
    case idle = "Ready"
    case scanning = "Scanning"
    case reviewing = "Review"
    case previewed = "Preview authorized"
    case cleaning = "Moving to Trash"
    case cancelled = "Cancelled"
    case complete = "Complete"
    case failed = "Needs attention"
}

enum CleanupProfile: String, CaseIterable, Identifiable {
    case all = "All"
    case appleDevelopment = "Apple Dev"
    case packageManagers = "Packages"
    case appCaches = "App Caches"

    var id: String { rawValue }

    func includes(_ item: ScanItem) -> Bool {
        switch self {
        case .all:
            return true
        case .appleDevelopment:
            return ["Xcode", "Swift", "Simulator"].contains(item.group)
        case .packageManagers:
            return ["Homebrew", "Python", "Node", "JavaScript", "Gradle", "CocoaPods"].contains(item.group)
        case .appCaches:
            return item.category == .exactCache
        }
    }
}

enum ScanSortMode: String, CaseIterable, Identifiable {
    case largestFirst = "Largest"
    case name = "Name"
    case risk = "Risk"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var diskStatus = DiskStatus()
    @Published var cleanupResults: [CleanupResult] = []
    @Published var storageSummaries: [StorageSummaryItem] = []
    @Published var permissionDiagnostics: [PermissionDiagnostic] = []
    @Published var warnings: [String] = []
    @Published var scanIssues: [ScanIssue] = []
    @Published var scanCompleteness: ScanCompleteness = .notRun
    @Published var statusText = "Ready. Scan starts only when requested."
    @Published var reportStatusText = "No report written in this session."
    @Published var isWorking = false
    @Published var lastReportURL: URL?
    @Published var accessStatus = "Not tested"
    @Published var scanDurationSeconds: TimeInterval = 0
    @Published var phase: OperationPhase = .idle
    @Published var activeProfile: CleanupProfile = .all {
        didSet {
            guard oldValue != activeProfile else { return }
            clearSelection(reason: "Profile changed. Previous selection was cleared to prevent hidden cleanup targets.")
        }
    }
    @Published var sortMode: ScanSortMode = .largestFirst
    @Published var searchText = ""
    @Published var reportDestinationDirectory: URL?
    @Published var reportFormat: ReportFormat = .markdown
    @Published var pathRedaction: PathRedactionMode = .homeRelative
    @Published var excludedLargeFileRootsText = ""
    @Published var lastTrashBytes: Int64 = 0
    @Published var cleanupPlan: CleanupPlan?
    @Published var lastCompletedPlan: CleanupPlan?
    @Published var lastLedgerURL: URL?

    private var activeTask: Task<Void, Never>?
    private var authorization = PreviewAuthorization()
    private var lastReportMode: ReportMode = .scan
    private let runner = CleanupRunner()

    var allCleanableItems: [ScanItem] {
        sorted(items.filter { $0.action == .moveToTrash })
    }

    var cleanableItems: [ScanItem] {
        sorted(items.filter { item in
            item.action == .moveToTrash && activeProfile.includes(item) && matchesSearch(item)
        })
    }

    var auditItems: [ScanItem] {
        sorted(items.filter {
            $0.action == .auditOnly && $0.category != .protected && $0.category != .cloudStorage && $0.risk != .forbidden && matchesSearch($0)
        })
    }

    var protectedItems: [ScanItem] {
        sorted(items.filter {
            ($0.category == .protected || $0.category == .cloudStorage || $0.risk == .forbidden) && matchesSearch($0)
        })
    }

    var selectedItems: [ScanItem] { sorted(items.filter { $0.isSelected }) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var cleanableBytes: Int64 { allCleanableItems.reduce(0) { $0 + $1.sizeBytes } }
    var auditBytes: Int64 { auditItems.reduce(0) { $0 + $1.sizeBytes } }
    var selectedSizeText: String { ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file) }
    var cleanableSizeText: String { ByteCountFormatter.string(fromByteCount: cleanableBytes, countStyle: .file) }
    var lastTrashSizeText: String { ByteCountFormatter.string(fromByteCount: lastTrashBytes, countStyle: .file) }
    var canClean: Bool { !isWorking && authorization.isValid(items: items, plan: cleanupPlan) }
    var manifestAuthorityText: String {
        CleanupCatalog.isAvailable ? "Manifest \(CleanupCatalog.policyVersion) · \(CleanupCatalog.manifestChecksum)" : "Cleanup disabled: manifest invalid"
    }

    func scan() {
        guard !isWorking else {
            statusText = "Another operation is still finishing."
            return
        }
        invalidatePreview()
        cleanupResults = []
        lastTrashBytes = 0
        lastReportMode = .scan
        statusText = "Scanning read-only targets and audit areas…"
        phase = .scanning
        isWorking = true
        let roots = parsedExcludedRoots
        let home = NSHomeDirectory()

        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
            }
            let worker = Task.detached(priority: .userInitiated) {
                DiskScanner(home: home, excludedLargeFileRelativePaths: roots).scan()
            }
            let snapshot = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            apply(snapshot: snapshot)
            switch snapshot.completeness {
            case .complete:
                phase = .reviewing
                statusText = "Scan complete. Review visible candidates; nothing is selected."
            case .partial:
                phase = .reviewing
                statusText = "Scan partial. Review the Issues tab before relying on missing results."
            case .cancelled:
                phase = .cancelled
                statusText = "Scan cancelled. Partial findings remain visible and are labeled incomplete."
            case .failed:
                phase = .failed
                statusText = "Scan failed. Review the Issues tab."
            case .notRun:
                phase = .idle
                statusText = "No scan has run."
            }
        }
    }

    func cancel() {
        guard isWorking else { return }
        activeTask?.cancel()
        phase = .cancelled
        statusText = "Cancellation requested. Active shell work is being terminated where possible."
    }

    func selectVisibleCandidates() {
        let visibleIDs = Set(cleanableItems.map(\.id))
        items = items.map { item in
            var copy = item
            copy.isSelected = copy.isCleanable && visibleIDs.contains(copy.id)
            return copy
        }
        invalidatePreview()
        statusText = "Selected \(visibleIDs.count) visible candidates. Preview is required before cleanup."
    }

    func clearSelection(reason: String? = nil) {
        items = items.map { item in var copy = item; copy.isSelected = false; return copy }
        invalidatePreview()
        if let reason { statusText = reason }
    }

    func toggle(_ item: ScanItem) {
        guard !isWorking, let index = items.firstIndex(where: { $0.id == item.id }), items[index].isCleanable else { return }
        items[index].isSelected.toggle()
        invalidatePreview()
        statusText = "Selection changed. Run Preview again before cleanup."
    }

    func previewSelected() {
        guard !isWorking else { return }
        let selected = selectedItems
        guard !selected.isEmpty else {
            statusText = "No cleanup candidates are selected."
            return
        }
        let outcome = runner.previewSelected(selected)
        cleanupResults = outcome.results
        cleanupPlan = outcome.plan
        lastReportMode = .dryRun
        if let plan = outcome.plan {
            authorization.authorize(items: items, plan: plan)
            phase = .previewed
            statusText = "Preview authorized plan \(plan.id.uuidString.prefix(8)). Review every path, then confirm Move to Trash."
        } else {
            authorization.invalidate()
            phase = .failed
            statusText = "Preview blocked. No cleanup plan was authorized."
        }
        appendLedger(mode: .dryRun, plan: outcome.plan, results: outcome.results, movedBytes: 0)
    }

    func cleanConfirmed() {
        guard canClean, let plan = cleanupPlan else {
            statusText = "Cleanup authorization is stale or missing. Run Preview again."
            return
        }
        isWorking = true
        phase = .cleaning
        statusText = "Revalidating each previewed target immediately before moving it to Finder Trash…"
        let home = NSHomeDirectory()
        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
            }
            let cleanupWorker = Task.detached(priority: .userInitiated) {
                CleanupRunner(home: home).clean(plan: plan)
            }
            let results = await withTaskCancellationHandler {
                await cleanupWorker.value
            } onCancel: {
                cleanupWorker.cancel()
            }
            cleanupResults = results
            lastReportMode = .cleanup
            lastTrashBytes = results.filter { $0.status == "Moved to Trash" }.reduce(Int64(0)) { total, result in
                total + (plan.items.first(where: { $0.path == result.path })?.sizeBytes ?? 0)
            }
            appendLedger(mode: .cleanup, plan: plan, results: results, movedBytes: lastTrashBytes)
            authorization.invalidate()
            lastCompletedPlan = plan
            cleanupPlan = nil

            if results.contains(where: { $0.status == "Failed" || $0.status == "Blocked" }) {
                phase = .failed
                statusText = "Cleanup completed with blocked or failed items. Review the complete Results list."
            } else if results.contains(where: { $0.status == "Cancelled" }) {
                phase = .cancelled
                statusText = "Cleanup cancelled. Completed moves remain in Trash; unprocessed items were not moved."
            } else {
                phase = .complete
                statusText = "Moved \(lastTrashSizeText) to Finder Trash. This is not a claim that disk space is free."
            }

            if Task.isCancelled {
                phase = .cancelled
                statusText = "Cleanup cancellation completed. No refresh scan was started."
                return
            }
            let roots = parsedExcludedRoots
            let scanWorker = Task.detached(priority: .utility) {
                DiskScanner(home: home, excludedLargeFileRelativePaths: roots).scan()
            }
            let snapshot = await withTaskCancellationHandler {
                await scanWorker.value
            } onCancel: {
                scanWorker.cancel()
            }
            apply(snapshot: snapshot, preserveResults: true)
        }
    }

    func writeReport() {
        let report = currentReport(mode: lastReportMode)
        do {
            lastReportURL = try ReportWriter.write(
                report: report,
                format: reportFormat,
                redaction: pathRedaction,
                destinationDirectory: reportDestinationDirectory
            )
            reportStatusText = "Report written: \(lastReportURL?.path ?? "unknown path")"
        } catch {
            reportStatusText = "Report failed: \(error.localizedDescription)"
        }
    }

    func chooseReportDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Report Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = reportDestinationDirectory
        if panel.runModal() == .OK { reportDestinationDirectory = panel.url }
    }

    func reveal(_ item: ScanItem) {
        guard item.path.hasPrefix("/") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func copyPath(_ item: ScanItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
        statusText = "Copied path."
    }

    func copyResult(_ result: CleanupResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(result.status): \(result.path) — \(result.detail)", forType: .string)
        statusText = "Copied result."
    }

    func requestAccessSettings() {
        statusText = "Opening Full Disk Access settings. macOS controls approval; run a new scan afterward."
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openReportsFolder() {
        if let reportDestinationDirectory {
            NSWorkspace.shared.open(reportDestinationDirectory)
        } else if let lastReportURL {
            NSWorkspace.shared.activateFileViewerSelecting([lastReportURL])
        }
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private var parsedExcludedRoots: [String] {
        excludedLargeFileRootsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(ManifestValidator.canonicalRelativePath)
    }

    private func matchesSearch(_ item: ScanItem) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return [item.displayName, item.path, item.group, item.manifestID ?? "", item.explanation]
            .contains { $0.localizedCaseInsensitiveContains(term) }
    }

    private func sorted(_ source: [ScanItem]) -> [ScanItem] {
        switch sortMode {
        case .largestFirst:
            return source.sorted { $0.sizeBytes > $1.sizeBytes }
        case .name:
            return source.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .risk:
            return source.sorted {
                if $0.risk.sortRank != $1.risk.sortRank { return $0.risk.sortRank < $1.risk.sortRank }
                return $0.sizeBytes > $1.sizeBytes
            }
        }
    }

    private func invalidatePreview() {
        authorization.invalidate()
        cleanupPlan = nil
        if phase == .previewed { phase = .reviewing }
    }

    private func apply(snapshot: ScanSnapshot, preserveResults: Bool = false) {
        items = snapshot.items.map { item in var copy = item; copy.isSelected = false; return copy }
        diskStatus = snapshot.diskStatus
        storageSummaries = snapshot.storageSummaries
        permissionDiagnostics = snapshot.permissionDiagnostics
        warnings = snapshot.warnings
        scanIssues = snapshot.issues
        scanCompleteness = snapshot.completeness
        accessStatus = snapshot.accessStatus
        scanDurationSeconds = snapshot.scanDurationSeconds
        invalidatePreview()
        if !preserveResults { cleanupResults = [] }
    }

    private func currentReport(mode: ReportMode) -> ScanReport {
        let reportPlan: CleanupPlan?
        switch mode {
        case .scan:
            reportPlan = nil
        case .dryRun:
            reportPlan = cleanupPlan
        case .cleanup:
            reportPlan = lastCompletedPlan
        }
        return ScanReport(
            mode: mode,
            timestamp: Date(),
            diskStatus: diskStatus,
            items: items,
            results: cleanupResults,
            storageSummaries: storageSummaries,
            permissionDiagnostics: permissionDiagnostics,
            warnings: warnings,
            issues: scanIssues,
            completeness: scanCompleteness,
            scanDurationSeconds: scanDurationSeconds,
            policyVersion: CleanupCatalog.policyVersion,
            manifestChecksum: CleanupCatalog.manifestChecksum,
            appVersion: DiskScanner().appVersion,
            accessStatus: accessStatus,
            cleanupPlan: reportPlan,
            movedToTrashBytes: lastTrashBytes
        )
    }

    private func appendLedger(mode: ReportMode, plan: CleanupPlan?, results: [CleanupResult], movedBytes: Int64) {
        do {
            lastLedgerURL = try OperationLedger.append(OperationLedgerEntry(
                mode: mode,
                planID: plan?.id,
                manifestVersion: CleanupCatalog.policyVersion,
                manifestChecksum: CleanupCatalog.manifestChecksum,
                results: results,
                movedToTrashBytes: movedBytes
            ))
        } catch {
            reportStatusText = "Operation completed, but ledger append failed: \(error.localizedDescription)"
        }
    }
}
