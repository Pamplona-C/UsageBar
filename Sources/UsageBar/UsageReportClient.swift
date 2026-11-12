import Foundation

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
    /// Diz se o Claude Code está logado e com qual método; usado quando o `/usage` vem sem relatório.
    static let authStatusArguments = ["auth", "status", "--json"]
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
        case .outputTooLarge:
            return .failure(.failed("O Claude Code devolveu uma saída maior que o limite de segurança."))
        case .exited(let status, let stdout, let stderr):
            do {
                return .success(try UsageReport.parse(stdout))
            } catch let error as UsageReportError {
                if case .noUsageReport = error {
                    if status != 0 {
                        return .failure(.failed(failureMessage(status: status, stderr: stderr)))
                    }
                    // Sem login, o `/usage` termina sem erro e só com o texto de custo local.
                    return .failure(.diagnosingMissingReport(authStatus(executable, timeout: timeout)))
                }
                return .failure(error)
            } catch {
                return .failure(.noUsageReport)
            }
        }
    }

    private static func authStatus(_ executable: URL, timeout: TimeInterval) -> AuthStatus? {
        guard case .exited(0, let stdout, _) = execute(executable, authStatusArguments, timeout: timeout) else {
            return nil
        }
        return AuthStatus.parse(stdout)
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

    private static func execute(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> BoundedProcess.Output {
        BoundedProcess.run(executable, arguments, timeout: timeout)
    }
}
