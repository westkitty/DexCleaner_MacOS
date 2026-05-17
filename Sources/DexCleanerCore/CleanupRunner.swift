import Foundation

public struct CleanupRunner {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    public func dryRunSelected(_ items: [ScanItem]) -> [CleanupResult] {
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else {
            return [CleanupResult(path: "selection://empty", status: "Dry run", detail: "No selected cleanup candidates.")]
        }

        return selected.map { item in
            let decision = SafetyEngine.decision(for: item, home: home)
            if decision.allowed {
                return CleanupResult(path: item.path, status: "Would move to Trash", detail: decision.reason)
            }
            return CleanupResult(path: item.path, status: "Blocked", detail: decision.reason)
        }
    }

    public func cleanSelected(_ items: [ScanItem]) -> [CleanupResult] {
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else {
            return [CleanupResult(path: "selection://empty", status: "Skipped", detail: "No selected cleanup candidates.")]
        }

        return selected.map { item in
            let decision = SafetyEngine.decision(for: item, home: home)
            guard decision.allowed else {
                return CleanupResult(path: item.path, status: "Blocked", detail: decision.reason)
            }

            #if os(macOS)
            do {
                let url = URL(fileURLWithPath: item.path)
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                let destination = resultingURL?.path ?? "Finder Trash"
                return CleanupResult(path: item.path, status: "Moved to Trash", detail: "Moved to \(destination).")
            } catch {
                return CleanupResult(path: item.path, status: "Failed", detail: error.localizedDescription)
            }
            #else
            return CleanupResult(path: item.path, status: "Unsupported platform", detail: "Trash cleanup is only available on macOS. Dry run remains available.")
            #endif
        }
    }
}
