import XCTest
@testable import UsageBar

final class TokenChartTests: XCTestCase {
    private func calendar(_ identifier: String = "America/Sao_Paulo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// "2026-10-29 11:40" no fuso do calendário.
    private func date(_ text: String, _ calendar: Calendar? = nil) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = (calendar ?? self.calendar()).timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func buckets(_ events: [(String, Int)]) -> TokenBuckets {
        var buckets = TokenBuckets()
        for (index, (time, written)) in events.enumerated() {
            buckets.add(TokenEvent(key: "\(index)", date: date(time),
                                   count: TokenCount(total: written * 10, written: written)))
        }
        return buckets
    }

    func testFiveHourBarsFollowTheWindow() {
        let window = UsageWindow(usedPercentage: 25, resetsAt: date("2026-10-29 14:20"))
        let chart = TokenChart.fiveHour(window: window, now: date("2026-10-29 11:40"), buckets: TokenBuckets())
        XCTAssertEqual(chart.bars.map(\.start), ["09:20", "10:20", "11:20", "12:20", "13:20"].map {
            date("2026-10-29 \($0)")
        })
        XCTAssertEqual(chart.bars.last?.end, date("2026-10-29 14:20"))
        XCTAssertEqual(chart.bars.map(\.isCurrent), [false, false, true, false, false])
        XCTAssertEqual(chart.bars.map(\.isFuture), [false, false, false, true, true])
        XCTAssertEqual(chart.periodStart, date("2026-10-29 09:20"))
        XCTAssertFalse(chart.isRolling)
    }

    func testFiveHourTotalIsExactToTheMinute() {
        let window = UsageWindow(usedPercentage: 25, resetsAt: date("2026-10-29 14:20"))
        let events = buckets([("2026-10-29 09:19", 1), ("2026-10-29 09:20", 2), ("2026-10-29 11:39", 4)])
        let chart = TokenChart.fiveHour(window: window, now: date("2026-10-29 11:40"), buckets: events)
        XCTAssertEqual(chart.total, TokenCount(total: 60, written: 6))
        XCTAssertEqual(chart.bars[0].count, TokenCount(total: 20, written: 2))
        XCTAssertEqual(chart.bars[2].count, TokenCount(total: 40, written: 4))
    }

    func testPassedResetFallsBackToRollingHours() {
        let window = UsageWindow(usedPercentage: 90, resetsAt: date("2026-10-29 08:00"))
        let chart = TokenChart.fiveHour(window: window, now: date("2026-10-29 11:40"), buckets: TokenBuckets())
        XCTAssertTrue(chart.isRolling)
        XCTAssertEqual(chart.bars.count, 5)
        XCTAssertEqual(chart.bars.first?.start, date("2026-10-29 06:40"))
        XCTAssertEqual(chart.bars.last?.end, date("2026-10-29 11:40"))
        XCTAssertEqual(chart.bars.filter(\.isFuture).count, 0)
    }

    func testNoWindowFallsBackToRollingHours() {
        let chart = TokenChart.fiveHour(window: nil, now: date("2026-10-29 11:40"), buckets: TokenBuckets())
        XCTAssertTrue(chart.isRolling)
        XCTAssertEqual(chart.periodStart, date("2026-10-29 06:40"))
    }

    func testWeekStartsOnMondayLocalMidnight() {
        let chart = TokenChart.week(now: date("2026-10-29 15:00"), calendar: calendar(), buckets: TokenBuckets())
        XCTAssertEqual(chart.bars.count, 7)
        XCTAssertEqual(chart.bars.first?.start, date("2026-10-26 00:00"))
        XCTAssertEqual(chart.bars.last?.end, date("2026-11-02 00:00"))
        // seg, ter, qua passados; qui é hoje; sex a dom no futuro.
        XCTAssertEqual(chart.bars.map(\.isCurrent), [false, false, false, true, false, false, false])
        XCTAssertEqual(chart.bars.map(\.isFuture), [false, false, false, false, true, true, true])
        XCTAssertFalse(chart.isRolling)
    }

    func testWeekWithHalfHourTimeZone() {
        let stJohns = calendar("America/St_Johns")
        let chart = TokenChart.week(now: date("2026-10-29 15:00", stJohns), calendar: stJohns, buckets: TokenBuckets())
        XCTAssertEqual(chart.bars.first?.start, date("2026-10-26 00:00", stJohns))
        XCTAssertEqual(chart.bars[1].start, date("2026-10-27 00:00", stJohns))
    }

    func testWeekAcrossDaylightSavingChange() {
        let newYork = calendar("America/New_York")
        let chart = TokenChart.week(now: date("2026-10-29 15:00", newYork), calendar: newYork, buckets: TokenBuckets())
        let sunday = chart.bars[6]
        XCTAssertEqual(sunday.start, date("2026-11-01 00:00", newYork))
        XCTAssertEqual(sunday.end, date("2026-11-02 00:00", newYork))
        XCTAssertEqual(sunday.end.timeIntervalSince(sunday.start), 25 * 3600)
    }

    func testEventsOutsidePeriodAreNotCounted() {
        let events = buckets([("2026-10-25 23:59", 1), ("2026-10-26 00:00", 2), ("2026-10-29 15:30", 4)])
        let chart = TokenChart.week(now: date("2026-10-29 15:00"), calendar: calendar(), buckets: events)
        XCTAssertEqual(chart.total, TokenCount(total: 20, written: 2))
    }

    func testEarliestStartPicksTheOlderOne() {
        // Segunda 02:00 com reset às 04:00: a janela abriu no domingo 23:00, antes da segunda 00:00.
        let window = UsageWindow(usedPercentage: 10, resetsAt: date("2026-10-26 04:00"))
        XCTAssertEqual(TokenChart.earliestStart(window: window, now: date("2026-10-26 02:00"), calendar: calendar()),
                       date("2026-10-25 23:00"))
        // Quinta: a segunda 00:00 é mais antiga.
        let later = UsageWindow(usedPercentage: 10, resetsAt: date("2026-10-29 14:20"))
        XCTAssertEqual(TokenChart.earliestStart(window: later, now: date("2026-10-29 11:40"), calendar: calendar()),
                       date("2026-10-26 00:00"))
    }
}
