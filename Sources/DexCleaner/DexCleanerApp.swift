import SwiftUI
import AppKit

@main
struct DexCleanerApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("DexCleaner", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("DexCleaner", systemImage: "internaldrive") {
            VStack(alignment: .leading) {
                Text("DexCleaner")
                    .font(.headline)
                Text(model.statusText)
                    .font(.caption)
                Text("Cleanable: \(model.cleanableSizeText)")
                Text("Selected: \(model.selectedSizeText)")
                if model.lastTrashBytes > 0 {
                    Text("Moved to Trash: \(model.lastTrashSizeText)")
                }
            }
            Divider()
            Button("Open Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Scan Now") { model.scan() }
                .disabled(model.isWorking)
            Button("Request Permissions") { model.requestAllPermissions() }
            Button("Preview Selected") { model.previewSelected() }
                .disabled(model.selectedItems.isEmpty)
            Button("Move Selected to Trash") { model.cleanSelected() }
                .disabled(model.selectedItems.isEmpty)
            Button("Write Report") { model.writeReport() }
            Toggle("Background Scan", isOn: Binding(
                get: { model.backgroundScanningEnabled },
                set: { _ in model.toggleBackgroundScanning() }
            ))
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { _ in model.toggleLaunchAtLogin() }
            ))
            Divider()
            Text("Available: \(model.diskStatus.available)")
            Text("Full Disk Access: \(model.fullDiskAccessStatus)")
        }
    }
}
