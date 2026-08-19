import DexCleanerCore
import Foundation
import SwiftUI

extension ContentView {
    var filteredResults: [CleanupResult] {
        model.cleanupResults.filter { resultFilter.includes($0) }
    }

    var resultPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            let counts = Dictionary(grouping: model.cleanupResults, by: \.status).mapValues(\.count)
            Text("Authorized \(counts["Authorized for confirmation", default: 0]) | Moved \(counts["Moved to Trash", default: 0]) | Blocked \(counts["Blocked", default: 0]) | Failed \(counts["Failed", default: 0]) | Cancelled \(counts["Cancelled", default: 0])")
                .font(.caption.weight(.semibold))
            if model.lastTrashBytes > 0 {
                Text("Moved to Trash: \(model.lastTrashSizeText). This is not a claim that disk space is free.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ResultFilter.allCases) { filter in
                        Button(resultFilterTitle(filter)) { resultFilter = filter }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(resultFilter == filter)
                    }
                    if !filteredResults.isEmpty {
                        FeedbackButton(title: "Copy Visible Results", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyResults(filteredResults) }
                    }
                }
            }
            if model.cleanupResults.isEmpty {
                EmptyState(title: "No preview or cleanup results", detail: "Preview results and cleanup outcomes will appear here.")
            } else if filteredResults.isEmpty {
                EmptyState(title: "No results in this filter", detail: "Choose another result status to continue reviewing the operation ledger.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredResults) { result in
                            ResultRow(result: result)
                            Divider()
                        }
                    }
                }
            }
        }.padding(8)
    }

    func resultFilterTitle(_ filter: ResultFilter) -> String {
        let count = model.cleanupResults.filter { filter.includes($0) }.count
        return filter == .all ? "All \(model.cleanupResults.count)" : "\(filter.rawValue) \(count)"
    }

    var issuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.scanIssues.isEmpty {
                HStack {
                    Text("Scan issues are explicit evidence of incomplete or degraded collection.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Run Scan Again") { model.scan() }.buttonStyle(.bordered).disabled(model.isWorking)
                    if model.scanIssues.contains(where: { $0.kind == .permission }) {
                        Button("Access Settings") { model.requestAccessSettings() }.buttonStyle(.bordered)
                    }
                }
            }
            if model.scanIssues.isEmpty {
                EmptyState(
                    title: "No scan issues",
                    detail: model.scanCompleteness == .notRun ? "Run Scan to collect issue evidence." : "The latest scan recorded no issues."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.scanIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: issueIcon(issue)).font(.headline).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.kind.rawValue).font(.subheadline.weight(.semibold))
                                    Text(issue.area).font(.caption.monospaced()).textSelection(.enabled)
                                    Text(issue.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                FeedbackButton(title: "Copy Issue", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyIssue(issue) }
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
            }
        }.padding(8)
    }

    func issueIcon(_ issue: ScanIssue) -> String {
        switch issue.kind {
        case .permission: return "lock"
        case .timeout: return "clock"
        case .commandFailure: return "terminal"
        case .manifest: return "checkmark.shield"
        case .cancellation: return "xmark.circle"
        case .filesystem: return "externaldrive"
        case .measurement: return "ruler"
        }
    }

}
