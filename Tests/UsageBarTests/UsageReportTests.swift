import XCTest
@testable import UsageBar

final class UsageReportTests: XCTestCase {
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/usage-report-sample.jsonl")

    private func fixture() throws -> Data {
        try Data(contentsOf: Self.fixtureURL)
    }

    /// A fixture com a linha do relatório alterada, para os casos de formato diferente.
    private func fixture(changingReport change: (inout [String: Any]) -> Void) throws -> Data {
        let lines = try fixture().split(separator: UInt8(ascii: "\n")).map { line -> Data in
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            if object["usage_report"] != nil {
                change(&object)
            }
            return try JSONSerialization.data(withJSONObject: object)
        }
        return Data(lines.joined(separator: [UInt8(ascii: "\n")]))
    }

    private func limits(_ rows: [[String: Any]]) -> (inout [String: Any]) -> Void {
        { object in
            var report = object["usage_report"] as! [String: Any]
            report["rate_limits"] = ["limits": rows]
            object["usage_report"] = report
        }
    }

    // MARK: - Parser

    func testRealFixtureMapsSessionAndWeekly() throws {
        let limits = try UsageReport.parse(try fixture())

        XCTAssertEqual(limits.fiveHour?.usedPercentage, 25)
        XCTAssertEqual(limits.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_792_160_400), "arredondado para segundos")
        XCTAssertEqual(limits.sevenDay?.usedPercentage, 56)
        XCTAssertEqual(limits.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_792_274_400))
    }

    /// Mesma janela que o bridge grava (`resets_at` 1792160400): o app não pode tratá-la como janela nova.
    func testFixtureWindowMatchesStatuslineWindow() throws {
        let fromServer = try XCTUnwrap(try UsageReport.parse(try fixture()).fiveHour)
        let fromBridge = UsageWindow(usedPercentage: 24, resetsAt: Date(timeIntervalSince1970: 1_792_160_400))

        XCTAssertEqual(UsageState.compare(fromServer, to: fromBridge), .newer, "25% > 24% na mesma janela")
        XCTAssertEqual(UsageState.compare(fromBridge, to: fromServer), .older)
    }

    func testRowsAreClassifiedByKindNotOrder() throws {
        let data = try fixture(changingReport: limits([
            ["kind": "weekly_scoped", "percent": 90, "resets_at": "2026-10-17T22:00:00+00:00"],
            ["kind": "weekly_all", "percent": 40, "resets_at": "2026-10-17T22:00:00Z"],
            ["kind": "session", "percent": 12.5, "resets_at": "2026-10-16T14:20:00+00:00"],
        ]))

        let limits = try UsageReport.parse(data)

        XCTAssertEqual(limits.fiveHour?.usedPercentage, 12.5)
        XCTAssertEqual(limits.sevenDay?.usedPercentage, 40)
    }

    func testMalformedRowIsSkippedWithoutLosingTheOthers() throws {
        let data = try fixture(changingReport: limits([
            ["kind": "session", "percent": "muito", "resets_at": 123],
            ["kind": "weekly_all", "percent": 56, "resets_at": "2026-10-17T22:00:00Z"],
        ]))

        let limits = try UsageReport.parse(data)

        XCTAssertNil(limits.fiveHour)
        XCTAssertEqual(limits.sevenDay?.usedPercentage, 56)
    }

    func testNullResetKeepsPercentage() throws {
        let data = try fixture(changingReport: limits([
            ["kind": "session", "percent": 0, "resets_at": NSNull()],
        ]))

        let limits = try UsageReport.parse(data)

        XCTAssertEqual(limits.fiveHour?.usedPercentage, 0)
        XCTAssertNil(limits.fiveHour?.resetsAt)
    }

    func testOnlyUnknownKindsIsAnError() throws {
        let data = try fixture(changingReport: limits([
            ["kind": "weekly_scoped", "percent": 90, "resets_at": NSNull()],
        ]))

        XCTAssertThrowsError(try UsageReport.parse(data)) {
            XCTAssertEqual($0 as? UsageReportError, .noKnownLimits)
        }
    }

    func testNullRateLimitsIsAnError() throws {
        let data = try fixture(changingReport: { object in
            var report = object["usage_report"] as! [String: Any]
            report["rate_limits"] = NSNull()
            object["usage_report"] = report
        })

        XCTAssertThrowsError(try UsageReport.parse(data)) {
            XCTAssertEqual($0 as? UsageReportError, .noLimits)
        }
    }

    /// Sessões com API key ou versões antigas mandam só o texto, sem `usage_report`.
    func testTextOnlyReportIsAnError() throws {
        let data = try fixture(changingReport: { $0["usage_report"] = nil })

        XCTAssertThrowsError(try UsageReport.parse(data)) {
            XCTAssertEqual($0 as? UsageReportError, .noUsageReport)
        }
    }

    func testErrorResultCarriesItsMessage() throws {
        let data = Data(#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in"}"#.utf8)

        XCTAssertThrowsError(try UsageReport.parse(data)) {
            XCTAssertEqual($0 as? UsageReportError, .failed("Not logged in"))
        }
    }

    func testGarbageAndEmptyOutput() throws {
        XCTAssertThrowsError(try UsageReport.parse(Data())) {
            XCTAssertEqual($0 as? UsageReportError, .noUsageReport)
        }
        var noisy = Data("aviso qualquer\n{não é json\n".utf8)
        noisy.append(try fixture())

        XCTAssertEqual(try UsageReport.parse(noisy).fiveHour?.usedPercentage, 25)
    }

    // MARK: - Processo

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageBarReport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Um `claude` falso: um script bash com o corpo dado.
    private func fakeClaude(_ body: String, name: String = "claude") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testRunPassesDocumentedArgumentsAndParsesOutput() throws {
        let argsFile = directory.appendingPathComponent("args")
        let claude = try fakeClaude("""
        printf '%s\\n' "$@" > '\(argsFile.path)'
        cat '\(Self.fixtureURL.path)'
        """)

        let result = UsageReportClient.run(claude)

        XCTAssertEqual(try result.get().sevenDay?.usedPercentage, 56)
        let args = try String(contentsOf: argsFile, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(args, ["-p", "--safe-mode", "--no-session-persistence",
                              "--output-format", "stream-json", "--verbose", "/usage"])
    }

    func testRunReportsStderrWhenCommandFails() throws {
        let claude = try fakeClaude("echo 'Invalid API key · Please run /login' >&2; exit 1")

        XCTAssertEqual(UsageReportClient.run(claude), .failure(.failed("Invalid API key · Please run /login")))
    }

    func testRunReportsExitCodeWithoutStderr() throws {
        let claude = try fakeClaude("exit 3")

        XCTAssertEqual(UsageReportClient.run(claude), .failure(.failed("O Claude Code terminou com o código 3.")))
    }

    func testRunTimesOut() throws {
        let claude = try fakeClaude("exec sleep 10")
        let start = Date()

        XCTAssertEqual(UsageReportClient.run(claude, timeout: 0.5), .failure(.timedOut))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testRunReportsLaunchFailure() throws {
        let missing = directory.appendingPathComponent("nao-existe")

        guard case .failure(.launchFailed) = UsageReportClient.run(missing) else {
            return XCTFail("esperava launchFailed")
        }
    }

    func testLocateClaudeSkipsMissingAndNonExecutableCandidates() throws {
        let notExecutable = directory.appendingPathComponent("texto")
        try "".write(to: notExecutable, atomically: true, encoding: .utf8)
        let claude = try fakeClaude("exit 0")

        let found = UsageReportClient.locateClaude(candidates: [
            directory.appendingPathComponent("nao-existe"), notExecutable, claude,
        ])

        XCTAssertEqual(found, claude)
    }
}
