import DexCleanerCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: ReviewTab = .selected
    @State private var showConfirm = false
    @State private var showDetails = false
    @FocusState private var searchFocused: Bool
    @FocusState private var confirmationCancelFocused: Bool

    enum ReviewTab: String, CaseIterable, Identifiable {
        case selected = "Selected", cleanable = "Candidates", audit = "Audit Only", protected = "Protected", results = "Results", issues = "Issues"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusBanner
                workflowStrip
                metrics
                scanDetails
                if model.isWorking { operationProgress }
                controls
                filterBar
                reviewTabs
                reportControls
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 620)
        .sheet(isPresented: $showConfirm) { cleanupConfirmation }
        .animation(animation, value: model.phase)
        .animation(animation, value: model.isWorking)
    }

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.18) }

    private var header: some View {
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

    private var statusBanner: some View {
        AdaptiveStack {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phaseIcon).font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(model.phase.rawValue).font(.headline); StatusPill(text: model.scanCompleteness.rawValue, systemImage: completenessIcon) }
                    Text(model.statusText).font(.callout).textSelection(.enabled)
                    Text(model.manifestAuthorityText).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("DexCleaner status")
                .accessibilityValue("\(model.phase.rawValue). Scan \(model.scanCompleteness.rawValue). \(model.statusText)")
                Spacer(minLength: 8)
                HStack {
                    if !model.scanIssues.isEmpty {
                        Button("Review \(model.scanIssues.count) Issue\(model.scanIssues.count == 1 ? "" : "s")") { tab = .issues }
                    }
                    if !model.warnings.isEmpty || !model.permissionDiagnostics.isEmpty { Button("Scan Details") { showDetails = true } }
                }.buttonStyle(.bordered)
            }
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var workflowStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack { workflowStep(1, "Scan"); connector; workflowStep(2, "Review"); connector; workflowStep(3, "Preview"); connector; workflowStep(4, "Confirm Trash Move"); Spacer() }
            VStack(alignment: .leading) { workflowStep(1, "Scan"); workflowStep(2, "Review"); workflowStep(3, "Preview"); workflowStep(4, "Confirm Trash Move") }
        }
        .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var connector: some View { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true) }
    private func workflowStep(_ n: Int, _ title: String) -> some View {
        let state = workflowState(n)
        return Label("\(n). \(title)", systemImage: state == 0 ? "checkmark.circle.fill" : state == 1 ? "circle.fill" : "circle")
            .font(.caption.weight(state == 1 ? .bold : .regular)).foregroundStyle(state == 2 ? .secondary : .primary)
            .accessibilityLabel("Step \(n), \(title), \(state == 0 ? "complete" : state == 1 ? "current" : "upcoming")")
    }
    private func workflowState(_ n: Int) -> Int {
        let current: Int
        switch model.phase {
        case .idle, .scanning: current = 1
        case .reviewing: current = 2
        case .previewed: current = 3
        case .cleaning, .complete: current = 4
        case .cancelled, .failed: current = model.lastCompletedPlan != nil ? 4 : (!model.cleanupResults.isEmpty ? 3 : (model.scanCompleteness != .notRun ? 2 : 1))
        }
        if model.phase == .complete || n < current { return 0 }
        return n == current ? 1 : 2
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack { metricCards }
            VStack { metricCards }
        }
    }
    @ViewBuilder private var metricCards: some View {
        MetricCard("Available", model.diskStatus.available, "Capacity \(model.diskStatus.capacity)", "internaldrive")
        MetricCard("Cleanable", model.cleanableSizeText, "\(model.allCleanableItems.count) exact targets", "checkmark.shield")
        MetricCard("Selected", model.selectedSizeText, "\(model.selectedItems.count) selected", "checklist")
        MetricCard("Moved to Trash", model.lastTrashSizeText, "Finder Trash only", "trash")
        MetricCard("Access", model.accessStatus, "Last scan \(model.scanDurationText)", "lock.shield")
    }

    private var scanDetails: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 12) {
                if !model.warnings.isEmpty { warningsSection }
                storageSummarySection
                accessDiagnosticsSection
            }.padding(.top, 8)
        } label: { Label("Scan details · storage · warnings · access", systemImage: "chart.bar").font(.headline) }
        .padding(11).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
    private var warningsSection: some View {
        DetailGroup("Warnings", "exclamationmark.triangle") {
            ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, value in Text(value).font(.caption).textSelection(.enabled) }
        }
    }
    private var storageSummarySection: some View {
        DetailGroup("Storage summary", "internaldrive") {
            Text("Exact cleanable targets only; audit findings are not added into a reclaim total.").font(.caption).foregroundStyle(.secondary)
            if model.storageSummaries.isEmpty { Text(model.scanCompleteness == .notRun ? "Run Scan to measure targets." : "No measured cleanable summaries.").font(.caption) }
            ForEach(model.storageSummaries) { item in LabeledContent(item.label, value: item.formattedSize).font(.caption); Text(item.detail).font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private var accessDiagnosticsSection: some View {
        DetailGroup("Access checks", "lock.shield") {
            if model.permissionDiagnostics.isEmpty { Text(model.scanCompleteness == .notRun ? "Run Scan to evaluate access." : "No access diagnostics recorded.").font(.caption) }
            ForEach(model.permissionDiagnostics) { d in
                VStack(alignment: .leading, spacing: 3) { Text("\(d.title) · \(d.status)").font(.caption.weight(.semibold)); Text(d.detail).font(.caption2); Text(d.remediation).font(.caption2).foregroundStyle(.secondary) }
            }
            Button("Open Full Disk Access Settings") { model.requestAccessSettings() }.buttonStyle(.bordered)
        }
    }

    private var operationProgress: some View {
        HStack(spacing: 10) {
            if reduceMotion { Image(systemName: "hourglass") } else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading) { Text(model.phase.rawValue).font(.subheadline.weight(.semibold)); Text("You can cancel without authorizing anything new.").font(.caption).foregroundStyle(.secondary) }
            Spacer(); Button("Cancel") { model.cancel() }.keyboardShortcut(".", modifiers: .command)
        }
        .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack {
                HStack {
                    Button { model.scan() } label: { Label("Scan Now", systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).disabled(model.isWorking)
                    Button("Select Visible (\(model.cleanableItems.count))") { model.selectVisibleCandidates() }.disabled(model.isWorking || model.cleanableItems.isEmpty)
                    Button("Clear (\(model.selectedItems.count))") { model.clearSelection(reason: "Selection cleared.") }.disabled(model.isWorking || model.selectedItems.isEmpty)
                    Button("Preview \(model.selectedItems.count)") { model.previewSelected(); tab = .results }.disabled(model.isWorking || model.selectedItems.isEmpty)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Button { showConfirm = true } label: { Label("Move to Trash", systemImage: "trash") }.disabled(!model.canClean(at: context.date))
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in Text(model.cleanupReadinessText(at: context.date)).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            AdaptiveStack {
                HStack {
                    TextField("Search name, path, group, manifest ID, explanation", text: $model.searchText)
                        .textFieldStyle(.roundedBorder).focused($searchFocused)
                        .onExitCommand { if !model.searchText.isEmpty { model.searchText = "" } else { searchFocused = false } }
                    if !model.searchText.isEmpty { Button("Clear Search") { model.searchText = "" }.buttonStyle(.bordered) }
                    Picker("Profile", selection: $model.activeProfile) { ForEach(CleanupProfile.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 150)
                    Picker("Sort", selection: $model.sortMode) { ForEach(ScanSortMode.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 120)
                }
            }
            HStack {
                Text("\(model.cleanableItems.count) visible of \(model.allCleanableItems.count) candidates · \(model.selectedItems.count) selected · \(model.scanIssues.count) issues").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Focus Search") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).buttonStyle(.plain)
            }
            Text(model.activeProfile.explanation + " Changing profile clears selection to prevent hidden cleanup targets.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var reviewTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Review area", selection: $tab) { ForEach(ReviewTab.allCases) { Text(tabTitle($0)).tag($0) } }.pickerStyle(.segmented)
            Group {
                switch tab {
                case .selected: scanList(model.selectedItems, kind: .selected)
                case .cleanable: scanList(model.cleanableItems, kind: .cleanable)
                case .audit: scanList(model.auditItems, kind: .audit)
                case .protected: scanList(model.protectedItems, kind: .protected)
                case .results: resultPanel
                case .issues: issuePanel
                }
            }
            .frame(minHeight: 250, maxHeight: 390)
        }
    }
    private func tabTitle(_ t: ReviewTab) -> String {
        switch t { case .selected: return "Selected \(model.selectedItems.count)"; case .cleanable: return "Candidates \(model.cleanableItems.count)"; case .audit: return "Audit \(model.auditItems.count)"; case .protected: return "Protected \(model.protectedItems.count)"; case .results: return "Results \(model.cleanupResults.count)"; case .issues: return "Issues \(model.scanIssues.count)" }
    }
    private enum PanelKind { case selected, cleanable, audit, protected }
    @ViewBuilder private func scanList(_ list: [ScanItem], kind: PanelKind) -> some View {
        if list.isEmpty { EmptyState(title: emptyTitle(kind), detail: emptyDetail(kind), actionTitle: model.scanCompleteness == .notRun ? "Scan Now" : nil) { model.scan() } }
        else { ScrollView { LazyVStack(spacing: 0) { ForEach(list) { ScanItemRow(item: $0, interactive: $0.isCleanable) ; Divider() } } }.background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8)) }
    }
    private func emptyTitle(_ kind: PanelKind) -> String {
        if model.scanCompleteness == .notRun { return "No scan yet" }
        if !model.searchText.isEmpty { return "No matching findings" }
        switch kind { case .selected: return "Nothing selected"; case .cleanable: return "No candidates in this profile"; case .audit: return "No audit-only findings"; case .protected: return "No protected markers" }
    }
    private func emptyDetail(_ kind: PanelKind) -> String {
        if model.scanCompleteness == .notRun { return "DexCleaner stays idle until you explicitly start a scan." }
        if !model.searchText.isEmpty { return "Clear Search or change the profile to broaden the visible review set." }
        switch kind { case .selected: return "Select exact safe candidates, then Preview before cleanup."; case .cleanable: return "This can be a valid result; DexCleaner does not invent cleanup targets."; case .audit: return "No read-only audit findings are visible under the current filter."; case .protected: return "No protected presence markers are visible under the current filter." }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            let counts = Dictionary(grouping: model.cleanupResults, by: \.status).mapValues(\.count)
            Text("Authorized \(counts["Authorized for confirmation", default: 0]) · Moved \(counts["Moved to Trash", default: 0]) · Blocked \(counts["Blocked", default: 0]) · Failed \(counts["Failed", default: 0]) · Cancelled \(counts["Cancelled", default: 0])").font(.caption.weight(.semibold))
            if model.lastTrashBytes > 0 { Text("Moved to Trash: \(model.lastTrashSizeText). This is not a claim that disk space is free.").font(.caption).foregroundStyle(.secondary) }
            if model.cleanupResults.isEmpty { EmptyState(title: "No preview or cleanup results", detail: "Preview results and cleanup outcomes will appear here.") }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(model.cleanupResults) { ResultRow(result: $0); Divider() } } } }
        }.padding(8)
    }
    private var issuePanel: some View {
        Group {
            if model.scanIssues.isEmpty { EmptyState(title: "No scan issues", detail: model.scanCompleteness == .notRun ? "Run Scan to collect issue evidence." : "The latest scan recorded no issues.") }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(model.scanIssues) { issue in VStack(alignment: .leading, spacing: 4) { Label(issue.kind.rawValue, systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold)); Text(issue.area).font(.caption.monospaced()); Text(issue.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.padding(.vertical, 7); Divider() } } } }
        }.padding(8)
    }

    private var reportControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Reports and privacy", systemImage: "doc.text").font(.headline)
            Text("Reports are local. Home-path redaction is the safer default. Destination: \(model.reportDestinationText)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            AdaptiveStack {
                HStack {
                    Picker("Format", selection: $model.reportFormat) { ForEach(ReportFormat.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 140)
                    Picker("Paths", selection: $model.pathRedaction) { ForEach(PathRedactionMode.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 170)
                    Button("Choose Folder") { model.chooseReportDestination() }
                    Button("Write Report") { model.writeReport() }.disabled(model.isWorking)
                    Button("Open Reports") { model.openReportsFolder() }.disabled(model.lastReportURL == nil && model.reportDestinationDirectory == nil)
                    Button("Open Trash") { model.openTrash() }
                }
            }
            Text(model.reportStatusText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("Additional large-file audit exclusions, comma-separated home-relative paths", text: $model.excludedLargeFileRootsText).textFieldStyle(.roundedBorder)
            Text(model.exclusionInputValidation.summary).font(.caption).foregroundStyle(model.exclusionInputValidation.rejected.isEmpty ? .secondary : .primary)
            if !model.exclusionInputValidation.rejected.isEmpty { Text("Ignored invalid input: \(model.exclusionInputValidation.rejected.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .padding(11).background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var cleanupConfirmation: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Label("Confirm exact Finder Trash move", systemImage: "trash").font(.title2.bold())
                if let plan = model.cleanupPlan {
                    Text("Plan \(plan.id.uuidString) · \(plan.items.count) item\(plan.items.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))").font(.caption.monospaced()).textSelection(.enabled)
                    Text("Created \(plan.createdAt.formatted(date: .abbreviated, time: .standard)). Authorization expires after fifteen minutes and every target is revalidated immediately before movement.").font(.callout)
                    ScrollView { VStack(alignment: .leading, spacing: 7) { ForEach(plan.items) { item in Text(item.path).font(.caption.monospaced()).textSelection(.enabled) } } }.frame(maxHeight: 260)
                }
                Text("DexCleaner moves only these previewed paths to Finder Trash. It does not empty Trash and does not claim the bytes are free.").font(.callout.weight(.semibold))
                if !model.canClean(at: context.date) { Label("Preview is stale or expired. Cancel and run Preview again.", systemImage: "exclamationmark.triangle").font(.callout.weight(.semibold)) }
                HStack { Spacer(); Button("Cancel") { showConfirm = false }.focused($confirmationCancelFocused); Button("Move Exact Paths to Trash") { showConfirm = false; model.cleanConfirmed(); tab = .results }.disabled(!model.canClean(at: context.date)) }
            }
            .padding(20).frame(minWidth: 620, minHeight: 390).onAppear { confirmationCancelFocused = true }
        }
    }

    private var phaseIcon: String { model.phase == .failed ? "exclamationmark.triangle" : model.phase == .complete ? "checkmark.shield" : model.phase == .cleaning ? "trash" : model.phase == .scanning ? "magnifyingglass" : "shield" }
    private var completenessIcon: String { model.scanCompleteness == .complete ? "checkmark.circle" : model.scanCompleteness == .failed ? "xmark.circle" : model.scanCompleteness == .partial ? "exclamationmark.circle" : "circle" }
}

private struct AdaptiveStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { ViewThatFits(in: .horizontal) { content(); ScrollView(.horizontal, showsIndicators: false) { content() } } }
}
private struct MetricCard: View {
    let title: String, value: String, detail: String, icon: String
    init(_ title: String, _ value: String, _ detail: String, _ icon: String) { self.title = title; self.value = value; self.detail = detail; self.icon = icon }
    var body: some View { VStack(alignment: .leading, spacing: 4) { Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7); Text(detail).font(.caption2).foregroundStyle(.secondary) }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)).accessibilityElement(children: .combine).accessibilityLabel(title).accessibilityValue("\(value). \(detail)") }
}
private struct DetailGroup<Content: View>: View {
    let title: String, icon: String; @ViewBuilder let content: () -> Content
    init(_ title: String, _ icon: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.icon = icon; self.content = content }
    var body: some View { VStack(alignment: .leading, spacing: 6) { Label(title, systemImage: icon).font(.subheadline.weight(.semibold)); content() }.padding(9).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)) }
}
private struct StatusPill: View {
    let text: String, systemImage: String
    var body: some View { Label(text, systemImage: systemImage).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 4).background(Color.secondary.opacity(0.08), in: Capsule()).fixedSize(horizontal: true, vertical: false) }
}
private struct EmptyState: View {
    let title: String, detail: String, actionTitle: String?, action: (() -> Void)?
    init(title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) { self.title = title; self.detail = detail; self.actionTitle = actionTitle; self.action = action }
    var body: some View { VStack(spacing: 8) { Image(systemName: "tray").font(.title2).foregroundStyle(.secondary); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center); if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.bordered) } }.frame(maxWidth: .infinity, minHeight: 150).padding() }
}
private struct ScanItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: ScanItem, interactive: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if interactive { Toggle("Select \(item.displayName)", isOn: Binding(get: { model.items.first(where: { $0.id == item.id })?.isSelected ?? false }, set: { _ in model.toggle(item) })).labelsHidden().toggleStyle(.checkbox) }
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(item.displayName).font(.headline); Spacer(); Text(item.sizeBytes > 0 ? item.formattedSize : "Not measured").font(.caption.monospacedDigit().weight(.semibold)) }
                HStack { StatusPill(text: item.risk.rawValue, systemImage: item.risk == .safe ? "checkmark.shield" : "eye"); StatusPill(text: item.category.rawValue, systemImage: "tag"); if let id = item.manifestID { StatusPill(text: "ID \(id)", systemImage: "number") } }
                if item.owningProcessRunning { Label("Owning app appears active. Close it before Preview when practical.", systemImage: "exclamationmark.circle").font(.caption.weight(.semibold)) }
                Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(item.explanation).font(.caption2).foregroundStyle(.secondary)
                Text("Recovery: \(item.recoveryNote)").font(.caption2).foregroundStyle(.secondary)
                HStack { Label(measurementText, systemImage: measurementIcon).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Reveal") { model.reveal(item) }.buttonStyle(.bordered).controlSize(.small); FeedbackButton(title: "Copy Path", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyPath(item) } }
            }
        }.padding(.vertical, 7)
    }
    private var measurementText: String { item.measuredAt.map { "\(item.measurementSource.rawValue) · \($0.formatted(date: .abbreviated, time: .standard))" } ?? item.measurementSource.rawValue }
    private var measurementIcon: String { item.measurementSource == .fresh ? "sparkles" : item.measurementSource == .cache ? "clock.arrow.circlepath" : "questionmark.circle" }
}
private struct ResultRow: View {
    @EnvironmentObject private var model: AppModel
    let result: CleanupResult
    var body: some View { VStack(alignment: .leading, spacing: 5) { HStack { StatusPill(text: result.status, systemImage: result.status == "Moved to Trash" ? "trash" : result.status == "Failed" ? "exclamationmark.triangle" : "info.circle"); Spacer(); FeedbackButton(title: "Copy Result", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyResult(result) } }; Text(result.path).font(.caption.monospaced()).textSelection(.enabled); Text(result.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.padding(.vertical, 6) }
}
private struct FeedbackButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var success = false
    let title: String, successTitle: String, systemImage: String, action: () -> Void
    var body: some View { Button { action(); withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { success = true }; Task { @MainActor in try? await Task.sleep(nanoseconds: 1_200_000_000); withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { success = false } } } label: { Label(success ? successTitle : title, systemImage: success ? "checkmark" : systemImage) }.buttonStyle(.bordered).controlSize(.small).frame(minHeight: 30) }
}
