import XCTest
@testable import UsageBar

final class CodexUsageReportTests: XCTestCase {
    static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/codex-rate-limits-sample.json")

    func testCapturedAccountLimitsAndDurations() throws {
        let report = try CodexUsageReport.parse(Data(contentsOf: Self.fixtureURL))
        XCTAssertEqual(report.primary?.usedPercent, 25)
        XCTAssertEqual(report.primary?.windowDurationMins, 300)
        XCTAssertEqual(report.secondary?.usedPercent, 56)
        XCTAssertEqual(report.secondary?.windowDurationMins, 10_080)
        XCTAssertEqual(report.primary?.window.resetsAt?.timeIntervalSince1970, 1_767_276_000)
        XCTAssertEqual(report.planType, "plus")
        XCTAssertEqual(try JSONDecoder().decode(CodexUsageReport.self, from: JSONEncoder().encode(report)), report)
    }

    func testCodexBucketTakesPrecedenceOverSingleBucketAndOtherModels() throws {
        let report = try parse(#"{"rateLimits":{"primary":{"usedPercent":90}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99}},"codex":{"primary":{"usedPercent":12}}}}"#)
        XCTAssertEqual(report.primary?.usedPercent, 12)
    }

    func testUnknownMeteredBucketIsNotPresentedAsCodex() {
        XCTAssertThrowsError(try parse(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99}}}}"#))
    }

    func testMalformedPrimaryDoesNotLoseValidSecondary() throws {
        let report = try parse(#"{"rateLimits":{"primary":{"usedPercent":"wrong","windowDurationMins":300},"secondary":{"usedPercent":42,"windowDurationMins":10080}}}"#)
        XCTAssertNil(report.primary)
        XCTAssertEqual(report.secondary?.usedPercent, 42)
    }

    func testOptionalResetAndDurationDoNotLosePercentage() throws {
        let report = try parse(#"{"rateLimits":{"primary":{"usedPercent":12.5,"resetsAt":null,"windowDurationMins":"new-format"},"futureField":true}}"#)
        XCTAssertEqual(report.primary?.usedPercent, 12.5)
        XCTAssertNil(report.primary?.window.resetsAt)
        XCTAssertEqual(report.primary?.title(fallback: "Janela atual"), "Janela atual")
    }

    func testInvalidPercentagesAndMissingLimitsAreUnavailable() {
        for text in ["", "not-json", "[]", "{}", #"{"rateLimits":null}"#,
                     #"{"rateLimits":{"primary":{"usedPercent":1e100}}}"#,
                     #"{"rateLimits":{"primary":{"usedPercent":-2}}}"#] {
            XCTAssertThrowsError(try parse(text)) { XCTAssertEqual($0 as? CodexUsageError, .noLimits) }
        }
    }

    func testWindowTitlesRespectActualDuration() {
        for (minutes, title) in [(15, "15 min"), (60, "1 hora"), (300, "5 horas"),
                                 (1440, "1 dia"), (2880, "2 dias"), (10_080, "Semana")] {
            XCTAssertEqual(CodexUsageWindow(usedPercent: 0, windowDurationMins: minutes).title(fallback: "Janela"), title)
        }
    }

    private func parse(_ text: String) throws -> CodexUsageReport { try CodexUsageReport.parse(Data(text.utf8)) }
}
