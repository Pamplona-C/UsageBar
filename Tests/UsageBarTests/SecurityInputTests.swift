import XCTest
@testable import UsageBar

final class SecurityInputTests: XCTestCase {
    func testExtremePercentagesCannotCrashFormatting() {
        for value in [Double.nan, Double.infinity, -Double.infinity, 1e100, -1, 101] {
            XCTAssertEqual(Format.percent(value), "--%")
            XCTAssertNil(UsageValidation.percentage(value))
        }
        XCTAssertEqual(Format.percent(100), "100%")
    }

    func testExtremeStatuslineFieldsAreDiscardedIndependently() throws {
        let data = Data(#"{"rate_limits":{"five_hour":{"used_percentage":1e100,"resets_at":1e300},"seven_day":{"used_percentage":50,"resets_at":1792274400}}}"#.utf8)
        let snapshot = try StateFile.parse(data)
        XCTAssertNil(snapshot.rateLimits?.fiveHour?.usedPercentage)
        XCTAssertNil(snapshot.rateLimits?.fiveHour?.resetsAt)
        XCTAssertEqual(snapshot.rateLimits?.sevenDay?.usedPercentage, 50)
    }

    func testNegativeAndOverflowingTranscriptCountersAreIgnored() {
        for counters in [#""output_tokens":-1"#, #""input_tokens":9223372036854775807,"output_tokens":1"#] {
            let text = """
            {"timestamp":"2026-01-01T12:00:00Z","message":{"id":"example","model":"example","usage":{\(counters)}}}
            """
            XCTAssertNil(TranscriptLine.parse(Data(text.utf8)))
        }
    }

    func testAggregationSaturatesInsteadOfTrappingOnOverflow() {
        let count = TokenCount(total: Int.max, written: Int.max) + TokenCount(total: 1, written: 1)
        XCTAssertEqual(count.total, Int.max)
        XCTAssertEqual(count.written, Int.max)
        XCTAssertFalse(Format.tokens(count.total).isEmpty)
    }

    func testSubprocessIgnoringTerminateHasBoundedTimeout() throws {
        let executable = try fakeProcess("import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(30)")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let start = Date()
        guard case .timedOut = BoundedProcess.run(executable, [], timeout: 0.3) else { return XCTFail() }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testExcessiveSubprocessOutputIsRejected() throws {
        let executable = try fakeProcess("import sys\nsys.stdout.write('x' * 100000)\nsys.stdout.flush()")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        guard case .outputTooLarge = BoundedProcess.run(executable, [], timeout: 3, outputLimit: 1024) else { return XCTFail() }
    }

    private func fakeProcess(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBarSecurity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-cli")
        try ("#!/usr/bin/python3\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
