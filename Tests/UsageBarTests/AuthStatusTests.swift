import XCTest
@testable import UsageBar

final class AuthStatusTests: XCTestCase {
    static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/\(name)")
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtureURL(name))
    }

    func testParsesLoggedInWithClaudeAi() throws {
        XCTAssertEqual(AuthStatus.parse(try fixture("auth-status-logged-in.json")),
                       AuthStatus(loggedIn: true, authMethod: "claude.ai"))
    }

    func testParsesLoggedOut() throws {
        XCTAssertEqual(AuthStatus.parse(try fixture("auth-status-logged-out.json")),
                       AuthStatus(loggedIn: false, authMethod: "none"))
    }

    func testGarbageIsNil() {
        XCTAssertNil(AuthStatus.parse(Data("Not a json".utf8)))
        XCTAssertNil(AuthStatus.parse(Data()))
        XCTAssertNil(AuthStatus.parse(Data(#"{"authMethod":"claude.ai"}"#.utf8)), "sem loggedIn não dá para concluir")
    }

    // MARK: - Diagnóstico sem relatório

    func testLoggedOutMeansNotLoggedIn() {
        XCTAssertEqual(UsageReportError.diagnosingMissingReport(AuthStatus(loggedIn: false, authMethod: "none")),
                       .notLoggedIn)
    }

    func testOtherLoginMethodIsReported() {
        XCTAssertEqual(UsageReportError.diagnosingMissingReport(AuthStatus(loggedIn: true, authMethod: "console")),
                       .notClaudeAiLogin("console"))
    }

    func testClaudeAiLoginKeepsGenericError() {
        XCTAssertEqual(UsageReportError.diagnosingMissingReport(AuthStatus(loggedIn: true, authMethod: "claude.ai")),
                       .noUsageReport)
    }

    func testUnknownStatusKeepsGenericError() {
        XCTAssertEqual(UsageReportError.diagnosingMissingReport(nil), .noUsageReport)
    }

    func testOnlyLoginProblemsOfferLogin() {
        XCTAssertTrue(UsageReportError.notLoggedIn.offersLogin)
        XCTAssertTrue(UsageReportError.notClaudeAiLogin("console").offersLogin)
        XCTAssertFalse(UsageReportError.noUsageReport.offersLogin)
        XCTAssertFalse(UsageReportError.timedOut.offersLogin)
    }

    func testMessages() {
        XCTAssertEqual(UsageReportError.notLoggedIn.message, "O Claude Code não está logado.")
        XCTAssertEqual(UsageReportError.notClaudeAiLogin("console").message,
                       "O Claude Code está logado com console, e o uso do plano só aparece com login de uma conta do claude.ai.")
    }
}
