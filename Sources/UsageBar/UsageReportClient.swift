import Foundation
import os

/// Consulta o uso real no servidor rodando o `/usage` do próprio Claude Code.
///
/// O app não lê token nem chama a API: quem fala com o servidor é o Claude Code, com o login dele. A consulta
/// não chama o modelo e não gasta limite. Detalhes em `docs/usage-report.md`.
enum UsageReportClient {
    /// `--safe-mode` não carrega hooks, plugins nem a statusline; `--no-session-persistence` não grava sessão.
    static let arguments = [
        "-p", "--safe-mode", "--no-session-persistence",
        "--output-format", "stream-json", "--verbose", "/usage",
    ]
    static let timeout: TimeInterval = 30

    /// Onde os instaladores colocam o `claude`. Um app aberto pelo Finder não herda o PATH do terminal.
    static var candidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".npm-global/bin/claude"),
            home.appendingPathComponent(".bun/bin/claude"),
        ]
    }

    static func fetch() async -> Result<RateLimits, UsageReportError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let executable = locateClaude() else {
                    continuation.resume(returning: .failure(.claudeNotFound))
                    return
                }
                continuation.resume(returning: run(executable))
            }
        }
    }

    static func locateClaude(candidates: [URL] = candidates) -> URL? {
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        // Instalação fora dos lugares comuns: pergunta ao shell de login, que carrega o PATH do usuário.
        let output = execute(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v claude"], timeout: 5)
        guard case .exited(0, let stdout, _) = output else { return nil }
        let path = String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path)
            ? URL(fileURLWithPath: path) : nil
    }

    static func run(_ executable: URL, timeout: TimeInterval = timeout) -> Result<RateLimits, UsageReportError> {
        switch execute(executable, arguments, timeout: timeout) {
        case .launchFailed(let reason):
            return .failure(.launchFailed(reason))
        case .timedOut:
            return .failure(.timedOut)
        case .exited(let status, let stdout, let stderr):
            do {
                return .success(try UsageReport.parse(stdout))
            } catch let error as UsageReportError {
                if status != 0, case .noUsageReport = error {
                    return .failure(.failed(failureMessage(status: status, stderr: stderr)))
                }
                return .failure(error)
            } catch {
                return .failure(.noUsageReport)
            }
        }
    }

    /// Última linha do stderr, que costuma ser a mensagem de erro, ou o código de saída.
    private static func failureMessage(status: Int32, stderr: Data) -> String {
        let lastLine = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last
            .map { String($0.prefix(200)).trimmingCharacters(in: .whitespaces) }
        if let lastLine, !lastLine.isEmpty { return lastLine }
        return "O Claude Code terminou com o código \(status)."
    }

    // MARK: - Processo

    private enum Execution {
        case launchFailed(String)
        case timedOut
        case exited(Int32, stdout: Data, stderr: Data)
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    private static func execute(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> Execution {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .launchFailed(error.localizedDescription)
        }

        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.withLock { $0 = true }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        // O stderr é lido em paralelo para um pipe cheio não travar o processo.
        let errors = Buffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errors.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        deadline.cancel()

        if timedOut.withLock({ $0 }) { return .timedOut }
        return .exited(process.terminationStatus, stdout: output, stderr: errors.data)
    }
}
