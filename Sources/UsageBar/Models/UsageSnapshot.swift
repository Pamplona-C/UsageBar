import Foundation

/// O que o app extrai do JSON que o Claude Code envia à statusline. Mapeamento em `docs/payload.md`.
///
/// Tudo é opcional e chaves desconhecidas são ignoradas. Um campo com tipo inesperado vira `nil`
/// em vez de invalidar o payload inteiro.
struct UsageSnapshot: Codable, Equatable {
    var rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }

    init(rateLimits: RateLimits? = nil) {
        self.rateLimits = rateLimits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = container.lenient(RateLimits.self, forKey: .rateLimits)
    }
}

struct RateLimits: Codable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(fiveHour: UsageWindow? = nil, sevenDay: UsageWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = container.lenient(UsageWindow.self, forKey: .fiveHour)
        sevenDay = container.lenient(UsageWindow.self, forKey: .sevenDay)
    }
}

/// Uma janela de rate limit: percentual de 0 a 100 e reset em epoch Unix (segundos).
struct UsageWindow: Codable, Equatable {
    var usedPercentage: Double?
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(usedPercentage: Double? = nil, resetsAt: Date? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    // `resets_at` é decodificado à mão para não depender da `dateDecodingStrategy` de quem decodifica.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = container.lenient(Double.self, forKey: .usedPercentage)
        resetsAt = container.lenient(Double.self, forKey: .resetsAt).map(Date.init(timeIntervalSince1970:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(usedPercentage, forKey: .usedPercentage)
        try container.encodeIfPresent(resetsAt?.timeIntervalSince1970, forKey: .resetsAt)
    }
}

extension KeyedDecodingContainer {
    /// Decodifica um campo opcional; ausente, `null` ou com tipo inesperado vira `nil`.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
