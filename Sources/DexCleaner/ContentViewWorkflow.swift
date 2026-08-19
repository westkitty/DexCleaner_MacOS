import DexCleanerCore
import Foundation
import SwiftUI

extension ContentView {
    var workflowStrip: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            ViewThatFits(in: .horizontal) {
            HStack {
                workflowStep(1, "Scan", date: context.date)
                connector
                workflowStep(2, "Review", date: context.date)
                connector
                workflowStep(3, "Preview", date: context.date)
                connector
                workflowStep(4, "Confirm Trash Move", date: context.date)
                Spacer()
            }
            VStack(alignment: .leading) {
                workflowStep(1, "Scan", date: context.date)
                workflowStep(2, "Review", date: context.date)
                workflowStep(3, "Preview", date: context.date)
                workflowStep(4, "Confirm Trash Move", date: context.date)
            }
            }
            .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    var connector: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
    }

    func workflowStep(_ n: Int, _ title: String, date: Date) -> some View {
        let state = workflowState(n)
        return Button { performWorkflowStep(n, date: date) } label: {
            Label("\(n). \(title)", systemImage: state == 0 ? "checkmark.circle.fill" : state == 1 ? "circle.fill" : "circle")
                .font(.caption.weight(state == 1 ? .bold : .regular))
                .foregroundStyle(state == 2 ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!workflowStepEnabled(n, date: date))
        .accessibilityLabel("Step \(n), \(title), \(state == 0 ? "complete" : state == 1 ? "current" : "upcoming")")
        .accessibilityHint(workflowStepHint(n))
    }

    func workflowState(_ n: Int) -> Int {
        let current: Int
        switch model.phase {
        case .idle, .scanning: current = 1
        case .reviewing: current = 2
        case .previewed: current = 3
        case .cleaning: current = 4
        case .complete: current = 5
        case .cancelled, .failed:
            current = model.hasCleanupOutcome ? 5 : (!model.cleanupResults.isEmpty ? 3 : (model.scanCompleteness != .notRun ? 2 : 1))
        }
        if n < current { return 0 }
        return n == current ? 1 : 2
    }

    func workflowStepEnabled(_ n: Int, date: Date) -> Bool {
        switch n {
        case 1: return !model.isWorking
        case 2: return model.scanCompleteness != .notRun
        case 3: return !model.isWorking && (!model.selectedItems.isEmpty || !model.cleanupResults.isEmpty)
        case 4: return model.canClean(at: date)
        default: return false
        }
    }

    func workflowStepHint(_ n: Int) -> String {
        switch n {
        case 1: return "Starts a new explicit scan."
        case 2: return "Opens cleanup candidates."
        case 3:
            if model.selectedItems.isEmpty && !model.cleanupResults.isEmpty {
                return "Opens the latest Preview or cleanup results."
            }
            return model.cleanupPlan == nil ? "Runs a read-only Preview for the current selection." : "Runs Preview again when authorization is stale, otherwise opens Preview results."
        case 4: return "Opens the exact-path confirmation sheet when Preview authorization is valid."
        default: return ""
        }
    }

    func performWorkflowStep(_ n: Int, date: Date) {
        switch n {
        case 1: model.scan()
        case 2: tab = .cleanable
        case 3:
            if !model.selectedItems.isEmpty && (model.cleanupPlan == nil || !model.canClean(at: date)) { model.previewSelected() }
            tab = .results
        case 4: if model.canClean(at: date) { showConfirm = true }
        default: break
        }
    }

    var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack { metricCards }
            VStack { metricCards }
        }
    }

    @ViewBuilder var metricCards: some View {
        MetricCard("Available", model.diskStatus.available, "Capacity \(model.diskStatus.capacity)", "internaldrive")
        MetricCard("Cleanable", model.cleanableSizeText, "\(model.allCleanableItems.count) exact targets", "checkmark.shield")
        MetricCard("Selected", model.selectedSizeText, "\(model.selectedItems.count) selected", "checklist")
        MetricCard("Moved to Trash", model.lastTrashSizeText, "Finder Trash only", "trash")
        MetricCard("Access", model.accessStatus, "Last scan \(model.scanDurationText)", "lock.shield")
    }

    var scanDetails: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Diagnostics are local and copyable for troubleshooting.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    FeedbackButton(title: "Copy Diagnostics", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyDiagnosticsSummary() }
                }
                if !model.warnings.isEmpty { warningsSection }
                storageSummarySection
                accessDiagnosticsSection
            }.padding(.top, 8)
        } label: {
            Label("Scan details | storage | warnings | access", systemImage: "chart.bar").font(.headline)
        }
        .padding(11).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    var warningsSection: some View {
        DetailGroup("Warnings", "exclamationmark.triangle") {
            ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, value in
                Text(value).font(.caption).textSelection(.enabled)
            }
        }
    }

    var storageSummarySection: some View {
        DetailGroup("Storage summary", "internaldrive") {
            Text("Exact cleanable targets only; audit findings are not added into a reclaim total.").font(.caption).foregroundStyle(.secondary)
            if model.storageSummaries.isEmpty {
                Text(model.scanCompleteness == .notRun ? "Run Scan to measure targets." : "No measured cleanable summaries.").font(.caption)
            }
            ForEach(model.storageSummaries) { item in
                LabeledContent(item.label, value: item.formattedSize).font(.caption)
                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    var accessDiagnosticsSection: some View {
        DetailGroup("Access checks", "lock.shield") {
            if model.permissionDiagnostics.isEmpty {
                Text(model.scanCompleteness == .notRun ? "Run Scan to evaluate access." : "No access diagnostics recorded.").font(.caption)
            }
            ForEach(model.permissionDiagnostics) { d in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(d.title) | \(d.status)").font(.caption.weight(.semibold))
                    Text(d.detail).font(.caption2)
                    Text(d.remediation).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button("Open Full Disk Access Settings") { model.requestAccessSettings() }.buttonStyle(.bordered)
        }
    }

    var operationProgress: some View {
        HStack(spacing: 10) {
            if reduceMotion { Image(systemName: "hourglass") } else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading) {
                Text(model.phase.rawValue).font(.subheadline.weight(.semibold))
                Text("You can cancel without authorizing anything new.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { model.cancel() }.keyboardShortcut(".", modifiers: .command)
        }
        .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack {
                HStack {
                    Button { model.scan() } label: { Label("Scan Now", systemImage: "magnifyingglass") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking)
                        .keyboardShortcut("r", modifiers: .command)
                    Button("Add Visible (\(model.cleanableItems.count))") { model.addVisibleCandidates() }
                        .disabled(model.isWorking || model.cleanableItems.isEmpty)
                    Button("Clear Visible") { model.clearVisibleSelection() }
                        .disabled(model.isWorking || !hasVisibleSelection)
                    Button("Clear All (\(model.selectedItems.count))") { model.clearSelection(reason: "Selection cleared.") }
                        .disabled(model.isWorking || model.selectedItems.isEmpty)
                    Button("Preview \(model.selectedItems.count)") { model.previewSelected(); tab = .results }
                        .disabled(model.isWorking || model.selectedItems.isEmpty)
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Button { showConfirm = true } label: { Label("Move to Trash", systemImage: "trash") }
                            .disabled(!model.canClean(at: context.date))
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(model.cleanupReadinessText(at: context.date)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

}
