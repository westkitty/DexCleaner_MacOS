import SwiftUI

@main
struct DexCleanerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("DexCleaner", systemImage: "internaldrive") {
            Button("Scan") { model.scan() }
            Button("Preview Selected") { model.previewSelected() }
                .disabled(model.selectedItems.isEmpty)
            Button("Write Report") { model.writeReport() }
            Divider()
            Text("Available: \(model.diskStatus.available)")
            Text("Selected: \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))")
        }
    }
}
