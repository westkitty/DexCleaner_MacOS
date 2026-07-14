import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public struct ShellResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var cancelled: Bool
    public var durationSeconds: TimeInterval

    public init(status: Int32, stdout: String, stderr: String, timedOut: Bool, cancelled: Bool = false, durationSeconds: TimeInterval) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.durationSeconds = durationSeconds
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock(); data.append(newData); lock.unlock()
    }

    func string() -> String {
        lock.lock(); let snapshot = data; lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

public enum Shell {
    public static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 30) -> ShellResult {
        let started = Date()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stdoutBuffer.append(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrBuffer.append(data) }
        }

        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false, durationSeconds: Date().timeIntervalSince(started))
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        while process.isRunning && Date() < deadline {
            if currentTaskIsCancelled {
                cancelled = true
                terminate(process)
                break
            }
            Thread.sleep(forTimeInterval: 0.03)
        }

        if process.isRunning && !cancelled {
            timedOut = true
            terminate(process)
        }

        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        return ShellResult(
            status: process.terminationStatus,
            stdout: stdoutBuffer.string(),
            stderr: stderrBuffer.string(),
            timedOut: timedOut,
            cancelled: cancelled,
            durationSeconds: Date().timeIntervalSince(started)
        )
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = pid_t(process.processIdentifier)
        _ = kill(pid, SIGTERM)
        let graceDeadline = Date().addingTimeInterval(0.15)
        while process.isRunning && Date() < graceDeadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { _ = kill(pid, SIGKILL) }
    }

    private static var currentTaskIsCancelled: Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }
}
