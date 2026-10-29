import Foundation

/// Tokens de uma resposta ou de uma soma de respostas.
struct TokenCount: Codable, Equatable {
    /// Entrada + gravação de cache + leitura de cache + saída.
    var total: Int
    /// Saída, que já inclui o raciocínio.
    var written: Int

    static let zero = TokenCount(total: 0, written: 0)

    static func + (lhs: TokenCount, rhs: TokenCount) -> TokenCount {
        TokenCount(total: lhs.total + rhs.total, written: lhs.written + rhs.written)
    }
}

/// Uma resposta do Claude Code com tokens, lida do histórico da sessão.
struct TokenEvent: Equatable {
    /// `message.id|requestId`: a mesma resposta aparece em várias linhas, uma por bloco de conteúdo.
    let key: String
    let date: Date
    let count: TokenCount
}

/// Lê uma linha dos históricos em `~/.claude/projects/`. Formato e regras em `docs/transcripts.md`.
enum TranscriptLine {
    /// `nil` para linhas sem tokens, mensagens locais (`<synthetic>`) e linhas ilegíveis.
    static func parse(_ line: Data) -> TokenEvent? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: line),
              let message = entry.message, let usage = message.usage, let id = message.id,
              message.model != "<synthetic>",
              let timestamp = entry.timestamp else { return nil }
        // Sem a fração: no macOS 14 e 15, `.iso8601` rejeita a data se ela tiver fração.
        let text = timestamp.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        guard let date = try? Date(text, strategy: .iso8601) else { return nil }
        let written = usage.output ?? 0
        let total = (usage.input ?? 0) + (usage.cacheCreation ?? 0) + (usage.cacheRead ?? 0) + written
        return TokenEvent(key: "\(id)|\(entry.requestId ?? "")", date: date,
                          count: TokenCount(total: total, written: written))
    }
}

private struct Entry: Decodable {
    var timestamp: String?
    var requestId: String?
    var message: Message?

    enum CodingKeys: String, CodingKey { case timestamp, requestId, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = container.lenient(String.self, forKey: .timestamp)
        requestId = container.lenient(String.self, forKey: .requestId)
        message = container.lenient(Message.self, forKey: .message)
    }
}

private struct Message: Decodable {
    var id: String?
    var model: String?
    var usage: Usage?

    enum CodingKeys: String, CodingKey { case id, model, usage }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, forKey: .id)
        model = container.lenient(String.self, forKey: .model)
        usage = container.lenient(Usage.self, forKey: .usage)
    }
}

private struct Usage: Decodable {
    var input: Int?
    var cacheCreation: Int?
    var cacheRead: Int?
    var output: Int?

    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cacheCreation = "cache_creation_input_tokens"
        case cacheRead = "cache_read_input_tokens"
        case output = "output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = container.lenient(Int.self, forKey: .input)
        cacheCreation = container.lenient(Int.self, forKey: .cacheCreation)
        cacheRead = container.lenient(Int.self, forKey: .cacheRead)
        output = container.lenient(Int.self, forKey: .output)
    }
}
