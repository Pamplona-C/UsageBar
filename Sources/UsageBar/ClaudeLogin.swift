import AppKit

/// Abre o Terminal rodando `claude auth login`, que abre o navegador para entrar na conta do claude.ai.
///
/// O app não toca na credencial: quem faz o login e guarda o resultado é o próprio Claude Code.
enum ClaudeLogin {
    /// Script `.command`: o macOS abre com o app de terminal padrão, sem pedir permissão de automação.
    static func script(claude: URL) -> String {
        let quoted = "'" + claude.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        return """
        #!/bin/zsh
        clear
        echo "Login do Claude Code para o UsageBar"
        echo
        \(quoted) auth login
        echo
        echo "Pronto. Volte ao UsageBar e clique em atualizar. Pode fechar esta janela."

        """
    }

    /// `nil` quando o Terminal abriu.
    static func open() async -> UsageReportError? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let claude = UsageReportClient.locateClaude() else {
                    continuation.resume(returning: .claudeNotFound)
                    return
                }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBar-Claude-\(UUID().uuidString)")
                let url = directory.appendingPathComponent("Conectar Claude.command")
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    try script(claude: claude).write(to: url, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                } catch {
                    continuation.resume(returning: .launchFailed(error.localizedDescription))
                    return
                }
                DispatchQueue.main.async {
                    let opened = NSWorkspace.shared.open(url)
                    continuation.resume(returning: opened ? nil : .launchFailed("o Terminal não abriu."))
                }
            }
        }
    }
}
