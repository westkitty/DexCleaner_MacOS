import DexCleanerCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab = ReviewTab.selected
    @State private var showCleanupConfirmation = false

    enum ReviewTab: String, CaseIterable, Identifiable {
        case selected = "Selected"
        case cleanable = "Candidates"
        case audit = "Audit Only"
        case protected = "Protected"
        case results = "Results"
        case issues = "Issues"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                workflowStrip
                metrics
                controls
                filterBar
                reviewTabs
                reportControls
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 620)
        .sheet(isPresented: $showCleanupConfirmation) {
            cleanupConfirmation
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DexCleaner")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Exact cache authority. Explicit scan. Immutable preview. Finder Trash only.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(model.statusText)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Label(model.phase.rawValue, systemImage: phaseIcon)
                    .font(.headline)
                Label(model.scanCompleteness.rawValue, systemImage: completenessIcon)
                    .font(.caption.weight(.semibold))
                Text(model.manifestAuthorityText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var workflowStrip: some View {
        HStack(spacing: 8) {
            workflowStep("1", "Scan", active: model.phase == .scanning)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
            workflowStep("2", "Review", active: model.phase == .reviewing)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
            workflowStep("3", "Preview", active: model.phase == .previewed)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
            workflowStep("4", "Confirm Trash Move", active: model.phase == .cleaning || model.phase == .complete)
            Spacer()
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Operation in progress")
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func workflowStep(_ number: String, _ title: String, active: Bool) -> some View {
        Label {
            Text("\(number). \(title)").font(.caption.weight(active ? .bold : .regular))
        } icon: {
            Image(systemName: active ? "circle.inset.filled" : "circle")
        }
        .accessibilityLabel("Step \(number), \(title)\(active ? ", current" : "")")
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { metricCards }
            VStack(spacing: 8) { metricCards }
        }
    }

    @ViewBuilder
    private var metricCards: some View {
        metric("Available", model.diskStatus.available, "internaldrive")
        metric("Cleanable", model.cleanableSizeText, "checkmark.shield")
        metric("Selected", model.selectedSizeText, "checklist")
        metric("Moved to Trash", model.lastTrashSizeText, "trash")
        metric("Access check", model.accessStatus, "lock.shield")
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) { commandButtons }
            VStack(alignment: .leading, spacing: 8) { commandButtons }
        }
    }

    @ViewBuilder
    private var commandButtons: some View {
        Button { model.scan() } label: { Label("Scan", systemImage: "magnifyingglass") }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isWorking)
            .help("Start an explicit read-only scan")
        Button { model.cancel() } label: { Label("Cancel", systemImage: "xmark.circle") }
            .disabled(!model.isWorking)
            .help("Cancel active scan or cleanup work")
        Button { model.selectVisibleCandidates(); selectedTab = .selected } label: { Label("Select Visible Candidates", systemImage: "checklist") }
            .disabled(model.cleanableItems.isEmpty || model.isWorking)
            .help("Select only candidates visible under the current profile and search")
        Button { model.clearSelection(); selectedTab = .selected } label: { Label("Clear", systemImage: "eraser") }
            .disabled(model.selectedItems.isEmpty || model.isWorking)
        Button { model.previewSelected(); selectedTab = .results } label: { Label("Preview", systemImage: "eye") }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(model.selectedItems.isEmpty || model.isWorking)
            .help("Create an immutable cleanup plan without moving anything")
        Button { showCleanupConfirmation = true } label: { Label("Move to Trash", systemImage: "trash") }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canClean)
            .help("Available only after the current selection has been previewed")
        Spacer()
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { filterFields }
            VStack(alignment: .leading, spacing: 8) { filterFields }
        }
    }

    @ViewBuilder
    private var filterFields: some View {
        Picker("Profile", selection: $model.activeProfile) {
            ForEach(CleanupProfile.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        TextField("Search name, path, group, manifest ID", text: $model.searchText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Search scan findings")
        Picker("Sort within groups", selection: $model.sortMode) {
            ForEach(ScanSortMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .frame(width: 180)
    }

    private var reviewTabs: some View {
        TabView(selection: $selectedTab) {
            scanPanel(title: "Selected", subtitle: "Always visible, even when filters change", items: model.selectedItems, interactive: true, showMeasuredBytes: true)
                .tabItem { Label("Selected (\(model.selectedItems.count))", systemImage: "checklist") }
                .tag(ReviewTab.selected)
            scanPanel(title: "Cleanup candidates", subtitle: "Exact manifest targets only", items: model.cleanableItems, interactive: true, showMeasuredBytes: true)
                .tabItem { Label("Candidates (\(model.cleanableItems.count))", systemImage: "checkmark.shield") }
                .tag(ReviewTab.cleanable)
            scanPanel(title: "Audit only", subtitle: "Individual measurements may overlap; no aggregate reclaim claim", items: model.auditItems, interactive: false, showMeasuredBytes: false)
                .tabItem { Label("Audit (\(model.auditItems.count))", systemImage: "doc.text.magnifyingglass") }
                .tag(ReviewTab.audit)
            scanPanel(title: "Protected presence markers", subtitle: "Counts only; no false byte total", items: model.protectedItems, interactive: false, showMeasuredBytes: false)
                .tabItem { Label("Protected (\(model.protectedItems.count))", systemImage: "hand.raised") }
                .tag(ReviewTab.protected)
            resultsPanel
                .tabItem { Label("Results (\(model.cleanupResults.count))", systemImage: "list.bullet.rectangle") }
                .tag(ReviewTab.results)
            issuesPanel
                .tabItem { Label("Issues (\(model.scanIssues.count))", systemImage: "exclamationmark.triangle") }
                .tag(ReviewTab.issues)
        }
        .frame(minHeight: 310)
    }

    private func scanPanel(title: String, subtitle: String, items: [ScanItem], interactive: Bool, showMeasuredBytes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if showMeasuredBytes {
                    Text(ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))
                        .font(.caption.monospacedDigit().weight(.semibold))
                } else {
                    Text("\(items.count) paths").font(.caption.monospacedDigit().weight(.semibold))
                }
            }
            List {
                let grouped = Dictionary(grouping: items, by: { $0.group })
                ForEach(grouped.keys.sorted(), id: \.self) { group in
                    Section(group) {
                        ForEach(grouped[group] ?? []) { item in
                            ScanItemRow(item: item, interactive: interactive)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(10)
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Complete preview and cleanup results").font(.headline)
                Spacer()
                if model.lastTrashBytes > 0 {
                    Button { model.openTrash() } label: { Label("Open Trash", systemImage: "trash") }
                }
            }
            List(model.cleanupResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(result.status, systemImage: resultIcon(result.status)).font(.headline)
                        Spacer()
                        Button { model.copyResult(result) } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                    Text(result.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(result.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            if model.cleanupResults.isEmpty {
                placeholder("No results", icon: "list.bullet.rectangle", detail: "Run Preview before cleanup.")
            }
        }
        .padding(10)
    }

    private var issuesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan completeness: \(model.scanCompleteness.rawValue)").font(.headline)
            List(model.scanIssues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    Label(issue.kind.rawValue, systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(issue.area).font(.caption.weight(.semibold))
                    Text(issue.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            if model.scanIssues.isEmpty {
                placeholder("No scan issues recorded", icon: "checkmark.shield", detail: "A complete scan will show no issues here.")
            }
        }
        .padding(10)
    }

    private var reportControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { reportFields }
                VStack(alignment: .leading, spacing: 8) { reportFields }
            }
            DisclosureGroup("Additional large-file audit exclusions") {
                TextField("Comma-separated home-relative paths", text: $model.excludedLargeFileRootsText)
                    .textFieldStyle(.roundedBorder)
                Text("Mandatory privacy exclusions are always enforced. Absolute paths and parent traversal are rejected. Changes apply on the next scan.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(model.reportStatusText).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var reportFields: some View {
        Button { model.requestAccessSettings() } label: { Label("Access Settings", systemImage: "lock.open") }
        Picker("Format", selection: $model.reportFormat) {
            ForEach(ReportFormat.allCases) { Text($0.rawValue).tag($0) }
        }.frame(width: 150)
        Picker("Paths", selection: $model.pathRedaction) {
            ForEach(PathRedactionMode.allCases) { Text($0.rawValue).tag($0) }
        }.frame(width: 180)
        Button { model.chooseReportDestination() } label: { Label("Report Folder", systemImage: "folder") }
        Button { model.writeReport() } label: { Label("Write Report", systemImage: "doc.text") }
            .disabled(model.isWorking)
        Button { model.openReportsFolder() } label: { Label("Open Reports", systemImage: "arrow.up.forward.app") }
            .disabled(model.reportDestinationDirectory == nil && model.lastReportURL == nil)
        Spacer()
    }

    private var cleanupConfirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Confirm exact Finder Trash move", systemImage: "exclamationmark.shield")
                .font(.title2.bold())
            Text("This plan was created by Preview. Every target will be revalidated immediately before movement.")
            if let plan = model.cleanupPlan {
                Text("Plan \(plan.id.uuidString) · \(plan.items.count) items · \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))")
                    .font(.caption.monospaced()).textSelection(.enabled)
                List(plan.items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName).font(.headline)
                        Text(item.path).font(.caption.monospaced()).textSelection(.enabled)
                        Text(item.safetyReason).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            Text("Items will be moved to Finder Trash. Disk space may not become available until Trash is emptied manually.")
                .font(.callout.weight(.semibold))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showCleanupConfirmation = false }
                Button("Move Exact Plan to Trash", role: .destructive) {
                    showCleanupConfirmation = false
                    model.cleanConfirmed()
                    selectedTab = .results
                }
                .disabled(!model.canClean)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
    }


    private func placeholder(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .accessibilityElement(children: .combine)
    }
    private var phaseIcon: String {
        switch model.phase {
        case .idle: return "pause.circle"
        case .scanning: return "magnifyingglass"
        case .reviewing: return "doc.text.magnifyingglass"
        case .previewed: return "checkmark.seal"
        case .cleaning: return "trash"
        case .cancelled: return "xmark.circle"
        case .complete: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var completenessIcon: String {
        switch model.scanCompleteness {
        case .complete: return "checkmark.circle"
        case .partial: return "exclamationmark.circle"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .notRun: return "circle.dashed"
        }
    }

    private func resultIcon(_ status: String) -> String {
        switch status {
        case "Moved to Trash": return "trash"
        case "Failed", "Blocked": return "exclamationmark.triangle"
        case "Cancelled": return "xmark.circle"
        default: return "checkmark.seal"
        }
    }
}

private struct ScanItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: ScanItem
    let interactive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if interactive {
                Toggle("Select \(item.displayName)", isOn: Binding(
                    get: { model.items.first(where: { $0.id == item.id })?.isSelected ?? false },
                    set: { _ in model.toggle(item) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Select \(item.displayName)")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.displayName).font(.headline)
                    if item.owningProcessRunning {
                        Label("Owning app appears active", systemImage: "exclamationmark.circle")
                            .font(.caption2.weight(.semibold))
                    }
                    Spacer()
                    Text(item.sizeBytes > 0 ? item.formattedSize : "Not measured")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text("\(item.risk.rawValue) · \(item.category.rawValue) · ID: \(item.manifestID ?? "none")")
                    .font(.caption2.weight(.semibold))
                Text(item.explanation).font(.caption2).foregroundStyle(.secondary)
                Text("Recovery: \(item.recoveryNote)").font(.caption2).foregroundStyle(.secondary)
                Text(measurementText).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button { model.reveal(item) } label: { Label("Reveal", systemImage: "finder") }
                        .buttonStyle(.borderless).disabled(!item.path.hasPrefix("/"))
                    Button { model.copyPath(item) } label: { Label("Copy Path", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private var measurementText: String {
        if let date = item.measuredAt {
            return "Measurement: \(item.measurementSource.rawValue), \(date.formatted(date: .abbreviated, time: .standard))"
        }
        return "Measurement: \(item.measurementSource.rawValue)"
    }
}
