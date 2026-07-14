import Foundation

public struct PreviewAuthorization: Hashable, Sendable {
    public static let maximumPlanAge: TimeInterval = 15 * 60

    public private(set) var selectionSignature: String?
    public private(set) var planID: UUID?

    public init(selectionSignature: String? = nil, planID: UUID? = nil) {
        self.selectionSignature = selectionSignature
        self.planID = planID
    }

    public mutating func authorize(items: [ScanItem], plan: CleanupPlan) {
        selectionSignature = Self.signature(for: items.filter { $0.isSelected })
        planID = plan.id
    }

    public mutating func invalidate() {
        selectionSignature = nil
        planID = nil
    }

    public func isValid(items: [ScanItem], plan: CleanupPlan?, now: Date = Date()) -> Bool {
        guard let plan, plan.id == planID else { return false }
        let age = now.timeIntervalSince(plan.createdAt)
        guard age >= 0, age <= Self.maximumPlanAge else { return false }
        return Self.signature(for: items.filter { $0.isSelected }) == selectionSignature
    }

    public static func signature(for items: [ScanItem]) -> String {
        items.map {
            [
                $0.id.uuidString,
                $0.manifestID ?? "none",
                $0.path,
                String($0.sizeBytes),
                $0.risk.rawValue,
                $0.action.rawValue
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: "\n")
    }
}
