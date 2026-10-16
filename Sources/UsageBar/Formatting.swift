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

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
