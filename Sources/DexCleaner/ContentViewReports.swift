import DexCleanerCore
import Foundation
import SwiftUI

extension ContentView {
    var reportControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Reports and privacy", systemImage: "doc.text").font(.headline)
            Text("Reports are local. Home-path redaction is the safer default. Destination: \(model.reportDestinationText)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(model.reportPreflightText)
                .font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                .padding(7).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            AdaptiveStack {
                HStack {
                    Picker("Format", selection: $model.reportFormat) {
                        ForEach(ReportFormat.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 140)
                    Picker("Paths", selection: $model.pathRedaction) {
                        ForEach(PathRedactionMode.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 170)
                    Button("Choose Folder") { model.chooseReportDestination() }
                    Button("Write Report") { model.writeReport() }.disabled(model.isWorking)
                    Button("Open Reports") { model.openReportsFolder() }.disabled(model.lastReportURL == nil && model.reportDestinationDirectory == nil)
                    Button("Open Trash") { model.openTrash() }
                }
            }
            Text(model.reportStatusText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("Additional large-file audit exclusions, comma-separated home-relative paths", text: $model.excludedLargeFileRootsText)
                .textFieldStyle(.roundedBorder)
            Text(model.exclusionInputValidation.summary)
                .font(.caption)
                .foregroundStyle(model.exclusionInputValidation.rejected.isEmpty ? .secondary : .primary)
            if !model.exclusionInputValidation.rejected.isEmpty {
                Text("Ignored invalid input: \(model.exclusionInputValidation.rejected.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(11).background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    var cleanupConfirmation: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Label("Confirm exact Finder Trash move", systemImage: "trash").font(.title2.bold())
                if let plan = model.cleanupPlan {
                    HStack {
                        Text("Plan \(plan.id.uuidString) | \(plan.items.count) item\(plan.items.count == 1 ? "" : "s") | \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))")
                            .font(.caption.monospaced()).textSelection(.enabled)
                        Spacer()
                        FeedbackButton(title: "Copy Plan Paths", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyPlanPaths(plan) }
                    }
                    HStack {
                        Label(model.previewRemainingText(at: context.date), systemImage: model.canClean(at: context.date) ? "clock" : "clock")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text("Created \(plan.createdAt.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Authorization expires after fifteen minutes and every target is revalidated immediately before movement.").font(.callout)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(plan.items) { item in Text(item.path).font(.caption.monospaced()).textSelection(.enabled) }
                        }
                    }.frame(maxHeight: 260)
                }
                Text("DexCleaner moves only these previewed paths to Finder Trash. It does not empty Trash and does not claim the bytes are free.")
                    .font(.callout.weight(.semibold))
                if !model.canClean(at: context.date) {
                    Label("Preview is stale or expired. Cancel and run Preview again.", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showConfirm = false }.focused($confirmationCancelFocused)
                    Button("Move Exact Paths to Trash") {
                        showConfirm = false
                        model.cleanConfirmed()
                        tab = .results
                    }
                    .disabled(!model.canClean(at: context.date))
                }
            }
            .padding(20)
            .frame(minWidth: 620, minHeight: 410)
            .onAppear { confirmationCancelFocused = true }
        }
    }

    var phaseIcon: String {
        model.phase == .failed ? "exclamationmark.triangle" : model.phase == .complete ? "checkmark.shield" : model.phase == .cleaning ? "trash" : model.phase == .scanning ? "magnifyingglass" : "shield"
    }

    var completenessIcon: String {
        model.scanCompleteness == .complete ? "checkmark.circle" : model.scanCompleteness == .failed ? "xmark.circle" : model.scanCompleteness == .partial ? "exclamationmark.circle" : "circle"
    }
}
