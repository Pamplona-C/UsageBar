import Foundation

enum CodexUsageError: Error, Equatable {
    case notFound
    case notLoggedIn
    case unsupportedLogin
    case timedOut
    case unsupportedVersion
    case noLimits
    case failed(String)

    var offersLogin: Bool { self == .notLoggedIn || self == .unsupportedLogin }

    var message: String {
        switch self {
        case .notFound: return "Codex não encontrado. Instale o Codex CLI para conectar sua conta."
        case .notLoggedIn: return "Entre com sua conta do ChatGPT para acompanhar os limites do Codex."
        case .unsupportedLogin: return "Os limites do plano precisam de login com ChatGPT. O Codex está usando outro tipo de autenticação."
        case .timedOut: return "O Codex demorou demais para responder. Tente atualizar novamente."
        case .unsupportedVersion: return "Esta versão do Codex não oferece a consulta de limites. Atualize o Codex CLI."
        case .noLimits: return "O Codex não devolveu limites disponíveis para esta conta."
        case .failed(let message): return message
        }
    }
}

/// Duração vem do servidor: não assume que primary e secondary são sempre 5h e semana.
struct CodexUsageWindow: Codable, Equatable {
    var usedPercent: Double?
    var windowDurationMins: Int?
    var resetsAt: Double?

    init(usedPercent: Double?, windowDurationMins: Int? = nil, resetsAt: Double? = nil) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey { case usedPercent, windowDurationMins, resetsAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = UsageValidation.percentage(container.lenient(Double.self, forKey: .usedPercent))
        windowDurationMins = container.lenient(Int.self, forKey: .windowDurationMins).flatMap { $0 > 0 ? $0 : nil }
        resetsAt = UsageValidation.resetDate(container.lenient(Double.self, forKey: .resetsAt))?.timeIntervalSince1970
    }

    var window: UsageWindow {
        UsageWindow(usedPercentage: usedPercent, resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)))
    }

    func title(fallback: String) -> String {
        guard let minutes = windowDurationMins else { return fallback }
        if minutes == 10_080 { return "Semana" }
        if minutes.isMultiple(of: 1440) { return "\(minutes / 1440) \(minutes == 1440 ? "dia" : "dias")" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60) \(minutes == 60 ? "hora" : "horas")" }
        return "\(minutes) min"
    }
}

struct CodexUsageReport: Codable, Equatable {
    var primary: CodexUsageWindow?
    var secondary: CodexUsageWindow?
    var planType: String?

    static func parse(_ data: Data) throws -> CodexUsageReport {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw CodexUsageError.noLimits
        }
        // O mapa pode incluir cotas de outros modelos. Nunca usa uma cota arbitrária como a do Codex.
        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits.flatMap {
            $0.limitId == nil || $0.limitId == "codex" ? $0 : nil
        }
        let primary = snapshot?.primary.flatMap { $0.usedPercent != nil ? $0 : nil }
        let secondary = snapshot?.secondary.flatMap { $0.usedPercent != nil ? $0 : nil }
        guard primary != nil || secondary != nil else { throw CodexUsageError.noLimits }
        return CodexUsageReport(primary: primary, secondary: secondary, planType: snapshot?.planType)
    }

    private struct Response: Decodable {
        var rateLimits: Snapshot?
        var rateLimitsByLimitId: [String: Snapshot]?
        enum CodingKeys: String, CodingKey { case rateLimits, rateLimitsByLimitId }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rateLimits = container.lenient(Snapshot.self, forKey: .rateLimits)
            rateLimitsByLimitId = container.lenient([String: Snapshot].self, forKey: .rateLimitsByLimitId)
        }
    }

    private struct Snapshot: Decodable {
        var limitId: String?
        var planType: String?
        var primary: CodexUsageWindow?
        var secondary: CodexUsageWindow?
        enum CodingKeys: String, CodingKey { case limitId, planType, primary, secondary }
        init(from decoder: Decoder) throws {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            limitId = container.lenient(String.self, forKey: .limitId)
            planType = container.lenient(String.self, forKey: .planType)
            primary = container.lenient(CodexUsageWindow.self, forKey: .primary)
            secondary = container.lenient(CodexUsageWindow.self, forKey: .secondary)
        }
    }
}
