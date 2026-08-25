import DexCleanerCore
import SwiftUI

struct CleanupCampaignView: View {
    @EnvironmentObject var model: AppModel
    let reviewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Evidence-driven cleanup campaign").font(.title2.bold())
                    Text("Explicit audit, grouped proof, exact selection, immutable Preview, Finder Trash, receipt, re-audit, then STOP.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.currentCampaignID == nil ? "Start Campaign" : "Re-audit Campaign") { model.startCleanupCampaign() }
                    .buttonStyle(.borderedProminent).disabled(model.isWorking)
            }
            if let progress = model.campaignProgress {
                HStack {
                    Label(progress.phase, systemImage: progress.state == .running ? "hourglass" : "checkmark.circle")
                    Spacer()
                    Text("\(progress.candidatesConsidered) findings | \(progress.partialResultCount) bounded domains").font(.caption.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
            if let stop = model.campaignStopRecommendation {
                VStack(alignment: .leading, spacing: 4) {
                    Label(stop.shouldStop ? "STOP recommended" : "Evidence-backed candidates remain", systemImage: stop.shouldStop ? "hand.raised.fill" : "checkmark.shield")
                        .font(.headline)
                    ForEach(stop.reasons, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Text("Actionable \(stop.actionableCount) | Review \(stop.reviewCount) | Protected \(stop.protectedCount) | Unknown \(stop.unknownCount)").font(.caption.monospacedDigit())
                }
                .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.campaignDomains.isEmpty {
                Text("Start the campaign to collect bounded evidence. Destructive action remains unavailable until an exact candidate is selected and Preview succeeds.").foregroundStyle(.secondary)
            } else {
                ForEach(model.campaignDomains, id: \.domain) { domain in
                    HStack(alignment: .top) {
                        Image(systemName: domain.completeness == .complete ? "checkmark.circle" : "exclamationmark.circle").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(domain.domain.rawValue).font(.subheadline.bold())
                            Text(domain.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(domain.actionableCount) actionable / \(domain.findingCount)").font(.caption.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack {
                    Button("Review Findings") { reviewAction() }.buttonStyle(.bordered)
                    if let receipt = model.lastReceiptURL { Text("Receipt: \(receipt.lastPathComponent)").font(.caption).textSelection(.enabled) }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
