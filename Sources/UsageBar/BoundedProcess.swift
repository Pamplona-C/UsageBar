import Foundation
import os

/// Executa CLIs com limite de tempo e de saída, inclusive quando um filho mantém os pipes abertos.
enum BoundedProcess {
    enum Output {
        case launchFailed(String)
        case timedOut
        case outputTooLarge
        case exited(Int32, stdout: Data, stderr: Data)
    }

    private struct State {
        var stdout = Data()
        var stderr = Data()
        var stdoutEnded = false
        var stderrEnded = false
        var terminated = false
        var oversized = false
    }

    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval,
                    outputLimit: Int = 4 * 1024 * 1024) -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let state = OSAllocatedUnfairLock(initialState: State())
        let changed = DispatchSemaphore(value: 0)
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            state.withLock { $0.terminated = true }
            changed.signal()
            exited.signal()
        }

        func observe(_ pipe: Pipe, isError: Bool) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                state.withLock { value in
                    if data.isEmpty {
                        if isError { value.stderrEnded = true } else { value.stdoutEnded = true }
                    } else if data.count > outputLimit - value.stdout.count - value.stderr.count {
                        value.oversized = true
                    } else if !value.oversized {
                        if isError { value.stderr.append(data) } else { value.stdout.append(data) }
                    }
                }
                changed.signal()
            }
        }
        observe(stdout, isError: false)
        observe(stderr, isError: true)
        do { try process.run() } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return .launchFailed(error.localizedDescription)
        }
        defer {
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 0.3) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = exited.wait(timeout: .now() + 0.3)
                }
            }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
        }
        let deadline = DispatchTime.now() + timeout
        while true {
            let snapshot = state.withLock { $0 }
            if snapshot.oversized { return .outputTooLarge }
            if snapshot.terminated && snapshot.stdoutEnded && snapshot.stderrEnded {
                return .exited(process.terminationStatus, stdout: snapshot.stdout, stderr: snapshot.stderr)
            }
            if DispatchTime.now() >= deadline || changed.wait(timeout: deadline) == .timedOut { return .timedOut }
        }
    }
}
