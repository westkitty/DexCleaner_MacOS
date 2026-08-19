import DexCleanerCore
import Foundation
import SwiftUI

extension ContentView {
    var hasVisibleSelection: Bool {
        let visibleIDs = Set(model.cleanableItems.map(\.id))
        return model.selectedItems.contains { visibleIDs.contains($0.id) }
    }

    var selectionImpact: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Selection impact", systemImage: "checklist").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.selectedItems.count) items | \(model.selectedSizeText)").font(.caption.monospacedDigit())
            }
            Text(model.selectedItems.isEmpty ? "No cleanup candidates are selected." : "Groups: \(model.selectedGroupSummary)")
                .font(.caption).foregroundStyle(.secondary)
            if model.selectedRunningProcessCount > 0 {
                HStack {
                    Label("\(model.selectedRunningProcessCount) selected target\(model.selectedRunningProcessCount == 1 ? "" : "s") belong to apps that appear active. Close them before Preview when practical.", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Show Selected") { tab = .selected }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(10).background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    var filterBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            AdaptiveStack {
                HStack {
                    TextField("Search name, path, group, manifest ID, explanation", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                        .onExitCommand {
                            if !model.searchText.isEmpty { model.searchText = "" }
                            else { searchFocused = false }
                        }
                    if !model.searchText.isEmpty {
                        Button("Clear Search") { model.searchText = "" }.buttonStyle(.bordered)
                    }
                    Picker("Profile", selection: $model.activeProfile) {
                        ForEach(CleanupProfile.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 150)
                    .disabled(model.isWorking)
                    Picker("Sort", selection: $model.sortMode) {
                        ForEach(ScanSortMode.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 120)
                }
            }
            HStack {
                Text("\(model.cleanableItems.count) visible of \(model.allCleanableItems.count) candidates | \(model.selectedItems.count) selected | \(model.scanIssues.count) issues")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Focus Search") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).buttonStyle(.plain)
            }
            Text(model.activeProfile.explanation + " Changing profile clears selection to prevent hidden cleanup targets.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    var reviewTabs: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                reviewNavigation
                Group {
                    switch tab {
                    case .selected: scanList(model.selectedItems, kind: .selected, now: context.date)
                    case .cleanable: scanList(model.cleanableItems, kind: .cleanable, now: context.date)
                    case .audit: scanList(model.auditItems, kind: .audit, now: context.date)
                    case .protected: scanList(model.protectedItems, kind: .protected, now: context.date)
                    case .results: resultPanel
                    case .issues: issuePanel
                    }
                }
                .frame(minHeight: 250, maxHeight: 410)
            }
        }
    }

    var reviewNavigation: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(ReviewTab.allCases.enumerated()), id: \.element.id) { index, reviewTab in
                    Button { tab = reviewTab } label: {
                        Label(tabTitle(reviewTab), systemImage: tabIcon(reviewTab))
                            .font(.caption.weight(tab == reviewTab ? .bold : .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(tab == reviewTab ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(tabShortcut(index), modifiers: .command)
                    .accessibilityValue(tab == reviewTab ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 1)
        }
    }

    func tabShortcut(_ index: Int) -> KeyEquivalent {
        switch index {
        case 0: return "1"
        case 1: return "2"
        case 2: return "3"
        case 3: return "4"
        case 4: return "5"
        default: return "6"
        }
    }

    func tabIcon(_ reviewTab: ReviewTab) -> String {
        switch reviewTab {
        case .selected: return "checklist"
        case .cleanable: return "checkmark.shield"
        case .audit: return "eye"
        case .protected: return "lock.shield"
        case .results: return "list.bullet.rectangle"
        case .issues: return "exclamationmark.triangle"
        }
    }

    func tabTitle(_ reviewTab: ReviewTab) -> String {
        switch reviewTab {
        case .selected: return "Selected \(model.selectedItems.count)"
        case .cleanable: return "Candidates \(model.cleanableItems.count)"
        case .audit: return "Audit \(model.auditItems.count)"
        case .protected: return "Protected \(model.protectedItems.count)"
        case .results: return "Results \(model.cleanupResults.count)"
        case .issues: return "Issues \(model.scanIssues.count)"
        }
    }

}
