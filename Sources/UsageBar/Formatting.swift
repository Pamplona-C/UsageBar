import Foundation

/// Textos exibidos na barra e no popover.
enum Format {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    static func updated(_ date: Date, now: Date) -> String {
        "Atualizado \(ago(date, now: now))"
    }

    /// "agora", "há 5 min", "há 2 h" ou "há 3 dias".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return "agora"
        case ..<3600:
            return "há \(Int(seconds / 60)) min"
        case ..<86_400:
            return "há \(Int(seconds / 3600)) h"
        default:
            let days = Int(seconds / 86_400)
            return "há \(days) \(days == 1 ? "dia" : "dias")"
        }
    }

    /// "hoje às 14:50", "amanhã às 09:00", "sábado às 19:00" ou "24/10 às 19:00".
    static func reset(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = formatter("HH:mm", calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "hoje às \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "amanhã às \(time)"
        }
        if date.timeIntervalSince(now) < 6 * 86_400 {
            return "\(formatter("EEEE", calendar).string(from: date)) às \(time)"
        }
        return "\(formatter("dd/MM", calendar).string(from: date)) às \(time)"
    }

    /// "950", "1,2 mil", "223 mil", "43,7M", "1,3 bi": uma casa decimal abaixo de 100 da unidade.
    static func tokens(_ value: Int) -> String {
        let units: [(Double, String)] = [(1e3, " mil"), (1e6, "M"), (1e9, " bi")]
        guard var index = units.lastIndex(where: { Double(value) >= $0.0 }) else { return "\(value)" }
        // Se o arredondamento chegar a 1000 da unidade, passa para a próxima: 999.960 vira "1,0M", não "1000 mil".
        if index < units.count - 1, (Double(value) / units[index].0).rounded(.toNearestOrAwayFromZero) >= 1000 {
            index += 1
        }
        let (size, suffix) = units[index]
        let tenths = (Double(value) / size * 10).rounded(.toNearestOrAwayFromZero)
        guard tenths < 1000 else { return "\(Int((tenths / 10).rounded(.toNearestOrAwayFromZero)))" + suffix }
        let whole = Int(tenths) / 10, decimal = Int(tenths) % 10
        return "\(whole),\(decimal)" + suffix
    }

    /// Texto abaixo do anel: "reinicia em 2h40" no mesmo dia, "reinicia amanhã 19:00" ou "reinicia sábado 19:00".
    static func resetShort(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "janela reiniciada" }
        if calendar.isDate(date, inSameDayAs: now) {
            let minutes = Int((seconds / 60).rounded(.up))
            if minutes < 60 { return "reinicia em \(minutes) min" }
            let rest = minutes % 60
            return "reinicia em \(minutes / 60)h" + (rest == 0 ? "" : String(format: "%02d", rest))
        }
        return "reinicia " + reset(date, now: now, calendar: calendar).replacingOccurrences(of: " às ", with: " ")
    }

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
