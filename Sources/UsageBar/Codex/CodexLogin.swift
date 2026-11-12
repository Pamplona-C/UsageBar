import AppKit

enum CodexLogin {
    static func script(codex: URL) -> String {
        let quoted = "'" + codex.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let bin = "'" + codex.deletingLastPathComponent().path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        return """
        #!/bin/zsh
        clear
        echo "Login do Codex para o UsageBar"
        echo
        export PATH=\(bin):"$PATH"
        if \(quoted) login; then
          echo
          echo "Login concluído. Volte ao UsageBar para ver seus limites."
        else
          echo
          echo "O login não foi concluído. Tente conectar novamente no UsageBar."
        fi
        echo "Pode fechar esta janela."

        """
    }

    static func open() async -> CodexUsageError? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let codex = CodexUsageClient.locateCodex() else {
                    continuation.resume(returning: .notFound)
                    return
                }
                // Diretório exclusivo evita colisão entre instâncias; sem tokens no script.
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBar-Codex-\(UUID().uuidString)")
                let url = directory.appendingPathComponent("Conectar Codex.command")
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    try script(codex: codex).write(to: url, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                } catch {
                    continuation.resume(returning: .failed(error.localizedDescription))
                    return
                }
                DispatchQueue.main.async {
                    let opened = NSWorkspace.shared.open(url)
                    continuation.resume(returning: opened ? nil : .failed("Não foi possível abrir o Terminal para conectar o Codex."))
                }
            }
        }
    }
}
