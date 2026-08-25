import AppKit
import Charts
import DexCleanerCore
import SwiftUI

final class DexCleanerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let output = ProcessInfo.processInfo.environment["DEXCLEANER_CAMPAIGN_UI_CERTIFICATION_OUTPUT"] {
            do {
                try UICertificationRenderer.renderCampaign(to: URL(fileURLWithPath: output, isDirectory: true))
                NSApp.terminate(nil)
            } catch {
                fputs("Campaign UI certification failed: \(error)\n", stderr)
                NSApp.terminate(nil)
            }
            return
        }
        if let output = ProcessInfo.processInfo.environment["DEXCLEANER_UI_CERTIFICATION_OUTPUT"] {
            do {
                try UICertificationRenderer.renderAll(to: URL(fileURLWithPath: output, isDirectory: true))
                NSApp.terminate(nil)
            } catch {
                fputs("UI certification failed: \(error)\n", stderr)
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
        if let existing {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
        }
    }
}

@main
struct DexCleanerApp: App {
    @NSApplicationDelegateAdaptor(DexCleanerAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    init() {
        if ProcessInfo.processInfo.environment["DEXCLEANER_UI_CERTIFICATION_OUTPUT"] != nil || ProcessInfo.processInfo.environment["DEXCLEANER_CAMPAIGN_UI_CERTIFICATION_OUTPUT"] != nil {
            _model = StateObject(wrappedValue: AppModel(performStartupReconciliation: false, certificationMode: true))
            return
        }
        let identifier = Bundle.main.bundleIdentifier
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let anotherInstanceExists = identifier.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
                .contains { $0.processIdentifier != currentPID && !$0.isTerminated }
        } ?? false
        _model = StateObject(wrappedValue: AppModel(performStartupReconciliation: !anotherInstanceExists))
    }

    var body: some Scene {
        WindowGroup("DexCleaner", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowStyle(.titleBar)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 9) {
                if model.alertState.activeSince != nil {
                    Label(model.alertText, systemImage: model.alertState.criticalSent ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(model.alertState.criticalSent ? .red : .orange)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Available for work").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(model.availableForWorkText).font(.title2.monospacedDigit().weight(.bold))
                    }
                    Spacer()
                    Text(model.measurementStatusText)
                        .font(.caption.weight(.semibold))
                }
                Text(model.diskStatus.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Recorder: \(model.recorderStatusText) · \(model.recorderCoverageText)", systemImage: "record.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.recorderStatusText == "Recording" ? Color.secondary : Color.orange)
                Label(model.scanFreshnessText(), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.cleanupPlan != nil && !model.canClean {
                    Label("Preview stale or expired", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let active = model.diagnosticOperations.first, active.state == .running {
                    HStack { ProgressView().controlSize(.small); Text("\(active.type): \(active.phase)").font(.caption) }
                        .accessibilityLabel("Active diagnostic operation: \(active.type), \(active.phase)")
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                    menuMetric("Immediately free", model.immediatelyFreeText)
                    menuMetric("Total capacity", model.totalCapacityText)
                    menuMetric("Used estimate", model.usedEstimateText)
                    menuMetric("Safe cleanable", model.cleanableSizeText)
                    menuMetric("Selected", model.selectedSizeText)
                    menuMetric("Last moved to Trash", model.lastTrashSizeText)
                    menuMetric("Verified capacity change", model.lastCapacityChangeText)
                    menuMetric("Access", model.accessStatus)
                }
                Divider()
                menuHistory
                Divider()
                HStack {
                    Button("Refresh Capacity") { model.refreshCapacity() }.disabled(model.isWorking).dexInteractive()
                    Button("Quick Scan") { model.scan() }.disabled(model.isWorking).dexInteractive()
                    Button("Investigate Now") { model.investigateNow() }.disabled(model.isWorking).dexInteractive()
                }
                if model.isWorking {
                    Button("Cancel Active Operation") { model.cancel() }.dexInteractive()
                }
                Button("Select All Verified Safe Candidates") { model.selectVisibleCandidates() }
                    .disabled(model.cleanableItems.isEmpty || model.isWorking)
                    .dexInteractive()
                HStack {
                    Button("Clear Selection") { model.clearSelection() }
                        .disabled(model.selectedItems.isEmpty || model.isWorking)
                        .dexInteractive()
                    Button("Preview") { model.previewSelected() }
                        .disabled(model.selectedItems.isEmpty || model.isWorking)
                        .dexInteractive()
                    Button("Move to Trash") {
                        openMainWindow()
                        model.requestCleanupConfirmation()
                    }
                    .disabled(!model.canClean)
                }
                Divider()
                Text("Last refresh: \(timestamp(model.lastRefreshAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Last scan: \(timestamp(model.lastScanAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button { openMainWindow() } label: { Label("Open Full Window", systemImage: "macwindow") }.dexInteractive()
                    Button { openMainWindow(); model.openStorageIncidents() } label: { Label("Storage Incidents", systemImage: "record.circle") }.dexInteractive()
                    Button { openMainWindow(); model.openStorageHistory() } label: { Label("Open Storage History", systemImage: "chart.xyaxis.line") }.dexInteractive()
                }
                HStack {
                    Button { model.openTrash() } label: { Label("Open Trash", systemImage: "trash") }.dexInteractive()
                    Button("Reports") { model.openReportsFolder() }.dexInteractive()
                    Button("Quit") { model.quit() }.dexInteractive()
                    Spacer()
                }
            }
            .padding(12)
            .frame(width: 420)
            .onAppear { model.refreshCapacityForPresentation(); model.refreshHistory(range: .day) }
        } label: {
            Text(model.menuBarCapacityText)
                .accessibilityLabel("DexCleaner, \(model.availableForWorkText) available for work, \(model.measurementStatusText)")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuHistory: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("24-hour history").font(.caption.weight(.semibold))
                Spacer()
                Text(model.historyStatistics.containsGap ? "Gap recorded" : (model.historyStatistics.records.count < 2 ? "Building history" : trendText(model.historyStatistics.netChange)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Chart(model.historyStatistics.records) { record in
                if let value = record.availableForWorkBytes { LineMark(x: .value("Time", record.end), y: .value("Available", value)).foregroundStyle(Color.accentColor).interpolationMethod(.linear) }
                if let value = record.immediatelyFreeBytes { LineMark(x: .value("Time", record.end), y: .value("Free", value)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2])).interpolationMethod(.linear) }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 44)
            Text("Latest: \(timestamp(model.historyStatistics.records.last?.end)) · \(model.historyStatistics.records.count < 2 ? "Insufficient history" : "Net \(signed(model.historyStatistics.netChange))")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("24-hour capacity history. \(model.historyStatistics.records.count < 2 ? "Insufficient history." : trendText(model.historyStatistics.netChange))")
    }

    @ViewBuilder
    private func menuMetric(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption)
    }

    private func timestamp(_ date: Date?) -> String {
        StorageCapacityProvider.displayTimestamp(date)
    }

    private func signed(_ value: Int64?) -> String { guard let value else { return "Unavailable" }; return (value >= 0 ? "+" : "") + ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func trendText(_ value: Int64?) -> String { guard let value else { return "Stable or insufficient" }; if abs(value) < 250_000_000 { return "Approximately stable" }; return value > 0 ? "Rising" : "Falling" }

    private func openMainWindow() {
        NSApp.windows.first(where: { $0.level == .popUpMenu })?.orderOut(nil)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
