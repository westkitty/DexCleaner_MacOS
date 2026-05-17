import SwiftUI
import DexCleanerCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            progressStrip
            summary
            controls
            lists
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 34)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor).opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.centerWindowIfNeeded() }
            if model.items.isEmpty { model.scan() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DexCleaner")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("Exact cache cleanup. Preview first. Finder Trash only.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(model.isWorking ? .orange : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Label(model.phase.rawValue, systemImage: model.isWorking ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                    .font(.headline)
                Text("Last scan: \(String(format: "%.1f", model.scanDurationSeconds))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(model.progressDetail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(model.isWorking ? .orange : .green)
                .animation(.easeInOut(duration: 0.25), value: model.progress)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric("Available", model.diskStatus.available, "internaldrive")
            metric("Cleanable", model.cleanableSizeText, "sparkles")
            metric("Selected", model.selectedSizeText, "checkmark.circle")
            metric("Trash moved", model.lastTrashSizeText, "trash")
            metric("Full Disk Access", model.fullDiskAccessStatus, "lock.shield")
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Profile", selection: $model.activeProfile) {
                    ForEach(CleanupProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 430)

                Text("Sort")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Sort", selection: $model.sortMode) {
                    ForEach(ScanSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 128)
                Spacer()
            }

            HStack(spacing: 10) {
                command("Scan", "magnifyingglass") { model.scan() }
                command("Cancel", "xmark.circle") { model.cancel() }
                    .disabled(!model.isWorking)
                command("Select Safe", "checklist") { model.selectSafe() }
                    .disabled(model.cleanableItems.isEmpty)
                command("Clear", "eraser") { model.clearSelection() }
                command("Preview", "eye") { model.previewSelected() }
                    .disabled(model.selectedItems.isEmpty)
                command("Move to Trash", "trash") { model.cleanSelected() }
                    .disabled(model.selectedItems.isEmpty)
                command("Permissions", "lock.open") { model.requestAllPermissions() }
                Spacer()
            }
        }
    }

    private func command(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
    }

    private var lists: some View {
        HSplitView {
            scanPanel(
                title: "Cleanable",
                subtitle: "Exact manifest targets only",
                items: model.cleanableItems,
                bytes: model.cleanableBytes,
                interactive: true,
                tint: .green
            )
            scanPanel(
                title: "Audit Only",
                subtitle: "Visible, not selectable",
                items: model.auditItems,
                bytes: model.auditBytes,
                interactive: false,
                tint: .orange
            )
            scanPanel(
                title: "Protected",
                subtitle: "Reported so it is not mistaken for trash",
                items: model.protectedItems,
                bytes: model.protectedBytes,
                interactive: false,
                tint: .red
            )
        }
        .frame(minHeight: 430)
    }

    private func scanPanel(title: String, subtitle: String, items: [ScanItem], bytes: Int64, interactive: Bool, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(title) (\(items.count))")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
            }
            List {
                ForEach(Dictionary(grouping: items, by: { $0.group }).keys.sorted(), id: \.self) { group in
                    Section(group) {
                        ForEach((Dictionary(grouping: items, by: { $0.group })[group] ?? [])) { item in
                            ScanItemRow(item: item, interactive: interactive, tint: tint)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Results")
                    .font(.headline)
                if model.cleanupResults.isEmpty {
                    Text("No preview or cleanup results yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.cleanupResults.prefix(5)) { result in
                        Text("\(result.status): \(result.path) - \(result.detail)")
                            .font(.caption)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(model.permissionRequestSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                Toggle("Background scan", isOn: Binding(
                    get: { model.backgroundScanningEnabled },
                    set: { _ in model.toggleBackgroundScanning() }
                ))
                .toggleStyle(.switch)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { _ in model.toggleLaunchAtLogin() }
                ))
                .toggleStyle(.switch)
                HStack {
                    Button {
                        model.chooseReportDestination()
                    } label: {
                        Label("Report Folder", systemImage: "folder")
                    }
                    Button {
                        model.writeReport()
                    } label: {
                        Label("Write Report", systemImage: "doc.text")
                    }
                    Button {
                        model.openReportsFolder()
                    } label: {
                        Label("Open Reports", systemImage: "arrow.up.forward.app")
                    }
                    .disabled(model.reportDestinationDirectory == nil && model.lastReportURL == nil)
                }
                if let url = model.lastReportURL {
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct ScanItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: ScanItem
    let interactive: Bool
    let tint: Color
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if interactive {
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { _ in model.toggle(item) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.displayName)
                        .font(.headline)
                    Spacer()
                    Text(item.formattedSize)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("\(item.risk.rawValue) - \(item.category.rawValue)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if hovering {
                    HStack {
                        Text(item.recoveryNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            model.reveal(item)
                        } label: {
                            Label("Reveal", systemImage: "finder")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!item.path.hasPrefix("/"))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, hovering ? 8 : 4)
        .padding(.horizontal, 6)
        .background(hovering ? tint.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}
