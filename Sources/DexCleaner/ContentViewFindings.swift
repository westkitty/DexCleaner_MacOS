import DexCleanerCore
import Foundation
import SwiftUI

extension ContentView {
    enum PanelKind { case selected, cleanable, audit, protected }

    @ViewBuilder func scanList(_ list: [ScanItem], kind: PanelKind, now: Date) -> some View {
        if list.isEmpty {
            EmptyState(
                title: emptyTitle(kind),
                detail: emptyDetail(kind),
                actionTitle: model.scanCompleteness == .notRun ? "Scan Now" : nil
            ) { model.scan() }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(groupedItems(list), id: \.name) { group in
                        groupedSection(group, now: now)
                    }
                }
                .padding(6)
            }
            .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    func groupedItems(_ list: [ScanItem]) -> [(name: String, items: [ScanItem])] {
        Dictionary(grouping: list, by: \.group)
            .map { (name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func groupedSection(_ group: (name: String, items: [ScanItem]), now: Date) -> some View {
        let bytes = group.items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let collapsed = collapsedGroups.contains(group.name)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(animation) {
                    if collapsed { collapsedGroups.remove(group.name) }
                    else { collapsedGroups.insert(group.name) }
                }
            } label: {
                HStack {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.caption)
                    Text(group.name).font(.subheadline.weight(.semibold))
                    StatusPill(text: "\(group.items.count) item\(group.items.count == 1 ? "" : "s")", systemImage: "number")
                    Spacer()
                    if bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityHint("Shows or hides the items in this review group.")
            .padding(8)

            if !collapsed {
                ForEach(group.items) { item in
                    Divider()
                    ScanItemRow(
                        item: item,
                        interactive: item.isCleanable,
                        now: now,
                        isExpanded: expandedRows.contains(item.id),
                        onToggleExpanded: { toggleRowExpansion(item.id) }
                    )
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
    }

    func toggleRowExpansion(_ id: UUID) {
        withAnimation(animation) {
            if expandedRows.contains(id) { expandedRows.remove(id) }
            else { expandedRows.insert(id) }
        }
    }

    func emptyTitle(_ kind: PanelKind) -> String {
        if model.scanCompleteness == .notRun { return "No scan yet" }
        if !model.searchText.isEmpty { return "No matching findings" }
        switch kind {
        case .selected: return "Nothing selected"
        case .cleanable: return "No candidates in this profile"
        case .audit: return "No audit-only findings"
        case .protected: return "No protected markers"
        }
    }

    func emptyDetail(_ kind: PanelKind) -> String {
        if model.scanCompleteness == .notRun { return "DexCleaner stays idle until you explicitly start a scan." }
        if !model.searchText.isEmpty { return "Clear Search or change the profile to broaden the visible review set." }
        switch kind {
        case .selected: return "Select exact safe candidates, then Preview before cleanup."
        case .cleanable: return "This can be a valid result; DexCleaner does not invent cleanup targets."
        case .audit: return "No read-only audit findings are visible under the current filter."
        case .protected: return "No protected presence markers are visible under the current filter."
        }
    }

}
