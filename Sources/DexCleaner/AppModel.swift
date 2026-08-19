import AppKit
import DexCleanerCore
import Foundation
import SwiftUI
import UserNotifications

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

    var explanation: String {
        switch self {
        case .all:
            return "Shows every exact manifest-authorized cleanup candidate."
        case .appleDevelopment:
            return "Shows Xcode, Swift, and Simulator cache candidates."
        case .packageManagers:
            return "Shows package-manager cache candidates only."
        case .appCaches:
            return "Shows exact application runtime-cache candidates only."
        }
    }

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

struct ExclusionInputValidation: Equatable {
    let accepted: [String]
    let rejected: [String]

    var summary: String {
        if accepted.isEmpty && rejected.isEmpty { return "No additional exclusions configured." }
        if rejected.isEmpty { return "\(accepted.count) additional exclusion\(accepted.count == 1 ? "" : "s") accepted." }
        return "\(accepted.count) accepted | \(rejected.count) invalid ignored."
    }
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
    @Published var lastScanDate: Date?
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
    @Published var lastRefreshAt: Date?
    @Published var lastScanAt: Date?
    @Published var lastVerifiedCapacityChangeBytes: Int64?
    @Published var launchAtLoginEnabled = false
    @Published var cleanupConfirmationRequested = false
    @Published private var capacityPresentationDate = Date()
    @Published var selectedHistoryRange: CapacityResolution = .day
    @Published var historyStatistics = CapacityRangeStatistics(records: [], start: Date(), end: Date(), validCount: 0, failedOrDisputedCount: 0, expectedCount: 0, coveragePercent: 0, longestGap: 0, containsGap: false, netChange: nil, minimum: nil, maximum: nil, average: nil)
    @Published var historySummary = CapacityHistorySummary(rawSampleCount: 0, aggregateCount: 0, oldest: nil, newest: nil, bytes: 0, schemaVersion: CapacitySample.schemaVersion, growthSuspended: false)
    @Published var alertConfiguration = StorageAlertConfiguration()
    @Published var alertState = StorageAlertState()
    @Published var alertText = "Storage warning monitoring is active. Notifications are optional."
    @Published var notificationsAvailable = "Not requested"
    @Published var storageDrivers: [StorageDriver] = []
    @Published var driverStatusText = "No Storage Driver snapshot has run. Drivers are diagnostic only."
    @Published var significantDropText: String?
    @Published var historyEvents: [CapacityEvent] = []
    @Published var requestedPrimarySection: String?
    @Published var recorderStatusText = RecorderStatus.armed.rawValue
    @Published var recorderCoverageText = "Starting recorder"
    @Published var recorderReserveText = "Pending Safe Conditions"
    @Published var incidents: [StorageIncident] = []
    @Published var diagnosticOperations: [DiagnosticOperation] = []
    @Published var cloudEvidence: [CloudProviderEvidence] = []
    @Published var repeatedPattern: RepeatedPattern?
    @Published var localCloudComparisons: [CopyComparisonResult] = []
    @Published var emergencyReserveActivity: EmergencyReserveStatus?
    @Published var deepTraceEvidence: DeepTraceEvidence?
    @Published var incidentActionText = ""

    private var activeTask: Task<Void, Never>?
    private var diagnosticCancellation = DiagnosticCancellationToken()
    private var freshnessExpiryTask: Task<Void, Never>?
    private var periodicCapacityTimer: Timer?
    private var lastHistoryCompactionAt: Date?
    private var samplingGate = CapacitySamplingGate()
    private let capacityHistory = CapacityHistoryStore()
    private let driverStore = StorageDriverStore()
    private let eventStore = CapacityEventStore()
    private let alertStore = StorageAlertStateStore()
    private var authorization = PreviewAuthorization()
    private var lastReportMode: ReportMode = .scan
    private let runner = CleanupRunner()
    private let operationCoordinator = OperationCoordinator()
    private let incidentRecorder: StorageIncidentRecorder
    private let certificationMode: Bool

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
    var scanDurationText: String { scanDurationSeconds > 0 ? String(format: "%.1f s", scanDurationSeconds) : "Not run" }
    var selectedRunningProcessCount: Int { selectedItems.filter(\.owningProcessRunning).count }
    var selectedGroupNames: [String] { Array(Set(selectedItems.map(\.group))).sorted() }
    var selectedGroupSummary: String {
        guard !selectedGroupNames.isEmpty else { return "No groups selected" }
        if selectedGroupNames.count <= 3 { return selectedGroupNames.joined(separator: ", ") }
        return selectedGroupNames.prefix(3).joined(separator: ", ") + " +\(selectedGroupNames.count - 3) more"
    }
    var canClean: Bool { canClean(at: Date()) }
    var hasCleanupOutcome: Bool { lastReportMode == .cleanup && !cleanupResults.isEmpty && lastCompletedPlan != nil }
    private var presentationDiskStatus: DiskStatus {
        StorageCapacityProvider.presentationStatus(diskStatus, now: capacityPresentationDate)
    }
    var availableForWorkText: String { formatted(presentationDiskStatus.availableForWorkBytes) }
    var immediatelyFreeText: String { formatted(presentationDiskStatus.immediatelyFreeBytes) }
    var totalCapacityText: String { formatted(presentationDiskStatus.totalBytes) }
    var usedEstimateText: String { formatted(presentationDiskStatus.usedEstimateBytes) }
    var potentiallyPurgeableText: String { formatted(presentationDiskStatus.potentiallyPurgeableBytes) }
    var lastCapacityChangeText: String {
        guard let bytes = lastVerifiedCapacityChangeBytes else { return "Not measured" }
        let prefix = bytes > 0 ? "+" : ""
        return prefix + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    var measurementStatusText: String { presentationDiskStatus.state.rawValue }
    var menuBarCapacityText: String {
        let marker: String
        switch presentationDiskStatus.state {
        case .fresh: marker = ""
        case .cached: marker = " C"
        case .partial: marker = " P"
        case .disputed: marker = " !"
        case .failed: marker = " —"
        }
        return diskStatus.availableForWorkBytes == nil ? "Storage\(marker)" : "\(availableForWorkText)\(marker)"
    }
    var manifestAuthorityText: String {
        CleanupCatalog.isAvailable ? "Manifest \(CleanupCatalog.policyVersion) | \(CleanupCatalog.manifestChecksum)" : "Cleanup disabled: manifest invalid"
    }
    var reportDestinationText: String {
        if let reportDestinationDirectory { return reportDestinationDirectory.path }
        if let lastReportURL { return lastReportURL.deletingLastPathComponent().path }
        return "Desktop (default)"
    }
    var reportModeText: String { lastReportMode.rawValue }
    var reportPreflightText: String {
        let planText: String
        switch lastReportMode {
        case .scan:
            planText = "no cleanup plan"
        case .dryRun, .cleanup:
            planText = reportPlan(for: lastReportMode) == nil ? "no retained plan" : "plan metadata included"
        }
        return "Mode: \(lastReportMode.rawValue) | \(items.count) findings | \(cleanupResults.count) results | \(reportFormat.rawValue) | \(pathRedaction.rawValue) | \(planText)"
    }
    var exclusionInputValidation: ExclusionInputValidation {
        let tokens = excludedLargeFileRootsText
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var accepted: [String] = []
        var rejected: [String] = []
        var seenAccepted = Set<String>()
        var seenRejected = Set<String>()
        for token in tokens {
            if let canonical = ManifestValidator.canonicalRelativePath(token) {
                if seenAccepted.insert(canonical).inserted { accepted.append(canonical) }
            } else if seenRejected.insert(token).inserted {
                rejected.append(token)
            }
        }
        return ExclusionInputValidation(accepted: accepted, rejected: rejected)
    }

    func canClean(at date: Date) -> Bool {
        !isWorking && authorization.isValid(items: items, plan: cleanupPlan, now: date)
    }

    func cleanupReadinessText(at date: Date = Date()) -> String {
        if isWorking { return "Another operation is active. Cleanup controls are locked until it finishes or is cancelled." }
        if selectedItems.isEmpty { return "Select one or more exact cache candidates before Preview can authorize a cleanup plan." }
        guard let plan = cleanupPlan else {
            return "Preview the current \(selectedItems.count) selected item\(selectedItems.count == 1 ? "" : "s") before Move to Trash becomes available."
        }
        let age = date.timeIntervalSince(plan.createdAt)
        if age < 0 || age > PreviewAuthorization.maximumPlanAge {
            return "Preview expired after fifteen minutes. Run Preview again before moving anything to Trash."
        }
        if !authorization.isValid(items: items, plan: plan, now: date) {
            return "Preview is stale because the authorized selection changed. Run Preview again."
        }
        return "Ready: exact plan \(plan.id.uuidString.prefix(8)) authorizes \(plan.items.count) item\(plan.items.count == 1 ? "" : "s") for Finder Trash until the fifteen-minute preview window expires."
    }

    func previewRemainingText(at date: Date = Date()) -> String {
        guard let plan = cleanupPlan else { return "No active Preview authorization" }
        let age = date.timeIntervalSince(plan.createdAt)
        guard age >= 0 else { return "Preview clock invalid - run Preview again" }
        let remaining = PreviewAuthorization.maximumPlanAge - age
        guard remaining > 0 else { return "Preview expired - run Preview again" }
        let whole = Int(remaining.rounded(.down))
        return String(format: "Preview expires in %02d:%02d", whole / 60, whole % 60)
    }

    func scanFreshnessText(at date: Date = Date()) -> String {
        guard let lastScanDate else { return "No scan yet" }
        let age = max(0, date.timeIntervalSince(lastScanDate))
        if age < 60 { return "Scanned just now" }
        if age < 3600 { return "Scanned \(Int(age / 60)) min ago" }
        if age < 86_400 { return "Scanned \(Int(age / 3600)) hr ago" }
        return "Scanned \(Int(age / 86_400)) day\(age < 172_800 ? "" : "s") ago"
    }

    func scanIsStale(at date: Date = Date()) -> Bool {
        guard let lastScanDate else { return false }
        return date.timeIntervalSince(lastScanDate) > 30 * 60
    }

    func measurementAgeText(for item: ScanItem, at date: Date = Date()) -> String {
        guard let measuredAt = item.measuredAt else { return item.measurementSource.rawValue }
        let age = max(0, date.timeIntervalSince(measuredAt))
        let ageText: String
        if age < 60 { ageText = "just now" }
        else if age < 3600 { ageText = "\(Int(age / 60)) min ago" }
        else { ageText = "\(Int(age / 3600)) hr ago" }
        return "\(item.measurementSource.rawValue) | \(ageText)"
    }

    func measurementIsStale(for item: ScanItem, at date: Date = Date()) -> Bool {
        guard let measuredAt = item.measuredAt else { return false }
        return date.timeIntervalSince(measuredAt) > 15 * 60
    }

    init(performStartupReconciliation: Bool = true, certificationMode: Bool = false) {
        self.certificationMode = certificationMode
        if certificationMode {
            let isolatedHome = FileManager.default.temporaryDirectory
                .appendingPathComponent("DexCleaner-UICertification-\(ProcessInfo.processInfo.processIdentifier)")
            incidentRecorder = StorageIncidentRecorder(store: IncidentStore(home: isolatedHome.path))
            let fixedDate = Date(timeIntervalSince1970: 1_735_689_600)
            diskStatus = DiskStatus(
                filesystem: "Certification Volume",
                totalBytes: 500_000_000_000,
                immediatelyFreeBytes: 18_000_000_000,
                availableForWorkBytes: 24_000_000_000,
                opportunisticBytes: 20_000_000_000,
                potentiallyPurgeableBytes: 6_000_000_000,
                usedEstimateBytes: 476_000_000_000,
                state: .fresh,
                measuredAt: fixedDate,
                source: "Deterministic certification fixture",
                detail: "Deterministic capacity evidence. No live scan or cleanup occurred."
            )
            lastRefreshAt = fixedDate
            launchAtLoginEnabled = false
            recorderStatusText = RecorderStatus.recording.rawValue
            recorderCoverageText = "Complete"
            recorderReserveText = ReserveState.pending.rawValue
            statusText = "Rendered UI certification fixture"
            return
        }
        incidentRecorder = StorageIncidentRecorder()
        diskStatus = StorageCapacityProvider.measure()
        alertState = alertStore.load()
        alertConfiguration = alertStore.loadConfiguration()
        historyEvents = eventStore.all()
        lastRefreshAt = diskStatus.measuredAt
        scheduleFreshnessExpiry()
        storageDrivers = StorageDriverCatalog.defaults() + driverStore.watchlist()
        sampleCapacity(trigger: .applicationLaunch, status: diskStatus, force: true)
        installMonitoringLifecycle()
        guard performStartupReconciliation else {
            statusText = "Another DexCleaner instance is active. This process will exit without mutation authority."
            return
        }
        do {
            let reconciled = try OperationLedger.reconcilePendingOperations()
            if !reconciled.isEmpty {
                statusText = "Interrupted operation evidence was reconciled without retry. Review the local ledger."
                lastLedgerURL = OperationLedger.ledgerURL()
            }
        } catch {
            statusText = "Ledger reconciliation failed: \(error.localizedDescription)"
        }
        Task { @MainActor [weak self] in
            // Let SwiftUI construct the menu extra and command paths before recovery can publish.
            await Task.yield()
            guard let self else { return }
            self.incidentRecorder.start(sample: self.diskStatus)
            self.synchronizeRecorder()
        }
    }

    func refreshCapacity(trigger: CapacityTrigger = .manualRefresh) {
        guard !isWorking, operationCoordinator.begin() else {
            statusText = "Another operation is still finishing."
            return
        }
        isWorking = true
        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
                operationCoordinator.end()
            }
            let previous = diskStatus
            let measured = await Task.detached(priority: .userInitiated) {
                StorageCapacityProvider.measure()
            }.value
            diskStatus = measured.state == .failed && previous.availableForWorkBytes != nil
                ? StorageCapacityProvider.cached(previous, reason: measured.detail)
                : measured
            lastRefreshAt = diskStatus.measuredAt
            scheduleFreshnessExpiry()
            sampleCapacity(trigger: trigger, status: diskStatus)
            statusText = "Capacity refreshed. Available for work is \(availableForWorkText); status is \(measurementStatusText)."
        }
    }

    func refreshCapacityForPresentation() {
        guard !isWorking else { return }
        refreshCapacity(trigger: .popoverOpening)
    }

    func scan() {
        guard !isWorking, operationCoordinator.begin() else {
            statusText = "Another operation is still finishing."
            return
        }
        invalidatePreview()
        cleanupResults = []
        lastTrashBytes = 0
        lastReportMode = .scan
        statusText = "Scanning read-only targets and audit areas..."
        phase = .scanning
        isWorking = true
        let roots = parsedExcludedRoots
        let home = NSHomeDirectory()

        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
                operationCoordinator.end()
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
            sampleCapacity(trigger: .quickScanCompletion, status: snapshot.diskStatus)
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
        diagnosticCancellation.cancel()
        incidentRecorder.requestCancellation()
        activeTask?.cancel()
        phase = .cancelled
        statusText = "Cancellation requested. Active shell work is being terminated where possible."
    }

    func addVisibleCandidates() {
        let visibleIDs = Set(cleanableItems.map(\.id))
        var added = 0
        let updatedItems = items.map { item in
            var copy = item
            if copy.isCleanable && visibleIDs.contains(copy.id) && !copy.isSelected {
                copy.isSelected = true
                added += 1
            }
            return copy
        }
        guard added > 0 else {
            statusText = "All visible candidates were already selected. Existing Preview authorization was left unchanged."
            return
        }
        items = updatedItems
        selectionDidChange()
        statusText = "Added \(added) visible candidate\(added == 1 ? "" : "s") to the selection. Preview is required before cleanup."
    }

    func selectVisibleCandidates() {
        addVisibleCandidates()
    }

    func clearVisibleSelection() {
        let visibleIDs = Set(cleanableItems.map(\.id))
        var cleared = 0
        let updatedItems = items.map { item in
            var copy = item
            if visibleIDs.contains(copy.id) && copy.isSelected {
                copy.isSelected = false
                cleared += 1
            }
            return copy
        }
        guard cleared > 0 else {
            statusText = "No visible selected candidates to clear."
            return
        }
        items = updatedItems
        selectionDidChange()
        statusText = "Cleared \(cleared) visible selection\(cleared == 1 ? "" : "s")."
    }

    func clearSelection(reason: String? = nil) {
        items = items.map { item in
            var copy = item
            copy.isSelected = false
            return copy
        }
        selectionDidChange()
        if let reason { statusText = reason }
    }

    func toggle(_ item: ScanItem) {
        guard !isWorking, let index = items.firstIndex(where: { $0.id == item.id }), items[index].isCleanable else { return }
        items[index].isSelected.toggle()
        selectionDidChange()
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
            statusText = "Preview blocked. No cleanup plan was authorized. Review Results for the blocking evidence before changing the selection or retrying."
        }
        appendLedger(mode: .dryRun, plan: outcome.plan, results: outcome.results, movedBytes: 0)
    }

    func cleanConfirmed() {
        guard canClean, let plan = cleanupPlan else {
            statusText = "Cleanup authorization is stale or missing. Run Preview again."
            return
        }
        guard operationCoordinator.begin() else {
            statusText = "Another mutation or scan operation already has authority."
            return
        }
        let pending: OperationLedgerEntry
        do {
            pending = try OperationLedger.begin(plan: plan)
            lastLedgerURL = OperationLedger.ledgerURL()
        } catch {
            operationCoordinator.end()
            statusText = "Cleanup blocked because the durable pending ledger record could not be written: \(error.localizedDescription)"
            return
        }
        let capacityBefore = diskStatus.availableForWorkBytes
        isWorking = true
        phase = .cleaning
        statusText = "Revalidating each previewed target immediately before moving it to Finder Trash..."
        let home = NSHomeDirectory()
        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
                operationCoordinator.end()
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
            do {
                lastLedgerURL = try OperationLedger.finish(
                    pending: pending,
                    results: results,
                    movedToTrashBytes: lastTrashBytes
                )
            } catch {
                reportStatusText = "Trash operation returned, but terminal ledger append failed: \(error.localizedDescription)"
            }
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
            sampleCapacity(trigger: .cleanupCompletion, status: snapshot.diskStatus, force: true)
            if let capacityBefore, let capacityAfter = snapshot.diskStatus.availableForWorkBytes {
                lastVerifiedCapacityChangeBytes = capacityAfter - capacityBefore
            } else {
                lastVerifiedCapacityChangeBytes = nil
            }
        }
    }

    func requestCleanupConfirmation() {
        guard canClean else {
            statusText = "Move to Trash remains disabled until the current selection has a valid Preview."
            return
        }
        cleanupConfirmationRequested = true
    }

    func dismissPreview() {
        cleanupConfirmationRequested = false
        guard cleanupPlan != nil || phase == .previewed else { return }
        invalidatePreview()
        phase = .reviewing
        statusText = "Preview closed. No files were moved; run Preview again before any cleanup."
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
        revealPath(item.path)
    }

    func canReveal(_ item: ScanItem) -> Bool {
        canRevealPath(item.path)
    }

    func revealPath(_ path: String) {
        guard canRevealPath(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func canRevealResult(_ result: CleanupResult) -> Bool {
        canRevealPath(result.path)
    }

    func revealResult(_ result: CleanupResult) {
        guard canRevealResult(result) else { return }
        revealPath(result.path)
    }

    func copyPath(_ item: ScanItem) {
        copyText(item.path)
    }

    func copyResult(_ result: CleanupResult) {
        copyText("\(result.status): \(result.path) - \(result.detail)")
    }

    func copyResults(_ results: [CleanupResult]) {
        let text = results.map { "\($0.status): \($0.path) - \($0.detail)" }.joined(separator: "\n")
        copyText(text)
    }

    func copyIssue(_ issue: ScanIssue) {
        copyText("\(issue.kind.rawValue): \(issue.area) - \(issue.detail)")
    }

    func copyDiagnosticsSummary() {
        var lines = [
            "DexCleaner diagnostics",
            "Scan: \(scanCompleteness.rawValue)",
            "Access: \(accessStatus)",
            "Duration: \(scanDurationText)",
            "Issues: \(scanIssues.count)",
            "Warnings: \(warnings.count)"
        ]
        lines.append(contentsOf: scanIssues.map { "Issue | \($0.kind.rawValue) | \($0.area) | \($0.detail)" })
        lines.append(contentsOf: warnings.map { "Warning | \($0)" })
        lines.append(contentsOf: permissionDiagnostics.map { "Access | \($0.title) | \($0.status) | \($0.detail)" })
        copyText(lines.joined(separator: "\n"))
    }

    func copyPlanPaths(_ plan: CleanupPlan) {
        copyText(plan.items.map(\.path).joined(separator: "\n"))
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
        } else {
            let directory = ReportWriter.defaultDirectory()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        }
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func refreshHistory(range: CapacityResolution? = nil) {
        if let range { selectedHistoryRange = range }
        let selected = selectedHistoryRange
        Task.detached { [capacityHistory] in
            let statistics = capacityHistory.statistics(range: selected)
            let summary = capacityHistory.summary()
            await MainActor.run { [weak self] in self?.historyStatistics = statistics; self?.historySummary = summary }
        }
    }

    func openStorageHistory() { requestedPrimarySection = "Storage History"; refreshHistory() }

    func openStorageIncidents() {
        requestedPrimarySection = "Storage Incidents"
        if !certificationMode { synchronizeRecorder() }
    }

    func investigateNow() {
        guard !isWorking else { return }
        statusText = "Investigating capacity loss with bounded diagnostic evidence. No cleanup authority is created."
        let measured = StorageCapacityProvider.measure()
        diskStatus = measured
        incidentRecorder.investigateNow(status: measured)
        let roots = DiagnosticCatalog.roots().map(\.0)
        incidentRecorder.investigateChangedRoots(roots)
        synchronizeRecorder()
    }

    func inspectCloudStorage() {
        guard !isWorking else { return }
        cloudEvidence = incidentRecorder.inspectCloud()
        synchronizeRecorder()
        statusText = "Cloud inspection completed with placeholder-aware allocation semantics. No provider state changed."
    }
    func refreshRepeatedPattern() { incidentRecorder.refreshRepeatedPattern(); synchronizeRecorder(); statusText = "Repeated-pattern analysis completed. Findings remain diagnostic only." }

    func compareCopies(localPath: String, cloudPath: String, provider: String) {
        guard !isWorking else { return }
        let local = URL(fileURLWithPath: NSString(string: localPath).expandingTildeInPath)
        let cloud = URL(fileURLWithPath: NSString(string: cloudPath).expandingTildeInPath)
        guard !localPath.isEmpty, !cloudPath.isEmpty else {
            incidentActionText = "Choose both ordinary local directories first."
            return
        }
        diagnosticCancellation = DiagnosticCancellationToken()
        let cancellation = diagnosticCancellation
        let lowSpace = (diskStatus.immediatelyFreeBytes ?? 0) < alertConfiguration.criticalBytes
        let providerName = provider.isEmpty ? "Unspecified provider" : provider
        let operation = incidentRecorder.beginDiagnosticOperation(type: "Local/cloud comparison", phase: "Comparing resident metadata")
        isWorking = true
        incidentActionText = "Comparing…"
        activeTask = Task { [weak self] in
            let result = await Task.detached {
                LocalCloudComparator.compare(local: local, cloud: cloud, provider: providerName, lowSpace: lowSpace, isCancelled: { cancellation.isCancelled })
            }.value
            guard let self else { return }
            self.incidentRecorder.recordComparisonResult(result, operationID: operation)
            self.isWorking = false
            self.synchronizeRecorder()
            self.incidentActionText = result.coverage == .cancelled ? "Comparison cancelled; partial evidence retained." : "Comparison complete"
        }
    }

    func requestDeepTraceExplanation() {
        guard !isWorking else { return }
        diagnosticCancellation = DiagnosticCancellationToken()
        let cancellation = diagnosticCancellation
        isWorking = true
        incidentActionText = "Tracing…"
        let paths = incidents.first?.measurements.map(\.path) ?? []
        activeTask = Task { [weak self] in
            let result = await Task.detached {
                DeepTraceController.runBounded(incidentPaths: paths, isCancelled: { cancellation.isCancelled })
            }.value
            guard let self else { return }
            self.incidentRecorder.recordDeepTraceEvidence(result)
            self.isWorking = false
            self.synchronizeRecorder()
            self.deepTraceEvidence = result
            self.incidentActionText = result.state == .requiresAuthorization
                ? "Deep trace requires per-run authorization. Normal recording remains armed."
                : result.summary
        }
    }

    func rebuildEmergencyReserve() {
        guard !isWorking else { return }
        let raw = historyStatistics.records.compactMap { record -> CapacitySample? in
            if case .raw(let sample) = record { return sample }
            return nil
        }.sorted { $0.timestamp < $1.timestamp }
        let recent = raw.filter { Date().timeIntervalSince($0.timestamp) <= 1_800 }
        let values = recent.compactMap(\.immediatelyFreeBytes)
        let spansThirtyMinutes = (recent.last?.timestamp.timeIntervalSince(recent.first?.timestamp ?? Date()) ?? 0) >= 1_800
        let stable = spansThirtyMinutes && ((values.max() ?? 0) - (values.min() ?? 0) <= 64 * 1_024 * 1_024)
        diagnosticCancellation = DiagnosticCancellationToken()
        let cancellation = diagnosticCancellation
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let free = diskStatus.immediatelyFreeBytes ?? 0
        let operation = incidentRecorder.beginDiagnosticOperation(type: "Emergency reserve", phase: "Creating physically allocated reserve")
        isWorking = true
        incidentActionText = "Creating…"
        activeTask = Task { [weak self] in
            let outcome = await Task.detached { () -> Result<EmergencyReserveStatus, Error> in
                do {
                    return .success(try EmergencyReserveController.create(injectedHome: home, freeBytes: free, stable: stable, incidentActive: false, activeOperation: false, isCancelled: { cancellation.isCancelled }))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            switch outcome {
            case .success(let result):
                self.incidentRecorder.recordEmergencyReserveStatus(result, operationID: operation)
                self.incidentActionText = result.state.rawValue
            case .failure(let error):
                let cancelled = error is CancellationError
                let result = EmergencyReserveStatus(state: cancelled ? .pending : .failed, eligibilityReason: cancelled ? "Creation cancelled before atomic finalization" : "Creation failed", failureReason: error.localizedDescription)
                self.incidentRecorder.recordEmergencyReserveStatus(result, operationID: operation)
                self.incidentActionText = cancelled ? "Reserve creation cancelled safely." : "Reserve creation failed safely: \(error.localizedDescription)"
            }
            self.isWorking = false
            self.synchronizeRecorder()
        }
    }

    func copyLatestIncidentForChatGPT() {
        guard let incident = incidents.first else {
            incidentActionText = "No incident report is available."
            return
        }
        let markdownURL = incident.reportURLs.first { $0.pathExtension == "md" }
        guard let markdownURL, let text = try? String(contentsOf: markdownURL) else {
            incidentActionText = "No persisted Markdown incident report is available."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        incidentActionText = "Copied"
    }

    func exportLatestIncidentReport() {
        guard let report = incidents.first?.reportURLs.first else {
            incidentActionText = "No persisted incident report is available."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([report])
        incidentActionText = "Report Exported"
    }

    func finishIncident() {
        let urls = incidentRecorder.finishActiveIncident(status: StorageCapacityProvider.measure())
        synchronizeRecorder()
        if let markdown = urls.first(where: { $0.pathExtension == "md" }) {
            lastReportURL = markdown
            reportStatusText = "Incident report written: \(markdown.path)"
        }
    }

    func exportHistory(format: String) {
        let panel = NSSavePanel()
        panel.title = "Export DexCleaner Capacity History"
        panel.nameFieldStringValue = "DexCleaner-capacity-history.\(format)"
        panel.allowedContentTypes = format == "json" ? [.json] : [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try capacityHistory.exportData(range: selectedHistoryRange, format: format).write(to: url, options: .atomic)
            statusText = "Exported local capacity history to \(url.lastPathComponent)."
        } catch {
            statusText = "History export failed: \(error.localizedDescription)"
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                self?.notificationsAvailable = granted ? "Available" : "Unavailable"
                self?.alertText = granted ? "System notifications are available. Warning monitoring remains local." : "System notifications are unavailable; menu-bar and in-app warnings remain active."
                if let error { self?.alertText += " \(error.localizedDescription)" }
            }
        }
    }

    func snoozeStorageWarning() {
        alertState.snoozedUntil = Date().addingTimeInterval(3_600)
        alertStore.save(alertState)
        event("Notification snoozed", "Remind me in one hour.")
        alertText = "Low-storage notifications snoozed for one hour."
    }

    func muteStorageWarningUntilRecovery() {
        alertState.mutedUntilRecovery = true
        alertStore.save(alertState)
        event("Notification muted", "Muted until Immediately free recovers above the configured recovery threshold.")
        alertText = "Low-storage notifications muted until recovery."
    }

    func updateAlertThresholds(warningGB: Int, recoveryGB: Int, criticalGB: Int) {
        let billion: Int64 = 1_000_000_000
        let candidate = StorageAlertConfiguration(
            warningBytes: Int64(warningGB) * billion,
            recoveryBytes: Int64(recoveryGB) * billion,
            criticalBytes: Int64(criticalGB) * billion,
            minimumNotificationInterval: alertConfiguration.minimumNotificationInterval
        )
        guard candidate.isValid() else {
            alertText = "Thresholds were not changed: recovery must exceed warning, which must exceed critical."
            return
        }
        alertConfiguration = candidate
        alertStore.saveConfiguration(candidate)
        event("Alert configuration", "Warning \(warningGB) GB, recovery \(recoveryGB) GB, critical \(criticalGB) GB.")
        alertText = "Low-storage thresholds updated locally."
    }

    func addManualHistoryNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        event("Manual note", trimmed)
    }

    func addWatchlistDirectory(name: String, path: String) {
        do {
            let watch = try driverStore.addWatch(name: name, path: path)
            if !storageDrivers.contains(where: { $0.id == watch.id }) { storageDrivers.append(watch) }
            driverStatusText = "Watch added for read-only size measurement. It is not a cleanup target."
        } catch { driverStatusText = "Watchlist change failed: \(error.localizedDescription)" }
    }

    func removeWatchlistDirectory(_ driver: StorageDriver) {
        guard driver.isWatch else { return }
        do { try driverStore.removeWatch(driver.id); storageDrivers.removeAll { $0.id == driver.id }; driverStatusText = "Watch removed. Historical capacity and safety evidence were retained." }
        catch { driverStatusText = "Watch removal failed: \(error.localizedDescription)" }
    }

    func refreshStorageDriver(_ driver: StorageDriver) {
        driverStatusText = "Measuring \(driver.name) read-only. This does not authorize cleanup."
        let store = driverStore
        Task.detached {
            let snapshot = StorageDriverMeasurer.measure(driver)
            try? store.append(snapshot)
            await MainActor.run { [weak self] in
                self?.driverStatusText = "\(driver.name): \(snapshot.state.rawValue) measurement \(self?.formatted(snapshot.bytes) ?? "Unavailable"). Driver measurement is diagnostic only."
            }
        }
    }

    func refreshStorageDrivers() {
        guard !storageDrivers.isEmpty else { driverStatusText = "No Storage Drivers are configured."; return }
        for driver in storageDrivers { refreshStorageDriver(driver) }
    }

    func findWhatChanged() {
        let watches = storageDrivers.filter(\.isWatch)
        var newest: [UUID: DriverSnapshot] = [:]
        var earlier: [UUID: DriverSnapshot] = [:]
        for driver in watches {
            let snapshots = driverStore.snapshots(for: driver.id)
            if let last = snapshots.last { newest[driver.id] = last }
            if snapshots.count > 1 { earlier[driver.id] = snapshots[snapshots.count - 2] }
        }
        let comparison = StorageDriverAnalytics.compare(drivers: watches, newest: newest, earlier: earlier, capacityChange: historyStatistics.netChange)
        let increases = comparison.changes.filter { ($0.1 ?? 0) > 0 }.prefix(3).map { "\($0.0.name): measured increase \(formatted($0.1))" }.joined(separator: "; ")
        driverStatusText = increases.isEmpty ? "No comparable driver snapshots yet. Driver measurement is never cleanup authority." : "Likely contributors by measured increase: \(increases). \(comparison.confidence)."
    }

    private var parsedExcludedRoots: [String] {
        exclusionInputValidation.accepted
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

    private func selectionDidChange() {
        invalidatePreview()
        if !isWorking && scanCompleteness != .notRun {
            phase = .reviewing
        }
    }

    private func invalidatePreview() {
        authorization.invalidate()
        cleanupPlan = nil
        if lastReportMode == .dryRun {
            cleanupResults = []
            lastReportMode = .scan
        }
        if phase == .previewed { phase = .reviewing }
    }

    private func apply(snapshot: ScanSnapshot, preserveResults: Bool = false) {
        items = snapshot.items.map { item in
            var copy = item
            copy.isSelected = false
            return copy
        }
        diskStatus = snapshot.diskStatus
        storageSummaries = snapshot.storageSummaries
        permissionDiagnostics = snapshot.permissionDiagnostics
        warnings = snapshot.warnings
        scanIssues = snapshot.issues
        scanCompleteness = snapshot.completeness
        accessStatus = snapshot.accessStatus
        scanDurationSeconds = snapshot.scanDurationSeconds
        lastScanDate = snapshot.timestamp
        lastScanAt = snapshot.timestamp
        lastRefreshAt = snapshot.diskStatus.measuredAt
        scheduleFreshnessExpiry()
        invalidatePreview()
        if !preserveResults { cleanupResults = [] }
    }

    private func reportPlan(for mode: ReportMode) -> CleanupPlan? {
        switch mode {
        case .scan:
            return nil
        case .dryRun:
            return cleanupPlan
        case .cleanup:
            return lastCompletedPlan
        }
    }

    private func currentReport(mode: ReportMode) -> ScanReport {
        ScanReport(
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
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            accessStatus: accessStatus,
            cleanupPlan: reportPlan(for: mode),
            movedToTrashBytes: lastTrashBytes
        )
    }

    private func appendLedger(mode: ReportMode, plan: CleanupPlan?, results: [CleanupResult], movedBytes: Int64) {
        do {
            lastLedgerURL = try OperationLedger.append(OperationLedgerEntry(
                state: mode == .dryRun ? .preview : .completed,
                mode: mode,
                planID: plan?.id,
                manifestVersion: CleanupCatalog.policyVersion,
                manifestChecksum: CleanupCatalog.manifestChecksum,
                targets: plan?.items.map {
                    OperationLedgerTarget(
                        manifestID: $0.manifestID,
                        path: $0.path,
                        identity: $0.identity,
                        measuredSizeBytes: $0.sizeBytes
                    )
                } ?? [],
                results: results,
                movedToTrashBytes: movedBytes
            ))
        } catch {
            reportStatusText = "Operation completed, but ledger append failed: \(error.localizedDescription)"
        }
    }

    private func scheduleFreshnessExpiry() {
        freshnessExpiryTask?.cancel()
        capacityPresentationDate = Date()
        guard diskStatus.state == .fresh, let measuredAt = diskStatus.measuredAt else { return }
        let remaining = max(0, StorageCapacityProvider.freshnessInterval - Date().timeIntervalSince(measuredAt))
        freshnessExpiryTask = Task { [weak self] in
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.capacityPresentationDate = Date()
        }
    }

    private func installMonitoringLifecycle() {
        periodicCapacityTimer?.invalidate()
        periodicCapacityTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCapacity(trigger: .periodic) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let status = StorageCapacityProvider.measure()
                self.diskStatus = status
                self.incidentRecorder.afterWake(status: status)
                self.sampleCapacity(trigger: .wakeFromSleep, status: status, force: true)
                self.synchronizeRecorder()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let status = StorageCapacityProvider.measure()
                self.incidentRecorder.beforeSleep(status: status)
                self.sampleCapacity(trigger: .periodic, status: status, force: true)
                self.synchronizeRecorder()
            }
        }
        refreshHistory()
    }

    private func sampleCapacity(trigger: CapacityTrigger, status: DiskStatus, force: Bool = false) {
        incidentRecorder.ingest(status: status, trigger: trigger.rawValue, wakeState: trigger == .wakeFromSleep ? "Woke" : "Active")
        incidentRecorder.handleEmergencyCapacity(home: URL(fileURLWithPath: NSHomeDirectory()), immediatelyFreeBytes: status.immediatelyFreeBytes)
        synchronizeRecorder()
        guard force || samplingGate.accepts() else { return }
        let sample = CapacitySample(status: status, trigger: trigger)
        let decision = StorageAlertEngine.evaluate(immediatelyFreeBytes: sample.immediatelyFreeBytes, configuration: alertConfiguration, state: alertState)
        alertState = decision.state
        alertStore.save(alertState)
        switch decision.event {
        case .warningCrossed: event("Low-storage threshold crossing", "Immediately free is below \(formatted(alertConfiguration.warningBytes)).")
        case .criticalCrossed: event("Critical threshold crossing", "Immediately free is below \(formatted(alertConfiguration.criticalBytes)).")
        case .recovered: event("Storage recovery", "Immediately free recovered above \(formatted(alertConfiguration.recoveryBytes))."); alertText = "Storage recovered above the configured recovery threshold."
        case .none: break
        }
        if alertState.activeSince != nil {
            let started = formatted(alertState.episodeStartedImmediatelyFreeBytes)
            alertText = "Low-storage episode began at \(started). Current immediately free: \(formatted(sample.immediatelyFreeBytes))."
        }
        if decision.shouldNotify { sendLocalNotification(for: decision.event, sample: sample) }
        let shouldCompact = lastHistoryCompactionAt.map { Date().timeIntervalSince($0) >= 86_400 } ?? true
        if shouldCompact { lastHistoryCompactionAt = Date() }
        let store = capacityHistory
        Task.detached { [store] in
            try? store.record(sample)
            if shouldCompact { try? store.compact() }
            let statistics = store.statistics(range: .day), summary = store.summary()
            await MainActor.run { [weak self] in
                self?.historyStatistics = statistics; self?.historySummary = summary
                self?.significantDropText = StorageDriverAnalytics.significantDrop(samples: statistics.records.compactMap { if case .raw(let sample) = $0 { return sample }; return nil })
            }
        }
    }

    private func sendLocalNotification(for event: StorageAlertEvent, sample: CapacitySample) {
        guard event == .warningCrossed || event == .criticalCrossed else { return }
        let content = UNMutableNotificationContent()
        content.title = event == .criticalCrossed ? "Critical low storage" : "Low storage"
        content.body = "Immediately free: \(formatted(sample.immediatelyFreeBytes)). Available for work: \(formatted(sample.availableForWorkBytes))."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "DexCleaner.storage.\(event.rawValue).\(UUID().uuidString)", content: content, trigger: nil))
    }

    private func event(_ kind: String, _ detail: String) {
        let value = CapacityEvent(kind: kind, detail: detail)
        try? eventStore.append(value)
        historyEvents.append(value)
    }

    private func formatted(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func synchronizeRecorder() {
        recorderStatusText = incidentRecorder.status.rawValue
        recorderCoverageText = incidentRecorder.coverage
        recorderReserveText = incidentRecorder.reserveState
        incidents = incidentRecorder.incidents
        diagnosticOperations = incidentRecorder.operations
        repeatedPattern = incidentRecorder.repeatedPattern
        localCloudComparisons = incidentRecorder.localCloudComparisons
        emergencyReserveActivity = incidents.first?.emergencyReserveActivity
        deepTraceEvidence = incidents.first?.deepTraceEvidence
    }

    private func canRevealPath(_ path: String) -> Bool {
        path.hasPrefix("/") && FileManager.default.fileExists(atPath: path)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
