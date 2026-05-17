import SwiftUI
import DexCleanerCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            controls
            lists
            footer
        }
        .padding(16)
        .onAppear { model.scan() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DexCleaner")
                .font(.largeTitle.bold())
            Text("Preview-first, exact-manifest, Finder-Trash-only cleanup.")
                .foregroundStyle(.secondary)
            Text(model.statusText)
                .font(.callout)
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            metric("Available", model.diskStatus.available)
            metric("Capacity", model.diskStatus.capacity)
            metric("Cleanable", ByteCountFormatter.string(fromByteCount: model.cleanableBytes, countStyle: .file))
            metric("Selected", ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))
            metric("Full Disk Access", model.fullDiskAccessStatus)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack {
            Button("Scan") { model.scan() }
            Button("Cancel") { model.cancel() }.disabled(!model.isWorking)
            Button("Select Safe") { model.selectSafe() }.disabled(model.cleanableItems.isEmpty)
            Button("Clear") { model.clearSelection() }
            Button("Preview Selected") { model.previewSelected() }.disabled(model.selectedItems.isEmpty)
            Button("Move Selected to Trash") { model.cleanSelected() }.disabled(model.selectedItems.isEmpty)
            Button("Write Report") { model.writeReport() }
        }
    }

    private var lists: some View {
        HSplitView {
            groupedList(title: "Cleanable", items: model.cleanableItems, interactive: true)
            groupedList(title: "Audit Only", items: model.auditItems, interactive: false)
            groupedList(title: "Protected", items: model.protectedItems, interactive: false)
        }
        .frame(minHeight: 420)
    }

    private func groupedList(title: String, items: [ScanItem], interactive: Bool) -> some View {
        VStack(alignment: .leading) {
            Text("\(title) (\(items.count))").font(.headline)
            List {
                ForEach(Dictionary(grouping: items, by: { $0.group }).keys.sorted(), id: \.self) { group in
                    Section(group) {
                        ForEach((Dictionary(grouping: items, by: { $0.group })[group] ?? []).sorted(by: { $0.sizeBytes > $1.sizeBytes })) { item in
                            HStack(alignment: .top) {
                                if interactive {
                                    Toggle("", isOn: Binding(
                                        get: { item.isSelected },
                                        set: { _ in model.toggle(item) }
                                    ))
                                    .labelsHidden()
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).font(.headline)
                                    Text(item.path).font(.caption).textSelection(.enabled)
                                    Text("\(item.risk.rawValue) · \(item.category.rawValue) · \(item.formattedSize)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.explanation).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.cleanupResults.isEmpty {
                Text("Results").font(.headline)
                ForEach(model.cleanupResults.prefix(6)) { result in
                    Text("\(result.status): \(result.path) — \(result.detail)")
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            if let url = model.lastReportURL {
                Text("Last report: \(url.path)").font(.caption).textSelection(.enabled)
            }
        }
    }
}
