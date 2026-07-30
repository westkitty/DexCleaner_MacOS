import Charts
import DexCleanerCore
import SwiftUI

struct StorageHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRecord: CapacityHistoryRecord.ID?
    @State private var note = ""
    @State private var warningGB = 10
    @State private var recoveryGB = 12
    @State private var criticalGB = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Storage History").font(.title2.bold())
                    Text("Collection began with DexCleaner 1.2.0. Capacity history records change; it does not assign cause.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Range", selection: $model.selectedHistoryRange) {
                    ForEach(CapacityResolution.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
                .onChange(of: model.selectedHistoryRange) { range in model.refreshHistory(range: range) }
            }
            summary
            chart
            inspection
            HStack {
                TextField("Optional timeline note", text: $note)
                Button("Add note") { model.addManualHistoryNote(note); note = "" }.dexInteractive()
                Button("Refresh history") { model.refreshHistory() }.dexInteractive()
                Button("Export JSON") { model.exportHistory(format: "json") }.dexInteractive()
                Button("Export CSV") { model.exportHistory(format: "csv") }.dexInteractive()
                Button("Request notifications") { model.requestNotificationPermission() }.dexInteractive()
            }
            .textFieldStyle(.roundedBorder)
            GroupBox("Low-storage thresholds") {
                HStack {
                    Stepper("Warning \(warningGB) GB", value: $warningGB, in: 2...500)
                    Stepper("Recovery \(recoveryGB) GB", value: $recoveryGB, in: 3...500)
                    Stepper("Critical \(criticalGB) GB", value: $criticalGB, in: 1...499)
                    Button("Save") { model.updateAlertThresholds(warningGB: warningGB, recoveryGB: recoveryGB, criticalGB: criticalGB) }.dexInteractive()
                }
                Text("Warning is based on Immediately free. Recovery must exceed warning; critical must be lower. Alerts are local and never invoke cleanup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Storage may change because of APFS, downloads, builds, local models, media exports, cloud sync, swap, temporary files, system updates, Trash, or purgeable capacity. DexCleaner does not infer which cause applies without measured evidence.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .onAppear {
            let billion: Int64 = 1_000_000_000
            warningGB = Int(model.alertConfiguration.warningBytes / billion)
            recoveryGB = Int(model.alertConfiguration.recoveryBytes / billion)
            criticalGB = Int(model.alertConfiguration.criticalBytes / billion)
            model.refreshHistory()
        }
    }

    private var summary: some View {
        let records = model.historyStatistics.records
        let first = records.first, last = records.last
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
            metric("Current Available for work", bytes(last?.availableForWorkBytes))
            metric("Current Immediately free", bytes(last?.immediatelyFreeBytes))
            metric("Starting Available for work", bytes(first?.availableForWorkBytes))
            metric("Starting Immediately free", bytes(first?.immediatelyFreeBytes))
            metric("Net Available for work", signed(change(from: first?.availableForWorkBytes, to: last?.availableForWorkBytes)))
            metric("Net Immediately free", signed(change(from: first?.immediatelyFreeBytes, to: last?.immediatelyFreeBytes)))
            metric("Minimum", bytes(model.historyStatistics.minimum))
            metric("Maximum", bytes(model.historyStatistics.maximum))
            metric("Average", bytes(model.historyStatistics.average))
            metric("Coverage", String(format: "%.0f%%", model.historyStatistics.coveragePercent))
            metric("Longest gap", model.historyStatistics.containsGap ? duration(model.historyStatistics.longestGap) : "No material gap")
            metric("Records", "\(model.historyStatistics.records.count) · raw \(model.historySummary.rawSampleCount) · aggregate \(model.historySummary.aggregateCount)")
            metric("Oldest", StorageCapacityProvider.displayTimestamp(model.historySummary.oldest))
            metric("Newest", StorageCapacityProvider.displayTimestamp(model.historySummary.newest))
            metric("History size", bytes(model.historySummary.bytes))
            metric("Schema", "v\(model.historySummary.schemaVersion)\(model.historySummary.growthSuspended ? " · growth paused" : "")")
        }
    }

    private var chart: some View {
        return Chart(model.historyStatistics.records) { record in
            if let value = record.availableForWorkBytes {
                LineMark(x: .value("Time", record.end), y: .value("Storage", value), series: .value("Metric", CapacityMetric.availableForWork.rawValue))
                    .foregroundStyle(by: .value("Metric", CapacityMetric.availableForWork.rawValue)).lineStyle(StrokeStyle(lineWidth: 2, dash: record.isAggregate ? [4, 3] : []))
                    .interpolationMethod(.linear)
                if record.isAggregate { PointMark(x: .value("Time", record.end), y: .value("Available for work", value)).symbolSize(16) }
            }
            if let value = record.immediatelyFreeBytes {
                LineMark(x: .value("Time", record.end), y: .value("Storage", value), series: .value("Metric", CapacityMetric.immediatelyFree.rawValue))
                    .foregroundStyle(by: .value("Metric", CapacityMetric.immediatelyFree.rawValue)).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 3])).interpolationMethod(.linear)
            }
            if record.state == .failed { RuleMark(x: .value("Failed", record.end)).foregroundStyle(.red).lineStyle(StrokeStyle(dash: [2, 2])) }
            RuleMark(y: .value("Warning", model.alertConfiguration.warningBytes)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])).annotation(position: .leading) { Text("Warning \(gigabytes(model.alertConfiguration.warningBytes))").font(.caption2) }
            RuleMark(y: .value("Critical", model.alertConfiguration.criticalBytes)).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])).annotation(position: .leading) { Text("Critical \(gigabytes(model.alertConfiguration.criticalBytes))").font(.caption2) }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
        .chartYAxis { AxisMarks { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let bytes = value.as(Int64.self) { Text(gigabytes(bytes)) } } } }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 260)
        .overlay {
            if model.historyStatistics.records.count < 2 {
                VStack(spacing: 5) {
                    Image(systemName: "chart.xyaxis.line")
                    Text("Insufficient history").font(.headline)
                    Text("DexCleaner will build local history while it runs. No intermediate values are invented.").font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Storage history chart. Available for work uses a solid line. Immediately free uses a dashed line. \(model.historyStatistics.containsGap ? "The selected period contains a collection gap." : "No material collection gap is recorded.")")
    }

    private var inspection: some View {
        let records = model.historyStatistics.records
        return VStack(alignment: .leading, spacing: 5) {
            Picker("Inspect measurement", selection: $selectedRecord) {
                Text("Select a measurement").tag(CapacityHistoryRecord.ID?.none)
                ForEach(records) { record in Text(StorageCapacityProvider.displayTimestamp(record.end)).tag(Optional(record.id)) }
            }
            .pickerStyle(.menu)
            if let selectedRecord, let record = records.first(where: { $0.id == selectedRecord }) {
                Text(inspectionText(record)).font(.caption).accessibilityLabel(inspectionText(record))
            } else { Text("Select a chart measurement to inspect both metrics, state, and aggregate range.").font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.caption.weight(.semibold)).lineLimit(2) }.padding(7).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)) }
    private func bytes(_ value: Int64?) -> String { guard let value else { return "Unavailable" }; return ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func gigabytes(_ value: Int64) -> String { "\(Int((Double(value) / 1_000_000_000).rounded())) GB" }
    private func signed(_ value: Int64?) -> String { guard let value else { return "Insufficient history" }; return (value >= 0 ? "+" : "") + bytes(value) }
    private func change(from: Int64?, to: Int64?) -> Int64? { guard let from, let to else { return nil }; return to - from }
    private func duration(_ value: TimeInterval) -> String { value < 60 ? "None" : DateComponentsFormatter().string(from: value) ?? "Unavailable" }
    private func inspectionText(_ record: CapacityHistoryRecord) -> String {
        let interval = record.isAggregate ? "Aggregate \(StorageCapacityProvider.displayTimestamp(record.start)) to \(StorageCapacityProvider.displayTimestamp(record.end))" : StorageCapacityProvider.displayTimestamp(record.end)
        var text = "\(interval). Available for work: \(bytes(record.availableForWorkBytes)). Immediately free: \(bytes(record.immediatelyFreeBytes)). \(record.isAggregate ? "Aggregated" : "Raw") \(record.state.rawValue)."
        if record.isAggregate { text += " Available range: \(bytes(record.minimumAvailableForWorkBytes)) to \(bytes(record.maximumAvailableForWorkBytes)). Free range: \(bytes(record.minimumImmediatelyFreeBytes)) to \(bytes(record.maximumImmediatelyFreeBytes))." }
        return text
    }
}
