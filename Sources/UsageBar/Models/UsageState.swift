import Foundation

/// Melhor leitura conhecida dos limites, combinando payloads de várias sessões do Claude Code.
///
/// Uma sessão parada repete o valor da última resposta que recebeu, então a última gravação de
/// `state.json` nem sempre é a mais recente em dados. Regra completa em `docs/payload.md`.
struct UsageState: Codable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    /// Quando chegou o último payload que não era mais antigo que o estado atual.
    var updatedAt: Date?

    /// Diferença de `resets_at` abaixo da qual dois payloads são considerados da mesma janela.
    static let sameWindowTolerance: TimeInterval = 5 * 60
    /// A partir de quanto tempo sem payload novo os dados são exibidos como antigos.
    static let staleAfter: TimeInterval = 60 * 60

    var hasData: Bool { fiveHour != nil || sevenDay != nil }

    func isStale(at now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) > Self.staleAfter
    }

    mutating func absorb(_ snapshot: UsageSnapshot, receivedAt: Date) {
        guard let limits = snapshot.rateLimits else { return }
        let results = [
            Self.merge(limits.fiveHour, into: &fiveHour),
            Self.merge(limits.sevenDay, into: &sevenDay),
        ].compactMap { $0 }
        // Uma janela mais antiga denuncia uma sessão parada, mesmo que a outra janela coincida.
        if !results.isEmpty && !results.contains(.older) {
            updatedAt = max(updatedAt ?? receivedAt, receivedAt)
        }
    }

    /// Aplica `incoming` sobre `current` quando for mais recente; `nil` se a janela não veio no payload.
    private static func merge(_ incoming: UsageWindow?, into current: inout UsageWindow?) -> Freshness? {
        guard let incoming else { return nil }
        let freshness = compare(incoming, to: current)
        if freshness == .newer {
            current = incoming
        }
        return freshness
    }

    enum Freshness { case newer, same, older }

    static func compare(_ incoming: UsageWindow, to current: UsageWindow?) -> Freshness {
        guard let current else { return .newer }
        guard let incomingReset = incoming.resetsAt, let currentReset = current.resetsAt else {
            return .newer
        }
        let delta = incomingReset.timeIntervalSince(currentReset)
        if delta > sameWindowTolerance { return .newer }
        if delta < -sameWindowTolerance { return .older }

        // Mesma janela: o uso só sobe, então o maior percentual é o mais recente.
        switch (incoming.usedPercentage, current.usedPercentage) {
        case let (new?, old?):
            return new > old ? .newer : (new == old ? .same : .older)
        case (_?, nil):
            return .newer
        case (nil, _):
            return .older
        }
    }
}

extension UsageWindow {
    /// Percentual a exibir agora: uma janela cujo reset já passou está zerada.
    func percentage(at now: Date) -> Double? {
        if let resetsAt, resetsAt <= now { return 0 }
        return usedPercentage
    }

    func hasReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }
}

/// Faixa de cor do consumo: verde < 60%, amarelo 60–85%, vermelho > 85%.
enum UsageLevel: Equatable {
    case normal, warning, critical

    /// Usa o percentual arredondado, o mesmo que aparece na tela.
    init(percentage: Double) {
        let shown = percentage.rounded()
        if shown > 85 {
            self = .critical
        } else if shown >= 60 {
            self = .warning
        } else {
            self = .normal
        }
    }
}
