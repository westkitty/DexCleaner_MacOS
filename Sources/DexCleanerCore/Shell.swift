import Foundation

public struct ShellResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var durationSeconds: TimeInterval

    public init(status: Int32, stdout: String, stderr: String, timedOut: Bool, durationSeconds: TimeInterval) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.durationSeconds = durationSeconds
    }
}

public enum Shell {
    public static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 30) -> ShellResult {
        let started = Date()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            stdoutData.append(data)
            lock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            stderrData.append(data)
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false, durationSeconds: Date().timeIntervalSince(started))
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.03)
        }

        if process.isRunning {
            timedOut = true
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning {
                process.interrupt()
            }
        }

        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        stdoutData.append(remainingOut)
        stderrData.append(remainingErr)
        let out = String(data: stdoutData, encoding: .utf8) ?? ""
        let err = String(data: stderrData, encoding: .utf8) ?? ""
        lock.unlock()

        return ShellResult(status: process.terminationStatus, stdout: out, stderr: err, timedOut: timedOut, durationSeconds: Date().timeIntervalSince(started))
    }
}
