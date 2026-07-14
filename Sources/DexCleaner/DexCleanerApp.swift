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

        MenuBarExtra("DexCleaner", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 4) {
                Text("DexCleaner").font(.headline)
                Text(model.statusText).font(.caption)
                Text("Scan: \(model.scanCompleteness.rawValue)")
                Text("Selected: \(model.selectedSizeText)")
                if model.lastTrashBytes > 0 { Text("Moved to Trash: \(model.lastTrashSizeText)") }
            }
            Divider()
            Button("Open Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Scan Now") { model.scan() }.disabled(model.isWorking)
            Button("Write Report") { model.writeReport() }
                .disabled(model.isWorking)
            Button("Open Trash") { model.openTrash() }
            Divider()
            Button("Quit DexCleaner") { model.quit() }
        }
    }
}
