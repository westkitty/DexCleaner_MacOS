import Foundation

public final class OperationCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    public init() {}

    public func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !active else { return false }
        active = true
        return true
    }

    public func end() {
        lock.lock()
        active = false
        lock.unlock()
    }

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }
}
