import DexCleanerCore
import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var tab: ReviewTab = .selected
    @State var showConfirm = false
    @State var showDetails = false
    @State var collapsedGroups: Set<String> = []
    @State var expandedRows: Set<UUID> = []
    @State var resultFilter: ResultFilter = .all
    @State private var primarySection = PrimarySection.review
    @FocusState var searchFocused: Bool
    @FocusState var confirmationCancelFocused: Bool

    enum PrimarySection: String, CaseIterable, Identifiable {
        case incidents = "Storage Incidents"
        case campaign = "Cleanup Campaign"
        case review = "Review"
        case history = "Storage History"
        case drivers = "Storage Drivers"
        var id: String { rawValue }
    }

    enum ReviewTab: String, CaseIterable, Identifiable {
        case selected = "Selected"
        case cleanable = "Candidates"
        case audit = "Audit Only"
        case protected = "Protected"
        case results = "Results"
        case issues = "Issues"
        var id: String { rawValue }
    }

    enum ResultFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case authorized = "Authorized"
        case moved = "Moved"
        case blocked = "Blocked"
        case failed = "Failed"
        case cancelled = "Cancelled"
        var id: String { rawValue }

        func includes(_ result: CleanupResult) -> Bool {
            switch self {
            case .all: return true
            case .authorized: return result.status == "Authorized for confirmation"
            case .moved: return result.status == "Moved to Trash"
            case .blocked: return result.status == "Blocked"
            case .failed: return result.status == "Failed"
            case .cancelled: return result.status == "Cancelled"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusBanner
                nextActionCard
                workflowStrip
                metrics
                scanDetails
                if model.isWorking { operationProgress }
                controls
                selectionImpact
                filterBar
                Picker("Section", selection: $primarySection) {
                    ForEach(PrimarySection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 560)
                if primarySection == .incidents {
                    StorageIncidentsView().environmentObject(model)
                } else if primarySection == .campaign {
                    CleanupCampaignView(reviewAction: { primarySection = .review; tab = .cleanable }).environmentObject(model)
                } else if primarySection == .review {
                    reviewTabs
                } else if primarySection == .history {
                    StorageHistoryView().environmentObject(model)
                } else {
                    StorageDriversView().environmentObject(model)
                }
                reportControls
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 620)
        .sheet(isPresented: $showConfirm, onDismiss: { model.cleanupConfirmationRequested = false }) { cleanupConfirmation }
        .animation(animation, value: model.phase)
        .animation(animation, value: model.isWorking)
        .animation(animation, value: tab)
        .animation(animation, value: resultFilter)
        .onChange(of: model.cleanupResults) { _ in
            resultFilter = .all
        }
        .onChange(of: model.cleanupConfirmationRequested) { requested in
            showConfirm = requested
        }
        .onChange(of: model.requestedPrimarySection) { requested in
            if requested == PrimarySection.incidents.rawValue { primarySection = .incidents }
            if requested == PrimarySection.history.rawValue { primarySection = .history }
            if requested == PrimarySection.drivers.rawValue { primarySection = .drivers }
        }
    }

    var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.18) }

    var shouldReviewOperationResults: Bool {
        guard model.cleanupPlan == nil, !model.cleanupResults.isEmpty else { return false }
        switch model.phase {
        case .failed, .cancelled, .complete:
            return true
        default:
            return false
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DexCleaner").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Exact cache authority. Explicit scan. Immutable preview. Finder Trash only.")
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: "No background cleaning", systemImage: "shield")
        }
    }

    var statusBanner: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            AdaptiveStack {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: phaseIcon).font(.title2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.phase.rawValue).font(.headline)
                            StatusPill(text: model.scanCompleteness.rawValue, systemImage: completenessIcon)
                            StatusPill(
                                text: model.scanFreshnessText(at: context.date),
                                systemImage: model.scanIsStale(at: context.date) ? "clock" : "clock"
                            )
                        }
                        Text(model.statusText).font(.callout).textSelection(.enabled)
                        Text(model.manifestAuthorityText).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        if model.scanIsStale(at: context.date) {
                            Label("The visible scan is over thirty minutes old. Re-scan before relying on audit freshness.", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("DexCleaner status")
                    .accessibilityValue("\(model.phase.rawValue). Scan \(model.scanCompleteness.rawValue). \(model.scanFreshnessText(at: context.date)). \(model.statusText)")
                    Spacer(minLength: 8)
                    HStack {
                        if !model.scanIssues.isEmpty {
                            Button("Review \(model.scanIssues.count) Issue\(model.scanIssues.count == 1 ? "" : "s")") { tab = .issues }
                        }
                        if !model.warnings.isEmpty || !model.permissionDiagnostics.isEmpty {
                            Button("Scan Details") { showDetails = true }
                        }
                    }.buttonStyle(.bordered)
                }
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    var nextActionCard: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: nextActionIcon(at: context.date)).font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next safe action").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(nextActionTitle(at: context.date)).font(.headline)
                    Text(nextActionDetail(at: context.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Button(nextActionButtonTitle(at: context.date)) { performNextAction(at: context.date) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    func nextActionTitle(at date: Date) -> String {
        if model.isWorking { return "Let the active operation finish or cancel it" }
        if model.scanCompleteness == .notRun { return "Run an explicit scan" }
        if !model.scanIssues.isEmpty && model.scanCompleteness != .complete { return "Review scan issues before trusting gaps" }
        if model.canClean(at: date) { return "Confirm the authorized Finder Trash move" }
        if model.cleanupPlan != nil { return "Preview authorization expired - run Preview again" }
        if shouldReviewOperationResults { return "Review operation results" }
        if model.selectedItems.isEmpty { return "Review exact cleanup candidates" }
        return "Preview the selected exact paths"
    }

    func nextActionDetail(at date: Date) -> String {
        if model.isWorking { return "Cancellation does not authorize any new cleanup target." }
        if model.scanCompleteness == .notRun { return "DexCleaner stays idle until you request a scan." }
        if !model.scanIssues.isEmpty && model.scanCompleteness != .complete { return "Issues are evidence, not silent zeroes." }
        if model.canClean(at: date) { return "The final move still revalidates every previewed target immediately before Trash." }
        if model.cleanupPlan != nil { return "Expired authorization cannot move anything. Re-preview the unchanged selection to establish a new plan." }
        if shouldReviewOperationResults { return "Blocked, failed, cancelled, and moved outcomes remain visible before you start another workflow." }
        if model.selectedItems.isEmpty { return "Selection is explicit and starts empty after each scan." }
        return "Preview is read-only and binds the exact selection to filesystem identity."
    }

    func nextActionButtonTitle(at date: Date) -> String {
        if model.isWorking { return "Cancel" }
        if model.scanCompleteness == .notRun { return "Scan Now" }
        if !model.scanIssues.isEmpty && model.scanCompleteness != .complete { return "Review Issues" }
        if model.canClean(at: date) { return "Review Confirmation" }
        if model.cleanupPlan != nil { return "Preview Again" }
        if shouldReviewOperationResults { return "Review Results" }
        if model.selectedItems.isEmpty { return "Review Candidates" }
        return "Preview \(model.selectedItems.count)"
    }

    func nextActionIcon(at date: Date) -> String {
        if model.isWorking { return "hourglass" }
        if model.scanCompleteness == .notRun { return "magnifyingglass" }
        if !model.scanIssues.isEmpty && model.scanCompleteness != .complete { return "exclamationmark.triangle" }
        if model.canClean(at: date) { return "checkmark.shield" }
        if model.cleanupPlan != nil { return "arrow.clockwise" }
        if shouldReviewOperationResults { return "list.bullet.rectangle" }
        if model.selectedItems.isEmpty { return "list.bullet.rectangle" }
        return "doc.text"
    }

    func performNextAction(at date: Date) {
        if model.isWorking { model.cancel(); return }
        if model.scanCompleteness == .notRun { model.scan(); return }
        if !model.scanIssues.isEmpty && model.scanCompleteness != .complete { tab = .issues; return }
        if model.canClean(at: date) { showConfirm = true; return }
        if model.cleanupPlan != nil { model.previewSelected(); tab = .results; return }
        if shouldReviewOperationResults { tab = .results; return }
        if model.selectedItems.isEmpty { tab = .cleanable; return }
        model.previewSelected()
        tab = .results
    }

}
