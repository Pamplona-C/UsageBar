import Foundation

/// Tokens somados por minuto. Por minuto porque a janela de 5h começa em qualquer minuto e a meia-noite local pode
/// cair em qualquer deslocamento de fuso.
struct TokenBuckets: Equatable {
    /// Minuto em epoch → tokens daquele minuto.
    private var minutes: [Int: TokenCount] = [:]
    /// Chave de cada resposta já contada → minuto dela, para o `prune` também limpar a deduplicação.
    private var seen: [String: Int] = [:]
    /// Eventos anteriores a este minuto são descartados.
    private var firstMinute: Int?

    var isEmpty: Bool { minutes.isEmpty }

    mutating func add(_ event: TokenEvent) {
        let minute = Self.minute(of: event.date)
        if let firstMinute, minute < firstMinute { return }
        guard seen[event.key] == nil else { return }
        seen[event.key] = minute
        minutes[minute, default: .zero] = minutes[minute, default: .zero] + event.count
    }

    /// Soma dos minutos que começam em `[from, to)`.
    func sum(from: Date, to: Date) -> TokenCount {
        let lower = Self.minute(rounding: from), upper = Self.minute(rounding: to)
        return minutes.reduce(into: .zero) { result, entry in
            if entry.key >= lower && entry.key < upper { result = result + entry.value }
        }
    }

    mutating func prune(before date: Date) {
        let limit = Self.minute(rounding: date)
        firstMinute = max(firstMinute ?? limit, limit)
        minutes = minutes.filter { $0.key >= limit }
        seen = seen.filter { $0.value >= limit }
    }

    func hasSeen(_ key: String) -> Bool { seen[key] != nil }

    /// Minuto que contém `date`.
    private static func minute(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    /// Primeiro minuto que começa em `date` ou depois.
    private static func minute(rounding date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.up))
    }
}
