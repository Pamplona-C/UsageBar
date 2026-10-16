import Foundation

/// Por que uma consulta ao `/usage` não trouxe os limites.
enum UsageReportError: Error, Equatable {
    case claudeNotFound
    case launchFailed(String)
    case timedOut
    case failed(String)
    /// Nenhuma mensagem com `usage_report`: login sem assinatura claude.ai, versão antiga ou formato novo.
    case noUsageReport
    /// `rate_limits` nulo: o Claude Code não conseguiu ler o uso do plano.
    case noLimits
    /// Os limites vieram, mas sem as linhas `session` e `weekly_all`.
    case noKnownLimits

    var message: String {
        switch self {
        case .claudeNotFound:
            return "Claude Code não encontrado."
        case .launchFailed(let reason):
            return "Não foi possível abrir o Claude Code: \(reason)"
        case .timedOut:
            return "O Claude Code demorou demais para responder."
        case .failed(let reason):
            return reason
        case .noUsageReport:
            return "O Claude Code não devolveu o relatório de uso."
        case .noLimits:
            return "O Claude Code não conseguiu ler os limites do plano."
        case .noKnownLimits:
            return "O relatório de uso veio sem os limites de 5h e semanal."
        }
    }
}

/// Lê a saída `stream-json` de `claude -p "/usage"`. Mapeamento em `docs/usage-report.md`.
///
/// O relatório estruturado vem em `usage_report` na mensagem `assistant`. Linhas que não são JSON e campos
/// desconhecidos são ignorados; uma linha de limite com tipo inesperado é descartada sozinha.
enum UsageReport {
    static func parse(_ output: Data) throws -> RateLimits {
        let lines = output.split(separator: UInt8(ascii: "\n"))
            .compactMap { try? JSONDecoder().decode(StreamLine.self, from: Data($0)) }

        guard let report = lines.lazy.compactMap(\.usageReport).first else {
            if let failure = lines.first(where: { $0.isError == true }) {
                throw UsageReportError.failed(failure.result ?? "O Claude Code devolveu um erro.")
            }
            throw UsageReportError.noUsageReport
        }
        guard let rows = report.rateLimits?.limits else {
            throw UsageReportError.noLimits
        }
        let limits = RateLimits(fiveHour: window(kind: "session", in: rows),
                                sevenDay: window(kind: "weekly_all", in: rows))
        guard limits.fiveHour != nil || limits.sevenDay != nil else {
            throw UsageReportError.noKnownLimits
        }
        return limits
    }

    /// A documentação manda classificar as linhas por `kind`, nunca pelo texto exibido.
    private static func window(kind: String, in rows: [LimitRow]) -> UsageWindow? {
        guard let row = rows.first(where: { $0.kind == kind && $0.percent != nil }) else { return nil }
        return UsageWindow(usedPercentage: row.percent, resetsAt: row.resetsAt)
    }
}

private struct StreamLine: Decodable {
    var usageReport: Report?
    var isError: Bool?
    var result: String?

    enum CodingKeys: String, CodingKey {
        case usageReport = "usage_report"
        case isError = "is_error"
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usageReport = container.lenient(Report.self, forKey: .usageReport)
        isError = container.lenient(Bool.self, forKey: .isError)
        result = container.lenient(String.self, forKey: .result)
    }
}

private struct Report: Decodable {
    var rateLimits: Limits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = container.lenient(Limits.self, forKey: .rateLimits)
    }
}

private struct Limits: Decodable {
    var limits: [LimitRow]?

    enum CodingKeys: String, CodingKey {
        case limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limits = container.lenient([LimitRow].self, forKey: .limits)
    }
}

private struct LimitRow: Decodable {
    var kind: String?
    var percent: Double?
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case kind, percent
        case resetsAt = "resets_at"
    }

    /// Nunca falha: uma linha estranha vira uma linha vazia, que é ignorada, sem derrubar as outras.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        kind = container.lenient(String.self, forKey: .kind)
        percent = container.lenient(Double.self, forKey: .percent)
        // ISO 8601 com microssegundos, ex.: "2026-10-16T14:20:00.138122+00:00". Arredonda para segundos, como
        // na statusline, para o cache (epoch em segundos) devolver exatamente o mesmo valor.
        resetsAt = container.lenient(String.self, forKey: .resetsAt)
            .flatMap { try? Date($0, strategy: .iso8601) }
            .map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded()) }
    }
}
