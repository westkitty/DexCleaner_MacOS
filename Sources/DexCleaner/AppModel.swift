import Foundation
import DexCleanerCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var diskStatus = DiskStatus()
    @Published var cleanupResults: [CleanupResult] = []
    @Published var storageSummaries: [StorageSummaryItem] = []
    @Published var permissionDiagnostics: [PermissionDiagnostic] = []
    @Published var warnings: [String] = []
    @Published var statusText = "Ready. Scan is read-only."
    @Published var isWorking = false
    @Published var lastReportURL: URL?
    @Published var fullDiskAccessStatus = "Unknown"
    @Published var scanDurationSeconds: TimeInterval = 0

    private var activeTask: Task<Void, Never>?
    private let scanner = DiskScanner()
    private let runner = CleanupRunner()

    var cleanableItems: [ScanItem] { items.filter { $0.action == .moveToTrash } }
    var auditItems: [ScanItem] { items.filter { $0.action == .auditOnly && $0.category != .protected && $0.category != .cloudStorage } }
    var protectedItems: [ScanItem] { items.filter { $0.category == .protected || $0.category == .cloudStorage || $0.risk == .forbidden } }
    var selectedItems: [ScanItem] { items.filter { $0.isSelected } }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var cleanableBytes: Int64 {
        cleanableItems.reduce(0) { $0 + $1.sizeBytes }
    }

    func scan() {
        activeTask?.cancel()
        cleanupResults = []
        statusText = "Scanning..."
        isWorking = true
        activeTask = Task {
            let snapshot = await Task.detached(priority: .userInitiated) { scanner.scan() }.value
            if Task.isCancelled { return }
            apply(snapshot: snapshot)
            statusText = snapshot.cancelled ? "Scan cancelled." : "Scan complete. Review before selecting anything."
            isWorking = false
        }
    }

    func cancel() {
        activeTask?.cancel()
        statusText = "Cancellation requested. Waiting for active command to return."
    }

    func selectSafe() {
        items = items.map { item in
            var copy = item
            copy.isSelected = item.isCleanable
            return copy
        }
    }

    func clearSelection() {
        items = items.map { item in
            var copy = item
            copy.isSelected = false
            return copy
        }
    }

    func toggle(_ item: ScanItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[index].isCleanable else { return }
        items[index].isSelected.toggle()
    }

    func previewSelected() {
        let selected = selectedItems
        cleanupResults = runner.dryRunSelected(selected)
        statusText = "Dry-run preview complete. Nothing was moved."
        writeReport(mode: .dryRun)
    }

    func cleanSelected() {
        let selected = selectedItems
        guard !selected.isEmpty else {
            statusText = "No selected cleanup candidates."
            return
        }
        activeTask?.cancel()
        isWorking = true
        statusText = "Moving exact selected targets to Trash..."
        activeTask = Task {
            let results = await Task.detached(priority: .userInitiated) { runner.cleanSelected(selected) }.value
            if Task.isCancelled { return }
            cleanupResults = results
            statusText = "Cleanup attempt complete. Refreshing scan..."
            let snapshot = await Task.detached(priority: .userInitiated) { scanner.scan() }.value
            apply(snapshot: snapshot, preserveResults: true)
            statusText = "Cleanup complete. Review results."
            isWorking = false
            writeReport(mode: .cleanup)
        }
    }

    func writeReport(mode: ReportMode = .scan) {
        let report = ScanReport(
            mode: mode,
            timestamp: Date(),
            diskStatus: diskStatus,
            items: items,
            results: cleanupResults,
            storageSummaries: storageSummaries,
            permissionDiagnostics: permissionDiagnostics,
            warnings: warnings,
            scanDurationSeconds: scanDurationSeconds,
            policyVersion: CleanupCatalog.policyVersion,
            appVersion: scanner.appVersion,
            fullDiskAccessStatus: fullDiskAccessStatus
        )
        do {
            lastReportURL = try ReportWriter.write(report: report)
            statusText = "Report written: \(lastReportURL?.path ?? "unknown path")"
        } catch {
            statusText = "Report failed: \(error.localizedDescription)"
        }
    }

    private func apply(snapshot: ScanSnapshot, preserveResults: Bool = false) {
        items = snapshot.items
        diskStatus = snapshot.diskStatus
        storageSummaries = snapshot.storageSummaries
        permissionDiagnostics = snapshot.permissionDiagnostics
        warnings = snapshot.warnings
        fullDiskAccessStatus = snapshot.fullDiskAccessStatus
        scanDurationSeconds = snapshot.scanDurationSeconds
        if !preserveResults { cleanupResults = [] }
    }
}
