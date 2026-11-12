import Foundation
import os

/// Usa apenas initialize, account/read e account/rateLimits/read do protocolo documentado.
/// Não inicia threads, não chama modelos e não lê arquivos de credenciais.
enum CodexUsageClient {
    static let timeout: TimeInterval = 30

    static func fetch() async -> Result<CodexUsageReport, CodexUsageError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let executable = locateCodex() else {
                    continuation.resume(returning: .failure(.notFound))
                    return
                }
                continuation.resume(returning: run(executable))
            }
        }
    }

    static func locateCodex(candidates: [URL]? = nil) -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var locations = candidates ?? [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".bun/bin/codex"),
            home.appendingPathComponent(".cargo/bin/codex"),
        ]
        if candidates == nil {
            let nvm = home.appendingPathComponent(".nvm/versions/node")
            let versions = (try? fm.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? []
            locations += versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/codex") }
            locations += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        }
        if let found = locations.first(where: { fm.isExecutableFile(atPath: $0.path) }) { return found }
        // Mesmo fallback do Claude: instalações personalizadas definidas pelo shell de login.
        guard candidates == nil else { return nil }
        guard case .exited(0, let output, _) = BoundedProcess.run(
            URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v codex"], timeout: 5, outputLimit: 64 * 1024)
        else { return nil }
        let path = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), fm.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func run(_ executable: URL, timeout: TimeInterval = timeout) -> Result<CodexUsageReport, CodexUsageError> {
        do {
            let rpc = try CodexRPC(executable: executable, timeout: timeout)
            defer { rpc.close() }
            _ = try rpc.request(id: 0, method: "initialize", params: [
                "clientInfo": ["name": "usagebar", "title": "UsageBar", "version": "0.1.0"],
            ])
            try rpc.notify(method: "initialized")
            let account = try rpc.request(id: 1, method: "account/read", params: ["refreshToken": false])
            guard let info = account["account"] as? [String: Any] else { return .failure(.notLoggedIn) }
            guard info["type"] as? String == "chatgpt" else { return .failure(.unsupportedLogin) }
            let limits = try rpc.request(id: 2, method: "account/rateLimits/read")
            return .success(try CodexUsageReport.parse(JSONSerialization.data(withJSONObject: limits)))
        } catch let error as CodexUsageError {
            return .failure(error)
        } catch {
            return .failure(.failed("Não foi possível consultar o Codex: \(error.localizedDescription)"))
        }
    }
}

/// Uma conexão curta de JSON-RPC por stdin/stdout. A espera tem prazo mesmo que o processo pare de responder.
private final class CodexRPC {
    private struct Incoming {
        var buffer = Data()
        var responses: [Int: [String: Any]] = [:]
        var ended = false
        var invalid = false
    }
    private let incoming = OSAllocatedUnfairLock(initialState: Incoming())
    private let available = DispatchSemaphore(value: 0)
    private let exited = DispatchSemaphore(value: 0)
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: DispatchTime

    init(executable: URL, timeout: TimeInterval) throws {
        deadline = .now() + timeout
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        // O pacote npm usa /usr/bin/env node. O Finder não herda o PATH do nvm.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let incoming = self.incoming, available = self.available, exited = self.exited
        process.terminationHandler = { _ in
            available.signal()
            exited.signal()
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            incoming.withLock { state in
                if data.isEmpty { state.ended = true }
                state.buffer.append(data)
                // Limita também saídas de versões incompatíveis que não mandam linhas JSON.
                if state.buffer.count > 4 * 1024 * 1024 { state.invalid = true; state.buffer.removeAll() }
                while let newline = state.buffer.firstIndex(of: 10) {
                    let line = Data(state.buffer[..<newline])
                    state.buffer.removeSubrange(...newline)
                    guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                          let id = message["id"] as? Int, (0...2).contains(id) else { continue }
                    state.responses[id] = message
                }
            }
            available.signal()
        }
        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CodexUsageError.failed("Não foi possível abrir o Codex: \(error.localizedDescription)")
        }
    }

    func notify(method: String) throws { try send(["method": method, "params": [:]]) }

    func request(id: Int, method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try send(request)
        while true {
            if DispatchTime.now() >= deadline { throw CodexUsageError.timedOut }
            let (response, ended, invalid) = incoming.withLock {
                ($0.responses.removeValue(forKey: id), $0.ended, $0.invalid)
            }
            if let response {
                if let error = response["error"] as? [String: Any] {
                    if error["code"] as? Int == -32601 { throw CodexUsageError.unsupportedVersion }
                    throw CodexUsageError.failed(String((error["message"] as? String ?? "O Codex não conseguiu consultar os limites.").prefix(300)))
                }
                guard let result = response["result"] as? [String: Any] else { throw CodexUsageError.noLimits }
                return result
            }
            if invalid { throw CodexUsageError.failed("O Codex devolveu uma resposta em formato inesperado.") }
            if ended { throw CodexUsageError.failed("O Codex encerrou a consulta antes de responder.") }
            if available.wait(timeout: deadline) == .timedOut { throw CodexUsageError.timedOut }
        }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning, exited.wait(timeout: .now() + 0.3) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.3) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.3)
            }
        }
        output.fileHandleForReading.readabilityHandler = nil
        try? output.fileHandleForReading.close()
    }
}
