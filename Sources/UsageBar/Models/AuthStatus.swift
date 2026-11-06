import Foundation

/// Saída de `claude auth status --json`, comando documentado do Claude Code. Formato em `docs/usage-report.md`.
struct AuthStatus: Equatable {
    var loggedIn: Bool
    /// `claude.ai` para login com assinatura; `none` sem login.
    var authMethod: String?

    /// `nil` quando a saída não é JSON ou não diz se está logado.
    static func parse(_ data: Data) -> AuthStatus? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), let loggedIn = raw.loggedIn else { return nil }
        return AuthStatus(loggedIn: loggedIn, authMethod: raw.authMethod)
    }

    private struct Raw: Decodable {
        var loggedIn: Bool?
        var authMethod: String?

        enum CodingKeys: String, CodingKey { case loggedIn, authMethod }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            loggedIn = container.lenient(Bool.self, forKey: .loggedIn)
            authMethod = container.lenient(String.self, forKey: .authMethod)
        }
    }
}
