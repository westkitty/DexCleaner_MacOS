import Foundation

public enum StorageCapacityProvider {
    public static let disagreementToleranceFraction = 0.02
    public static let disagreementToleranceFloor: Int64 = 1_073_741_824
    /// A capacity reading may be labeled Fresh only during this interval.
    public static let freshnessInterval: TimeInterval = 60

    public static func measure(path: String = "/") -> DiskStatus {
        let url = URL(fileURLWithPath: path)
        var keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]
#if os(macOS)
        keys.insert(.volumeAvailableCapacityForImportantUsageKey)
        keys.insert(.volumeAvailableCapacityForOpportunisticUsageKey)
#endif

        do {
            let values = try url.resourceValues(forKeys: keys)
            let total = values.volumeTotalCapacity.map(Int64.init)
            let basicAvailable = values.volumeAvailableCapacity.map(Int64.init)
#if os(macOS)
            let important = values.volumeAvailableCapacityForImportantUsage
            let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage
#else
            let important = basicAvailable
            let opportunistic: Int64? = nil
#endif
            let filesystemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: path)
            let filesystemFree = (filesystemAttributes?[.systemFreeSize] as? NSNumber)?.int64Value
            let immediate = filesystemFree ?? basicAvailable

            guard let total, let important, total > 0, important >= 0 else {
                return DiskStatus(
                    filesystem: values.volumeName ?? "Startup volume",
                    state: .failed,
                    measuredAt: Date(),
                    source: "Foundation URL volume capacity keys",
                    detail: "Total capacity or capacity available for important usage was unavailable."
                )
            }

            let usedEstimate = max(0, total - important)
            let purgeable = max(0, important - (immediate ?? important))
            var state: StorageMeasurementState = immediate == nil || opportunistic == nil ? .partial : .fresh
            var detail = "Available for work uses the strongest volume-capacity key available on this platform. Immediately free is reported separately."

            if let basicAvailable, let filesystemFree {
                let tolerance = max(disagreementToleranceFloor, Int64(Double(total) * disagreementToleranceFraction))
                let difference = abs(basicAvailable - filesystemFree)
                if difference > tolerance {
                    state = .disputed
                    detail += " The general URL capacity and filesystem immediately-free values differ by \(format(difference)), above the \(format(tolerance)) tolerance."
                }
            } else if state == .fresh {
                state = .partial
                detail += " The filesystem free-space cross-check was unavailable."
            }

            let usedPercent = total > 0 ? Double(usedEstimate) / Double(total) : 0
            return DiskStatus(
                filesystem: values.volumeName ?? "Startup volume",
                size: format(total),
                used: format(usedEstimate),
                available: format(important),
                capacity: String(format: "%.0f%% used estimate", usedPercent * 100),
                totalBytes: total,
                immediatelyFreeBytes: immediate,
                availableForWorkBytes: important,
                opportunisticBytes: opportunistic,
                potentiallyPurgeableBytes: purgeable,
                usedEstimateBytes: usedEstimate,
                state: state,
                measuredAt: Date(),
                source: "Foundation important-usage capacity with FileManager filesystem immediately-free cross-check",
                detail: detail
            )
        } catch {
            return DiskStatus(
                filesystem: "Startup volume",
                state: .failed,
                measuredAt: Date(),
                source: "Foundation URL volume capacity keys",
                detail: "Storage capacity measurement failed: \(error.localizedDescription)"
            )
        }
    }

    public static func cached(_ status: DiskStatus, reason: String) -> DiskStatus {
        var copy = status
        copy.state = .cached
        copy.detail = "\(status.detail) Cached because \(reason)"
        return copy
    }

    public static func presentationStatus(_ status: DiskStatus, now: Date = Date()) -> DiskStatus {
        guard status.state == .fresh, let measuredAt = status.measuredAt else { return status }
        guard now.timeIntervalSince(measuredAt) > freshnessInterval else { return status }
        return cached(status, reason: "the measurement is older than the \(Int(freshnessInterval))-second freshness interval.")
    }

    public static func displayTimestamp(
        _ date: Date?,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let date else { return "Not yet" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct MountedFilesystemRecord: Hashable, Sendable {
    public var deviceIdentity: String
    public var filesystemIdentity: String
    public var mountPath: String

    public init(deviceIdentity: String, filesystemIdentity: String, mountPath: String) {
        self.deviceIdentity = deviceIdentity
        self.filesystemIdentity = filesystemIdentity
        self.mountPath = mountPath
    }
}

public enum MountedFilesystemDeduplicator {
    public static func unique(_ records: [MountedFilesystemRecord]) -> [MountedFilesystemRecord] {
        var seen = Set<String>()
        return records.filter { record in
            seen.insert("\(record.deviceIdentity)|\(record.filesystemIdentity)").inserted
        }
    }
}
