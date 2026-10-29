import Foundation

/// Modo do card de tokens.
enum TokenRange: String, CaseIterable {
    case fiveHour, week
}

struct TokenBar: Equatable, Identifiable {
    let start: Date
    let end: Date
    let count: TokenCount
    let isFuture: Bool
    let isCurrent: Bool

    var id: Date { start }
}

struct TokenChartData: Equatable {
    let bars: [TokenBar]
    /// Soma de `periodStart` até agora.
    let total: TokenCount
    let periodStart: Date
    /// Modo 5h sem janela atual conhecida: as últimas 5 horas corridas, terminando agora.
    let isRolling: Bool
}

/// Barras dos modos 5h e Semana, somadas a partir dos baldes por minuto.
enum TokenChart {
    static let windowLength: TimeInterval = 5 * 3600

    /// Janela de 5h atual quando `window` ainda não passou do reset; senão, as últimas 5 horas corridas.
    static func fiveHour(window: UsageWindow?, now: Date, buckets: TokenBuckets) -> TokenChartData {
        let (start, isRolling) = fiveHourStart(window: window, now: now)
        let edges = (0...5).map { start.addingTimeInterval(TimeInterval($0) * 3600) }
        return chart(edges: edges, now: now, isRolling: isRolling, buckets: buckets)
    }

    /// Segunda a domingo da semana de `now`, com os dias pela meia-noite local de `calendar`.
    static func week(now: Date, calendar: Calendar, buckets: TokenBuckets) -> TokenChartData {
        let monday = mondayStart(of: now, calendar: calendar)
        let edges = (0...7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        return chart(edges: edges, now: now, isRolling: false, buckets: buckets)
    }

    /// O mais antigo entre o início do modo 5h e a segunda 00:00: o período que o leitor precisa cobrir.
    static func earliestStart(window: UsageWindow?, now: Date, calendar: Calendar) -> Date {
        min(fiveHourStart(window: window, now: now).start, mondayStart(of: now, calendar: calendar))
    }

    private static func fiveHourStart(window: UsageWindow?, now: Date) -> (start: Date, isRolling: Bool) {
        if let resetsAt = window?.resetsAt, resetsAt > now {
            return (resetsAt.addingTimeInterval(-windowLength), false)
        }
        return (now.addingTimeInterval(-windowLength), true)
    }

    private static func mondayStart(of now: Date, calendar: Calendar) -> Date {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    /// `edges` são os limites das barras, em ordem: n + 1 datas para n barras.
    private static func chart(edges: [Date], now: Date, isRolling: Bool, buckets: TokenBuckets) -> TokenChartData {
        // Até o fim do minuto atual, para uma resposta de agora já aparecer.
        let countedUntil = Date(timeIntervalSince1970: ((now.timeIntervalSince1970 / 60).rounded(.down) + 1) * 60)
        let bars = zip(edges, edges.dropFirst()).enumerated().map { index, edge -> TokenBar in
            let (start, end) = edge
            let isFuture = start > now
            let isCurrent = isRolling ? index == edges.count - 2 : (start <= now && now < end)
            let count = isFuture ? .zero : buckets.sum(from: start, to: min(end, countedUntil))
            return TokenBar(start: start, end: end, count: count, isFuture: isFuture, isCurrent: isCurrent)
        }
        let total = buckets.sum(from: edges[0], to: min(edges[edges.count - 1], countedUntil))
        return TokenChartData(bars: bars, total: total, periodStart: edges[0], isRolling: isRolling)
    }
}
