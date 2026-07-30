import DexCleanerCore
import SwiftUI

struct StorageIncidentsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let certificationReduceMotion: Bool?
    @State private var localPath = ""
    @State private var cloudPath = ""
    @State private var provider = ""

    init(certificationReduceMotion: Bool? = nil) {
        self.certificationReduceMotion = certificationReduceMotion
    }

    static func certificationAccessibilityLabels(for model: AppModel) -> [String] {
        var labels = [
            "Recorder status: \(model.recorderStatusText)",
            "Reduce Motion is enabled",
            "Ordinary local comparison directory",
            "Already-local cloud comparison directory",
            "Cloud provider name"
        ]
        if model.isWorking, model.diagnosticOperations.first?.cancellable == true {
            labels.append("Cancel active diagnostic operation")
        }
        if model.diagnosticOperations.contains(where: { $0.state == .running && $0.total == nil }) {
            labels.append("Operation in progress")
        }
        return labels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Incidents").font(.title2.bold())
                    Text("Persistent, local-only evidence. Diagnostics never create cleanup authority.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.recorderStatusText, systemImage: recorderIcon)
                    .font(.headline)
                    .accessibilityLabel("Recorder status: \(model.recorderStatusText)")
            }
            HStack(spacing: 10) {
                card("Coverage", model.recorderCoverageText, "waveform.path.ecg")
                card("Reserve", model.recorderReserveText, "lifepreserver")
                card("Activity", model.diagnosticOperations.first?.phase ?? "Idle", "timer")
            }
            HStack(spacing: 10) {
                card("Immediately free", model.immediatelyFreeText, "internaldrive")
                card("Available for work", model.availableForWorkText, "externaldrive")
                card("Launch at Login", model.launchAtLoginEnabled ? "Enabled" : "Disabled", "power")
            }
            HStack(spacing: 8) {
                Button { model.investigateNow() } label: { Label("Investigate Now", systemImage: "waveform.path.ecg.rectangle") }
                    .disabled(model.isWorking)
                Button { model.inspectCloudStorage() } label: { Label("Inspect Cloud", systemImage: "icloud.and.arrow.down") }
                    .disabled(model.isWorking)
                Button { model.finishIncident() } label: { Label("Finish Active Incident", systemImage: "doc.badge.checkmark") }
                    .disabled(model.isWorking)
                Button { model.refreshRepeatedPattern() } label: { Label("Refresh Patterns", systemImage: "repeat") }
                    .disabled(model.isWorking)
                Button { model.requestDeepTraceExplanation() } label: { Label("Deep Trace", systemImage: "point.3.connected.trianglepath.dotted") }
                    .disabled(model.isWorking)
                Button { model.rebuildEmergencyReserve() } label: { Label("Rebuild Reserve", systemImage: "lifepreserver") }
                    .disabled(model.isWorking)
                if model.isWorking, model.diagnosticOperations.first?.cancellable == true {
                    Button { model.cancel() } label: { Label("Cancel", systemImage: "xmark.circle") }
                        .accessibilityLabel("Cancel active diagnostic operation")
                }
                Spacer()
            }
            .buttonStyle(DexButtonStyle())
            comparisonControls
            incidentList
            activityList
            patternList
            comparisonList
            reserveList
            deepTraceList
            cloudList
            reportControls
        }
        .padding(10)
        .onAppear { model.openStorageIncidents() }
    }

    private func card(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).lineLimit(2)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var incidentList: some View {
        GroupBox("Recent incidents") {
            if model.incidents.isEmpty {
                Text("Insufficient incident history. The armed recorder will preserve future capacity losses without running a recurring disk crawl.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(model.incidents.prefix(12)) { incident in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(incident.trigger.rawValue).font(.headline); Spacer(); Text(ByteCountFormatter.string(fromByteCount: incident.lossBytes, countStyle: .file)).font(.caption.monospacedDigit()) }
                        Text("\(incident.completeness.rawValue) · \(incident.explainedPercentage)% explained · \(incident.startedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Unexplained allocation change: \(ByteCountFormatter.string(fromByteCount: incident.system.unexplainedBytes, countStyle: .file)). No cleanup occurred.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    if incident.id != model.incidents.prefix(12).last?.id { Divider() }
                }
            }
        }
    }

    private var activityList: some View {
        GroupBox("Activity Center") {
            if model.diagnosticOperations.isEmpty { Text("No recorder operations yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(model.diagnosticOperations.prefix(6)) { operation in
                HStack {
                    VStack(alignment: .leading) {
                        Text(operation.type).font(.caption.weight(.semibold))
                        Text("\(operation.phase) · \(operation.state.rawValue) · \(operation.elapsed(), specifier: "%.1f")s")
                            .font(.caption2).foregroundStyle(.secondary)
                        if !operation.summary.isEmpty { Text(operation.summary).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let total = operation.total {
                        VStack(alignment: .trailing) {
                            ProgressView(value: Double(operation.processed), total: Double(max(1, total)))
                                .frame(width: 80)
                            Text("\(operation.processed) of \(total)").font(.caption.monospacedDigit())
                        }
                    } else if operation.state == .running {
                        ProgressView().controlSize(.small).accessibilityLabel("Operation in progress")
                    }
                }.padding(.vertical, 3)
            }
        }
    }

    private var patternList: some View { GroupBox("Repeated patterns") { if let pattern = model.repeatedPattern { Text("\(pattern.kind.rawValue) · \(pattern.confidence) · \(pattern.occurrences) occurrences").font(.caption); Text(pattern.supporting.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary); Text("Diagnostic correlation only. It cannot select or clean files.").font(.caption2).foregroundStyle(.secondary) } else { Text("Not analyzed. Pattern findings are diagnostic only.").font(.caption).foregroundStyle(.secondary) } } }
    private var comparisonList: some View { GroupBox("Local and cloud comparison") { if let item = model.localCloudComparisons.first { VStack(alignment: .leading, spacing: 3) { Text("\(item.classification.rawValue) · \(item.confidence)").font(.caption.weight(.semibold)); Text("Local: \(item.localRoot)"); Text("Cloud: \(item.cloudRoot)"); Text("\(item.provider) · \(item.providerMode.rawValue) · \(item.coverage.rawValue)"); Text("\(item.filesSampled) files · \(item.placeholdersSkipped) placeholders skipped · \(item.bytesRead) bytes read"); Text("Allocation: local \(item.localPhysicalAllocation), cloud \(item.cloudPhysicalAllocation) · disposition \(item.disposition.rawValue)"); if !item.limitsReached.isEmpty { Text("Limits: \(item.limitsReached.joined(separator: ", "))") }; Text("\(item.reason) Safe actions: \(item.safeActions.joined(separator: ", "))."); Text("Diagnostic only — not authorized for cleanup.") }.font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) } else { Text("No comparison yet. Only already-resident metadata is eligible; placeholders are never opened.").font(.caption).foregroundStyle(.secondary) } } }

    private var comparisonControls: some View {
        GroupBox("Compare resident copies") {
            HStack {
                TextField("Ordinary local directory", text: $localPath)
                    .accessibilityLabel("Ordinary local comparison directory")
                TextField("Already-local cloud directory", text: $cloudPath)
                    .accessibilityLabel("Already-local cloud comparison directory")
                TextField("Provider", text: $provider)
                    .frame(width: 120)
                    .accessibilityLabel("Cloud provider name")
                Button { model.compareCopies(localPath: localPath, cloudPath: cloudPath, provider: provider) } label: {
                    Label(model.isWorking ? "Comparing…" : "Compare Copies", systemImage: "rectangle.2.swap")
                }
                .disabled(model.isWorking || localPath.isEmpty || cloudPath.isEmpty)
                .buttonStyle(DexButtonStyle())
            }
            Text("Names alone are never duplicate proof. Symlinks, filesystem crossings, dataless files, and placeholders are refused.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var reserveList: some View {
        GroupBox("Emergency reserve") {
            VStack(alignment: .leading, spacing: 3) {
                if let reserve = model.emergencyReserveActivity {
                    Text("\(reserve.state.rawValue) · target \(ByteCountFormatter.string(fromByteCount: reserve.targetBytes, countStyle: .file))")
                    Text("Actual physical allocation: \(ByteCountFormatter.string(fromByteCount: reserve.allocatedBytes, countStyle: .file))")
                    Text("Last creation: \(reserve.lastCreation?.formatted() ?? "Never") · last release: \(reserve.lastRelease?.formatted() ?? "Never")")
                    Text("Bytes restored: \(reserve.releasedBytes) · \(reserve.eligibilityReason)")
                    if let failure = reserve.failureReason { Text("Failure: \(failure)") }
                } else {
                    Text("Pending Safe Conditions. The 1 GiB DexCleaner-owned reserve visibly consumes storage and is never created automatically without all safety conditions.")
                }
                Text("The reserve contains no user data. It is the only file DexCleaner may release automatically.")
                    .foregroundStyle(.secondary)
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deepTraceList: some View {
        GroupBox("Deep incident trace") {
            VStack(alignment: .leading, spacing: 3) {
                if let trace = model.deepTraceEvidence {
                    Text("\(trace.state.rawValue) · \(trace.authorizationState) · \(trace.coverage.rawValue)")
                    Text("\(trace.relevantOperations) relevant operations · \(trace.duration, specifier: "%.1f") seconds")
                    Text(trace.summary)
                } else {
                    Text("Available but disabled. It is never automatic or continuous.")
                }
                Text("A trace observes bounded process, path, operation, and timing metadata for at most 60 seconds. It collects no file contents, discards unrelated events, redacts sensitive arguments, may require authorization, and remains diagnostic only.")
                    .foregroundStyle(.secondary)
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reportControls: some View {
        HStack {
            Button { model.copyLatestIncidentForChatGPT() } label: { Label(model.incidentActionText == "Copied" ? "Copied" : "Copy for ChatGPT", systemImage: "doc.on.doc") }
                .disabled(model.incidents.isEmpty)
            Button { model.exportLatestIncidentReport() } label: { Label(model.incidentActionText == "Report Exported" ? "Report Exported" : "Export Report", systemImage: "square.and.arrow.up") }
                .disabled(model.incidents.isEmpty)
            if !model.incidentActionText.isEmpty { Text(model.incidentActionText).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text(effectiveReduceMotion ? "Reduce Motion enabled" : "Standard motion")
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel(effectiveReduceMotion ? "Reduce Motion is enabled" : "Standard motion is enabled")
        }.buttonStyle(DexButtonStyle())
    }

    private var cloudList: some View {
        GroupBox("Cloud Storage Inspector") {
            if model.cloudEvidence.isEmpty { Text("Not inspected. Cloud inspection is metadata-only and never downloads, evicts, or changes provider state.").font(.caption).foregroundStyle(.secondary) }
            ForEach(model.cloudEvidence) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.provider).font(.caption.weight(.semibold))
                    Text("Allocated \(ByteCountFormatter.string(fromByteCount: item.allocatedUserBytes + item.cacheBytes + item.databaseBytes, countStyle: .file)) · logical \(ByteCountFormatter.string(fromByteCount: item.logicalBytes, countStyle: .file)) · placeholders \(ByteCountFormatter.string(fromByteCount: item.placeholderBytes, countStyle: .file))")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 2)
            }
        }
    }

    private var recorderIcon: String { model.recorderStatusText == RecorderStatus.recording.rawValue ? "record.circle" : "exclamationmark.circle" }
    private var effectiveReduceMotion: Bool { certificationReduceMotion ?? reduceMotion }
}
