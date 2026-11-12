import Foundation

/// Dados dos CLIs e históricos são entrada externa: valores extremos não chegam aos formatadores.
enum UsageValidation {
    static func percentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    static func resetDate(_ seconds: Double?) -> Date? {
        // Intervalo representável como data civil ISO 8601 (até 9999-12-31).
        guard let seconds, seconds.isFinite, (0...253_402_300_799).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
