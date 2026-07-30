import DexCleanerCore
import SwiftUI

struct StorageDriversView: View {
    @EnvironmentObject private var model: AppModel
    @State private var watchPath = ""
    @State private var watchName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Storage Drivers").font(.title2.bold())
                    Text("Read-only totals for categories and explicitly watched directories. A driver is never cleanup authority.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh Storage Drivers") { model.refreshStorageDrivers() }.dexInteractive()
                Button("Find What Changed") { model.findWhatChanged() }.dexInteractive()
            }
            HStack {
                TextField("Watch directory path", text: $watchPath)
                TextField("Name", text: $watchName).frame(width: 180)
                Button("Add to Watchlist") { model.addWatchlistDirectory(name: watchName.isEmpty ? URL(fileURLWithPath: watchPath).lastPathComponent : watchName, path: watchPath); watchPath = ""; watchName = "" }.dexInteractive()
            }.textFieldStyle(.roundedBorder)
            Text(model.driverStatusText).font(.caption).foregroundStyle(.secondary)
            if let drop = model.significantDropText { Label(drop, systemImage: "arrow.down.right.circle").font(.callout).foregroundStyle(.orange) }
            List(model.storageDrivers) { driver in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(driver.name).font(.headline)
                        Text(driver.isWatch ? "Watched directory · \(driver.classification.rawValue)" : driver.classification.rawValue).font(.caption).foregroundStyle(.secondary)
                        Text(driver.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { model.refreshStorageDriver(driver) }.dexInteractive()
                    if driver.isWatch { Button("Remove") { model.removeWatchlistDirectory(driver) }.dexInteractive() }
                }
                .accessibilityElement(children: .contain)
            }
            .frame(minHeight: 260)
        }
        .padding(12)
    }
}
