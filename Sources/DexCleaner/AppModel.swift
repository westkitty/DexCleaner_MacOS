import Foundation
import DexCleanerCore
import SwiftUI
import AppKit
import ServiceManagement

enum OperationPhase: String, CaseIterable {
    case idle = "Ready"
    case scanning = "Scanning"
    case previewing = "Previewing"
    case cleaning = "Moving to Trash"
    case refreshing = "Refreshing"
    case reporting = "Writing report"
    case cancelled = "Cancelled"
    case complete = "Complete"
}

enum CleanupProfile: String, CaseIterable, Identifiable {
    case all = "All"
    case appleDevelopment = "Apple Dev"
    case packageManagers = "Packages"
    case appCaches = "App Caches"
    case git = "Git"

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
        case .git:
            return item.category == .gitTemporaryPack || item.group == "Git"
        }
    }
}

enum ScanSortMode: String, CaseIterable, Identifiable {
    case largestFirst = "Largest"
    case group = "Group"
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
    @Published var statusText = "Ready. Scan is read-only."
    @Published var isWorking = false
    @Published var lastReportURL: URL?
    @Published var fullDiskAccessStatus = "Unknown"
    @Published var scanDurationSeconds: TimeInterval = 0
    @Published var phase: OperationPhase = .idle
    @Published var progress: Double = 0
    @Published var progressDetail = "No scan has run yet."
    @Published var activeProfile: CleanupProfile = .all
    @Published var sortMode: ScanSortMode = .largestFirst
    @Published var reportDestinationDirectory: URL?
    @Published var backgroundScanningEnabled = false
    @Published var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @Published var lastTrashBytes: Int64 = 0
    @Published var permissionRequestSummary = "Full Disk Access has not been requested in this session."

    private var activeTask: Task<Void, Never>?
    private var backgroundTimer: Timer?
    private let scanner = DiskScanner()
    private let runner = CleanupRunner()

    var cleanableItems: [ScanItem] {
        sorted(items.filter { $0.action == .moveToTrash && activeProfile.includes($0) })
    }

    var auditItems: [ScanItem] {
        sorted(items.filter { $0.action == .auditOnly && $0.category != .protected && $0.category != .cloudStorage })
    }

    var protectedItems: [ScanItem] {
        sorted(items.filter { $0.category == .protected || $0.category == .cloudStorage || $0.risk == .forbidden })
    }

    var selectedItems: [ScanItem] { items.filter { $0.isSelected } }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var cleanableBytes: Int64 {
        cleanableItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var auditBytes: Int64 {
        auditItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var protectedBytes: Int64 {
        protectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
    }

    var cleanableSizeText: String {
        ByteCountFormatter.string(fromByteCount: cleanableBytes, countStyle: .file)
    }

    var lastTrashSizeText: String {
        ByteCountFormatter.string(fromByteCount: lastTrashBytes, countStyle: .file)
    }

    func scan() {
        activeTask?.cancel()
        cleanupResults = []
        statusText = "Scanning..."
        phase = .scanning
        progress = 0.08
        progressDetail = "Reading exact manifest targets and disk pressure."
        isWorking = true
        let scannerHome = scanner.home
        activeTask = Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                DiskScanner(home: scannerHome).scan()
            }.value
            if Task.isCancelled { return }
            progress = 0.82
            progressDetail = "Sorting scan findings by reclaimable impact."
            apply(snapshot: snapshot)
            statusText = snapshot.cancelled ? "Scan cancelled." : "Scan complete. Review before selecting anything."
            phase = snapshot.cancelled ? .cancelled : .complete
            progress = 1
            progressDetail = snapshot.cancelled ? "Scan stopped before completion." : "Scan complete. Safe candidates remain unselected."
            isWorking = false
        }
    }

    func cancel() {
        activeTask?.cancel()
        statusText = "Cancellation requested. Waiting for active command to return."
        phase = .cancelled
        progressDetail = "Cancellation requested."
    }

    func selectSafe() {
        let visibleIDs = Set(cleanableItems.map(\.id))
        items = items.map { item in
            var copy = item
            copy.isSelected = item.isCleanable && visibleIDs.contains(item.id)
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
        phase = .previewing
        progress = 0.35
        progressDetail = "Checking selected paths against SafetyEngine."
        let selected = selectedItems
        cleanupResults = runner.dryRunSelected(selected)
        statusText = "Dry-run preview complete. Nothing was moved."
        phase = .complete
        progress = 1
        progressDetail = "Preview complete. Nothing was moved."
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
        phase = .cleaning
        progress = 0.12
        progressDetail = "SafetyEngine is checking every selected path."
        statusText = "Moving exact selected targets to Trash..."
        let runnerHome = runner.home
        let scannerHome = scanner.home
        let selectedSizes = Dictionary(uniqueKeysWithValues: selected.map { ($0.path, $0.sizeBytes) })
        activeTask = Task {
            let results = await Task.detached(priority: .userInitiated) {
                CleanupRunner(home: runnerHome).cleanSelected(selected)
            }.value
            if Task.isCancelled { return }
            cleanupResults = results
            lastTrashBytes = results.filter { $0.status == "Moved to Trash" }.reduce(Int64(0)) { partial, result in
                partial + (selectedSizes[result.path] ?? 0)
            }
            progress = 0.62
            phase = .refreshing
            progressDetail = "Trash move complete. Refreshing disk scan."
            statusText = "Cleanup attempt complete. Refreshing scan..."
            let snapshot = await Task.detached(priority: .userInitiated) {
                DiskScanner(home: scannerHome).scan()
            }.value
            apply(snapshot: snapshot, preserveResults: true)
            statusText = "Cleanup complete. Review results."
            phase = .complete
            progress = 1
            progressDetail = "Cleanup complete. Empty Trash manually to release all space."
            isWorking = false
            writeReport(mode: .cleanup)
        }
    }

    func writeReport(mode: ReportMode = .scan) {
        phase = .reporting
        progressDetail = "Writing report."
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
            lastReportURL = try ReportWriter.write(report: report, destinationDirectory: reportDestinationDirectory)
            statusText = "Report written: \(lastReportURL?.path ?? "unknown path")"
            phase = .complete
        } catch {
            statusText = "Report failed: \(error.localizedDescription)"
            phase = .complete
        }
    }

    func chooseReportDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Report Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = reportDestinationDirectory
        if panel.runModal() == .OK {
            reportDestinationDirectory = panel.url
            statusText = "Report destination: \(panel.url?.path ?? "default")"
        }
    }

    func reveal(_ item: ScanItem) {
        guard item.path.hasPrefix("/") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func toggleBackgroundScanning() {
        backgroundScanningEnabled.toggle()
        configureBackgroundScanning()
    }

    func openReportsFolder() {
        if let reportDestinationDirectory {
            NSWorkspace.shared.open(reportDestinationDirectory)
        } else if let lastReportURL {
            NSWorkspace.shared.activateFileViewerSelecting([lastReportURL])
        }
    }

    func requestAllPermissions() {
        phase = .scanning
        progress = 0.2
        progressDetail = "Opening the macOS Full Disk Access pane."
        permissionRequestSummary = "Grant Full Disk Access to DexCleaner once, then rescan. macOS does not allow apps to approve this silently."
        statusText = "Opening Privacy & Security. Add DexCleaner to Full Disk Access, then return here and scan."

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }

        triggerPermissionProbe()
        phase = .complete
        progress = 1
        progressDetail = "Permission request flow started. Rerun Scan after granting access."
    }

    func centerWindowIfNeeded() {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        for window in NSApp.windows where window.title == "DexCleaner" || window.contentViewController != nil {
            let width = min(max(window.frame.width, 1120), screenFrame.width)
            let height = min(max(window.frame.height, 760), screenFrame.height)
            let origin = NSPoint(
                x: screenFrame.midX - width / 2,
                y: screenFrame.midY - height / 2
            )
            window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginEnabled = false
                statusText = "Launch at login disabled."
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginEnabled = true
                statusText = "Launch at login enabled."
            }
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            statusText = "Launch at login failed: \(error.localizedDescription)"
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

    private func sorted(_ source: [ScanItem]) -> [ScanItem] {
        switch sortMode {
        case .largestFirst:
            return source.sorted { $0.sizeBytes > $1.sizeBytes }
        case .group:
            return source.sorted {
                if $0.group != $1.group { return $0.group < $1.group }
                return $0.sizeBytes > $1.sizeBytes
            }
        case .risk:
            return source.sorted {
                if $0.risk.sortRank != $1.risk.sortRank { return $0.risk.sortRank < $1.risk.sortRank }
                return $0.sizeBytes > $1.sizeBytes
            }
        }
    }

    private func configureBackgroundScanning() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        guard backgroundScanningEnabled else {
            statusText = "Background scans disabled."
            return
        }
        statusText = "Background scans enabled. DexCleaner will only scan, never clean automatically."
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isWorking else { return }
                self.scan()
            }
        }
    }

    private func triggerPermissionProbe() {
        let probePaths = [
            "Library/Mail",
            "Library/Safari",
            "Library/Messages",
            "Desktop",
            "Documents",
            "Downloads"
        ]
        let homeURL = URL(fileURLWithPath: scanner.home)
        for relativePath in probePaths {
            let url = homeURL.appendingPathComponent(relativePath)
            _ = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        }
        permissionDiagnostics = PermissionDiagnostics.evaluate(home: scanner.home)
        fullDiskAccessStatus = PermissionDiagnostics.summary(permissionDiagnostics)
    }
}
