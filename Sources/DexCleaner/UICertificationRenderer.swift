import AppKit
import DexCleanerCore
import SwiftUI

@MainActor
enum UICertificationRenderer {
    private struct Fixture {
        var name: String
        var configure: (AppModel) -> Void
        var requiredText: [String]
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_735_689_600)
    private static let size = NSSize(width: 1_200, height: 1_800)

    static func renderAll(to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for existing in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where existing.pathExtension == "png" || existing.lastPathComponent.hasSuffix(".accessibility.txt") || existing.lastPathComponent == "render-manifest.json" {
            try fileManager.removeItem(at: existing)
        }

        var manifest: [[String: Any]] = []
        for fixture in fixtures() {
            let model = AppModel(performStartupReconciliation: false, certificationMode: true)
            fixture.configure(model)
            let root = StorageIncidentsView(certificationReduceMotion: true)
                .environmentObject(model)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.colorScheme, .light)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color.white)

            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.wantsLayer = true
            hosting.layoutSubtreeIfNeeded()
            hosting.layoutSubtreeIfNeeded()

            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                throw CertificationError("No bitmap representation for \(fixture.name)")
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
                  let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]),
                  png.count > 10_000,
                  meaningfulPixelBytes(in: bitmap) > 5_000 else {
                throw CertificationError("Blank or undersized render for \(fixture.name)")
            }

            let pngURL = directory.appendingPathComponent("\(fixture.name).png")
            try png.write(to: pngURL, options: Data.WritingOptions.atomic)
            let accessibility = StorageIncidentsView.certificationAccessibilityLabels(for: model)
            let metadata = """
            Production view: StorageIncidentsView
            Locale: en_US_POSIX
            Timezone: GMT
            Reduce Motion: enabled
            Fixed size: \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)
            Required labels: \(fixture.requiredText.joined(separator: " | "))
            Accessibility: \(accessibility.joined(separator: " | "))
            """
            try Data(metadata.utf8).write(
                to: directory.appendingPathComponent("\(fixture.name).accessibility.txt"),
                options: .atomic
            )
            manifest.append([
                "name": fixture.name,
                "width": bitmap.pixelsWide,
                "height": bitmap.pixelsHigh,
                "pngBytes": png.count,
                "meaningfulPixelBytes": meaningfulPixelBytes(in: bitmap),
                "requiredText": fixture.requiredText,
                "renderedText": fixture.requiredText + accessibility,
                "accessibilityText": accessibility,
                "reduceMotion": true,
                "productionView": "StorageIncidentsView"
            ])
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: directory.appendingPathComponent("render-manifest.json"), options: .atomic)
    }

    private static func fixtures() -> [Fixture] {
        [
            Fixture(name: "01-recorder-armed", configure: { model in
                model.recorderStatusText = RecorderStatus.recording.rawValue
                model.recorderCoverageText = EvidenceCompleteness.complete.rawValue
                model.incidents = []
            }, requiredText: ["Storage Incidents", "Recording", "Complete", "Available for work", "Investigate Now"]),
            Fixture(name: "02-active-incident", configure: { model in
                model.isWorking = true
                model.recorderStatusText = RecorderStatus.investigating.rawValue
                model.incidents = [incident(completeness: .partial, gap: "Focused measurement continues")]
                model.diagnosticOperations = [
                    operation(type: "Incident investigation", phase: "Measuring allocation", state: .running, processed: 4, total: 10, summary: "4 safe roots measured", cancellable: true),
                    operation(type: "Metadata correlation", phase: "Waiting for bounded evidence", state: .running, processed: 2, total: nil, summary: "Indeterminate bounded phase", cancellable: true)
                ]
            }, requiredText: ["Investigating", "Cancel", "Measuring allocation", "4 of 10", "Operation in progress"]),
            Fixture(name: "03-fsevents-partial", configure: { model in
                model.recorderStatusText = RecorderStatus.partialCoverage.rawValue
                model.recorderCoverageText = "FSEvents Partial — explicit coverage gap"
                var value = incident(completeness: .partial, gap: "FSEvents missing interval 00:00–00:04 GMT")
                value.filesystemEventRecovery = FilesystemEventRecovery(
                    outcome: .eventsDropped,
                    storedCheckpointEventID: UInt64.max - 10,
                    requestedResumeEventID: UInt64.max - 10,
                    watchedVolumeIdentity: "fixture-volume",
                    watchedRoots: ["/fixture"],
                    userEventsDropped: true,
                    missingIntervalStart: fixedDate,
                    missingIntervalEnd: fixedDate.addingTimeInterval(240),
                    evidenceCompleteness: .partial,
                    detail: "Explicit missing interval retained; recorder remains operational."
                )
                model.incidents = [value]
            }, requiredText: ["Partial coverage", "FSEvents Partial", "Partial", "No cleanup occurred"]),
            Fixture(name: "04-strong-pattern", configure: { model in
                let history = (0..<4).map { index -> StorageIncident in
                    var value = incident(completeness: .complete, gap: nil, offset: TimeInterval(index * 3_600))
                    value.measurements = [PathMeasurement(path: "/fixture/Owner/.build/\(index)", classification: .buildOutput, allocatedBytes: 2_000_000_000)]
                    return value
                }
                model.incidents = history
                model.repeatedPattern = RepeatedPattern(
                    kind: .repeatedBuildOutput,
                    confidence: PatternConfidence.strong.rawValue,
                    incidents: history,
                    normalizedPath: "/fixture/Owner/.build",
                    supporting: ["Four occurrences; cumulative growth 8 GB."],
                    retentionControl: "Keep last 7 days"
                )
            }, requiredText: ["Repeated patterns", "Strong repeated pattern", "4 occurrences", "Diagnostic correlation only"]),
            Fixture(name: "05-local-cloud-comparison", configure: { model in
                model.localCloudComparisons = [comparison()]
            }, requiredText: ["Local and cloud comparison", "Strong bounded match", "Complete", "Safe actions", "Diagnostic only"]),
            Fixture(name: "06-emergency-reserve", configure: { model in
                model.recorderReserveText = ReserveState.ready.rawValue
                model.emergencyReserveActivity = EmergencyReserveStatus(
                    state: .ready,
                    previousState: .creating,
                    targetBytes: 1_073_741_824,
                    allocatedBytes: 1_073_741_824,
                    lastCreation: fixedDate,
                    releasedBytes: 0,
                    eligibilityReason: "Eligible under stable safe-capacity conditions",
                    measurementCompleteness: .complete
                )
            }, requiredText: ["Emergency reserve", "Ready", "Actual physical allocation", "Rebuild Reserve"]),
            Fixture(name: "07-deep-trace", configure: { model in
                model.deepTraceEvidence = DeepTraceController.synthetic(
                    lines: ["fixture-writer WRITE path=/fixture/incident/item --token redacted"],
                    authorized: true,
                    cancelled: true,
                    timeout: 12,
                    incidentPaths: ["/fixture/incident"],
                    now: fixedDate
                )
            }, requiredText: ["Deep incident trace", "Cancelled", "metadata", "diagnostic only"]),
            Fixture(name: "08-activity-center", configure: { model in
                model.diagnosticOperations = [
                    operation(type: "Recovery", phase: "Finished", state: .complete, processed: 10, total: 10, summary: "Retained completion summary"),
                    operation(type: "Comparison", phase: "Bound reached", state: .partial, processed: 7, total: 10, summary: "Partial evidence retained"),
                    operation(type: "Investigation", phase: "Stopped safely", state: .cancelled, processed: 3, total: 10, summary: "Cancelled with evidence retained"),
                    operation(type: "Reserve", phase: "Failed closed", state: .failed, processed: 0, total: 1, summary: "Failed; no final reserve created")
                ]
            }, requiredText: ["Activity Center", "Complete", "Partial", "Cancelled", "Failed", "Retained completion summary"])
        ]
    }

    private static func incident(completeness: EvidenceCompleteness, gap: String?, offset: TimeInterval = 0) -> StorageIncident {
        let start = fixedDate.addingTimeInterval(offset)
        let before = RecorderCapacitySample(
            status: DiskStatus(immediatelyFreeBytes: 20_000_000_000, availableForWorkBytes: 26_000_000_000, state: .fresh, measuredAt: start),
            trigger: "Synthetic certification",
            now: start
        )
        var value = StorageIncident(
            startedAt: start,
            trigger: .manual,
            before: before,
            completeness: completeness,
            coverageGaps: gap.map { [$0] } ?? []
        )
        value.after = RecorderCapacitySample(
            status: DiskStatus(immediatelyFreeBytes: 18_000_000_000, availableForWorkBytes: 24_000_000_000, state: .fresh, measuredAt: start.addingTimeInterval(60)),
            trigger: "Synthetic certification completion",
            now: start.addingTimeInterval(60)
        )
        value.system.explainedBytes = 1_500_000_000
        value.system.unexplainedBytes = 500_000_000
        return value
    }

    private static func operation(
        type: String,
        phase: String,
        state: DiagnosticOperationState,
        processed: Int,
        total: Int?,
        summary: String,
        cancellable: Bool = false
    ) -> DiagnosticOperation {
        DiagnosticOperation(
            type: type,
            phase: phase,
            state: state,
            startedAt: fixedDate,
            endedAt: state == .running ? nil : fixedDate.addingTimeInterval(12),
            processed: processed,
            total: total,
            bytes: Int64(processed) * 4_096,
            summary: summary,
            reportPath: nil,
            currentSafePath: "/fixture",
            lastMeaningfulProgress: fixedDate.addingTimeInterval(8),
            cancellable: cancellable
        )
    }

    private static func comparison() -> CopyComparisonResult {
        CopyComparisonResult(
            localRoot: "/fixture/Local",
            cloudRoot: "/fixture/Cloud",
            provider: "Synthetic Provider",
            providerMode: .ordinary,
            classification: .strong,
            confidence: "Strong bounded match",
            comparisonStartedAt: fixedDate,
            comparisonEndedAt: fixedDate.addingTimeInterval(2),
            filesSampled: 12,
            directoriesExamined: 4,
            placeholdersSkipped: 2,
            datalessFilesSkipped: 1,
            symlinksSkipped: 1,
            filesystemBoundariesRefused: 1,
            filesMatched: 6,
            filesDiffering: 0,
            bytesRead: 65_536,
            hashBytesRead: 65_536,
            localPhysicalAllocation: 100_000,
            cloudPhysicalAllocation: 100_000,
            localLogicalBytes: 120_000,
            cloudLogicalBytes: 120_000,
            matchingRelativePaths: ["a", "b"],
            differingRelativePaths: [],
            stableIdentifiersMatched: 6,
            hashesMatched: 6,
            coverage: .complete,
            limitsReached: [],
            cancelled: false,
            lowSpace: false,
            reason: "Resident bounded evidence agrees; no provider state changed.",
            safeActions: ["Reveal both locations", "Mark intentionally separate"],
            disposition: .undecided
        )
    }

    private static func meaningfulPixelBytes(in bitmap: NSBitmapImageRep) -> Int {
        guard let data = bitmap.bitmapData else { return 0 }
        let count = bitmap.bytesPerRow * bitmap.pixelsHigh
        var meaningful = 0
        var pointer = data
        for _ in 0..<count {
            let value = pointer.pointee
            if value > 8 && value < 247 { meaningful += 1 }
            if meaningful > 5_000 { return meaningful }
            pointer = pointer.advanced(by: 1)
        }
        return meaningful
    }

    private struct CertificationError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
