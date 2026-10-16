import XCTest
@testable import UsageBar

final class FormattingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

    /// Quinta-feira, 15/10/2026 12:34 (-03), horário da captura da fixture.
    private let now = Date(timeIntervalSince1970: 1_792_078_440)

    func testPercent() {
        XCTAssertEqual(Format.percent(42), "42%")
        XCTAssertEqual(Format.percent(23.5), "24%")
        XCTAssertEqual(Format.percent(nil), "--%")
    }

    func testUpdated() {
        XCTAssertEqual(Format.updated(now - 30, now: now), "Atualizado agora")
        XCTAssertEqual(Format.updated(now - 5 * 60, now: now), "Atualizado há 5 min")
        XCTAssertEqual(Format.updated(now - 2 * 3600, now: now), "Atualizado há 2 h")
        XCTAssertEqual(Format.updated(now - 86_400, now: now), "Atualizado há 1 dia")
        XCTAssertEqual(Format.updated(now - 3 * 86_400, now: now), "Atualizado há 3 dias")
        XCTAssertEqual(Format.updated(now + 10, now: now), "Atualizado agora", "relógio adiantado não gera tempo negativo")
    }

    func testAgo() {
        XCTAssertEqual(Format.ago(now - 30, now: now), "agora")
        XCTAssertEqual(Format.ago(now - 5 * 60, now: now), "há 5 min")
        XCTAssertEqual(Format.ago(now - 2 * 86_400, now: now), "há 2 dias")
    }

    func testResetUsesFixtureTimes() {
        XCTAssertEqual(Format.reset(Date(timeIntervalSince1970: 1_792_086_600), now: now, calendar: calendar),
                       "hoje às 14:50")
        XCTAssertEqual(Format.reset(Date(timeIntervalSince1970: 1_792_274_400), now: now, calendar: calendar),
                       "sábado às 19:00")
    }

    func testResetTomorrowAndFarDates() {
        let tomorrowMorning = Date(timeIntervalSince1970: 1_792_152_000) // 16/10/2026 09:00 (-03)
        XCTAssertEqual(Format.reset(tomorrowMorning, now: now, calendar: calendar), "amanhã às 09:00")

        let nextWeek = Date(timeIntervalSince1970: 1_792_879_200) // 24/10/2026 19:00 (-03)
        XCTAssertEqual(Format.reset(nextWeek, now: now, calendar: calendar), "24/10 às 19:00")
    }
}
