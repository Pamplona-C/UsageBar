import XCTest
@testable import UsageBar

final class TranscriptLineTests: XCTestCase {
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/transcript-sample.jsonl")

    /// Linhas da fixture, na ordem do arquivo.
    static func fixtureLines() throws -> [Data] {
        try Data(contentsOf: fixtureURL).split(separator: UInt8(ascii: "\n")).map { Data($0) }
    }

    private func line(_ index: Int) throws -> Data {
        try Self.fixtureLines()[index]
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testParsesUsageLine() throws {
        let event = try XCTUnwrap(TranscriptLine.parse(line(0)))
        XCTAssertEqual(event.key, "msg_1|req_1")
        XCTAssertEqual(event.date, Date(timeIntervalSince1970: 1_793_275_530))
        XCTAssertEqual(event.count, TokenCount(total: 50_967, written: 331))
    }

    func testIgnoresSyntheticLine() throws {
        XCTAssertNil(TranscriptLine.parse(try line(3)))
    }

    func testIgnoresLineWithoutUsage() throws {
        XCTAssertNil(TranscriptLine.parse(try line(4)))
    }

    func testIgnoresCorruptedLine() throws {
        XCTAssertNil(TranscriptLine.parse(try line(5)))
    }

    func testMissingTokenFieldCountsAsZero() throws {
        let event = try XCTUnwrap(TranscriptLine.parse(json("""
            {"timestamp":"2026-10-29T12:00:00Z","requestId":"r","message":{"id":"m","model":"x","usage":{"output_tokens":7}}}
            """)))
        XCTAssertEqual(event.count, TokenCount(total: 7, written: 7))
    }

    func testLineWithoutIdIsIgnored() {
        XCTAssertNil(TranscriptLine.parse(json("""
            {"timestamp":"2026-10-29T12:00:00Z","requestId":"r","message":{"model":"x","usage":{"output_tokens":7}}}
            """)))
    }
}
