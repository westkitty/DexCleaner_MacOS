import AppKit
import SwiftUI

@main
struct DexCleanerApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("DexCleaner", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("DexCleaner", systemImage: menuBarIcon) {
            VStack(alignment: .leading, spacing: 5) {
                Label("DexCleaner", systemImage: menuBarIcon).font(.headline)
                Text(model.statusText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Label("\(model.phase.rawValue) | Scan \(model.scanCompleteness.rawValue)", systemImage: "waveform.path.ecg")
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Label(model.scanFreshnessText(at: context.date), systemImage: model.scanIsStale(at: context.date) ? "clock" : "clock")
                }
                Label("\(model.selectedItems.count) selected | \(model.selectedSizeText)", systemImage: "checklist")
                if !model.scanIssues.isEmpty {
                    Label("\(model.scanIssues.count) scan issue\(model.scanIssues.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                }
                if let plan = model.cleanupPlan {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let ready = model.canClean(at: context.date)
                        Label(ready ? "Preview ready | \(plan.items.count) items" : "Preview stale or expired", systemImage: ready ? "checkmark.shield" : "lock.shield")
                    }
                }
                if model.lastTrashBytes > 0 {
                    Label("Moved to Trash: \(model.lastTrashSizeText)", systemImage: "trash")
                }
            }
            Divider()
            Button("Open Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Scan Now") { model.scan() }
                .disabled(model.isWorking)
            if model.isWorking {
                Button("Cancel Active Operation") { model.cancel() }
            }
            Button("Write Report") { model.writeReport() }
                .disabled(model.isWorking)
            Button("Open Trash") { model.openTrash() }
            Divider()
            Button("Quit DexCleaner") { model.quit() }
        }
    }

    private var menuBarIcon: String {
        switch model.phase {
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        case .scanning: return "magnifyingglass"
        case .cleaning: return "trash"
        case .previewed: return "checkmark.shield"
        case .complete: return "checkmark.circle"
        case .idle, .reviewing: return "checkmark.shield"
        }
    }
}
