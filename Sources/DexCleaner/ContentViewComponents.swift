import DexCleanerCore
import Foundation
import SwiftUI

struct AdaptiveStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            content()
            ScrollView(.horizontal, showsIndicators: false) { content() }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    init(_ title: String, _ value: String, _ detail: String, _ icon: String) {
        self.title = title
        self.value = value
        self.detail = detail
        self.icon = icon
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value). \(detail)")
    }
}

struct DetailGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, _ icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            content()
        }
        .padding(9).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?
    init(title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity, minHeight: 150).padding()
    }
}

struct ScanItemRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ScanItem
    let interactive: Bool
    let now: Date
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if interactive {
                Toggle("Select \(item.displayName)", isOn: Binding(
                    get: { model.items.first(where: { $0.id == item.id })?.isSelected ?? false },
                    set: { _ in model.toggle(item) }
                ))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(model.isWorking)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.displayName).font(.headline)
                    if isSelected { StatusPill(text: "Selected", systemImage: "checkmark") }
                    Spacer()
                    Text(item.sizeBytes > 0 ? item.formattedSize : "Not measured").font(.caption.monospacedDigit().weight(.semibold))
                }
                HStack {
                    StatusPill(text: item.risk.rawValue, systemImage: item.risk == .safe ? "checkmark.shield" : "eye")
                    StatusPill(text: item.category.rawValue, systemImage: "tag")
                    if let id = item.manifestID { StatusPill(text: "ID \(id)", systemImage: "number") }
                }
                if item.owningProcessRunning {
                    Label("Owning app appears active. Close it before Preview when practical.", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                }
                Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(isExpanded ? nil : 1).textSelection(.enabled)
                HStack {
                    Label(model.measurementAgeText(for: item, at: now), systemImage: measurementIcon).font(.caption2).foregroundStyle(.secondary)
                    if model.measurementIsStale(for: item, at: now) {
                        StatusPill(text: "Over 15 min old", systemImage: "clock")
                    }
                    Spacer()
                    Button(isExpanded ? "Less" : "Details") { onToggleExpanded() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityHint(isExpanded ? "Collapses explanation and recovery details." : "Expands explanation and recovery details.")
                    if model.canReveal(item) {
                        Button("Reveal") { model.reveal(item) }.buttonStyle(.bordered).controlSize(.small)
                    }
                    FeedbackButton(title: "Copy Path", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyPath(item) }
                }
                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.explanation).font(.caption2).foregroundStyle(.secondary)
                        Text("Recovery: \(item.recoveryNote)").font(.caption2).foregroundStyle(.secondary)
                        if model.measurementIsStale(for: item, at: now) {
                            Text("This size measurement is older than the scanner cache window. Preview still revalidates filesystem identity before it can authorize cleanup.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if interactive {
                Button(isSelected ? "Deselect" : "Select") { model.toggle(item) }
                    .disabled(model.isWorking)
            }
            if model.canReveal(item) {
                Button("Reveal in Finder") { model.reveal(item) }
            }
            Button("Copy Path") { model.copyPath(item) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(isSelected ? "Selected. " : "")\(item.risk.rawValue). \(item.sizeBytes > 0 ? item.formattedSize : "Not measured"). \(model.measurementAgeText(for: item, at: now)).")
    }

    private var isSelected: Bool {
        model.items.first(where: { $0.id == item.id })?.isSelected ?? item.isSelected
    }

    private var measurementIcon: String {
        item.measurementSource == .fresh ? "sparkles" : item.measurementSource == .cache ? "clock.arrow.circlepath" : "questionmark.circle"
    }
}

struct ResultRow: View {
    @EnvironmentObject private var model: AppModel
    let result: CleanupResult
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                StatusPill(text: result.status, systemImage: result.status == "Moved to Trash" ? "trash" : result.status == "Failed" ? "exclamationmark.triangle" : "info.circle")
                Spacer()
                if model.canRevealResult(result) {
                    Button("Reveal") { model.revealResult(result) }.buttonStyle(.bordered).controlSize(.small)
                }
                FeedbackButton(title: "Copy Result", successTitle: "Copied", systemImage: "doc.on.doc") { model.copyResult(result) }
            }
            Text(result.path).font(.caption.monospaced()).textSelection(.enabled)
            Text(result.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(.vertical, 6)
    }
}

struct FeedbackButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var success = false
    @State private var feedbackResetTask: Task<Void, Never>?
    let title: String
    let successTitle: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button {
            feedbackResetTask?.cancel()
            action()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { success = true }
            feedbackResetTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 1_200_000_000)
                } catch {
                    return
                }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { success = false }
            }
        } label: {
            Label(success ? successTitle : title, systemImage: success ? "checkmark" : systemImage)
        }
        .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 30)
        .onDisappear { feedbackResetTask?.cancel() }
    }
}
