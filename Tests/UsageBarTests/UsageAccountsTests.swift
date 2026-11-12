import XCTest
@testable import UsageBar

@MainActor
final class UsageAccountsTests: XCTestCase {
    func testSwitchingProvidersKeepsReadingsSeparateAndRestoresSelection() async throws {
        let suite = "UsageBarAccountsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let claude = UsageStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                defaults: defaults,
                                fetchReport: { .success(RateLimits(fiveHour: UsageWindow(usedPercentage: 42))) },
                                tokens: TokenStore(scan: { _ in TokenBuckets() }))
        let codex = CodexStore(defaults: defaults,
                               fetch: { .success(CodexUsageReport(primary: CodexUsageWindow(usedPercent: 18))) },
                               startAutomatically: false)
        let accounts = UsageAccounts(defaults: defaults, claude: claude, codex: codex)
        codex.check()
        for _ in 0..<200 where claude.isCheckingServer || codex.isChecking {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        accounts.selected = .codex
        XCTAssertEqual(accounts.claude.state.fiveHour?.usedPercentage, 42)
        XCTAssertEqual(accounts.codex.report?.primary?.usedPercent, 18)
        accounts.selected = .claude
        XCTAssertEqual(accounts.codex.report?.primary?.usedPercent, 18)
        accounts.selected = .codex
        let restored = UsageAccounts(defaults: defaults, claude: claude, codex: codex)
        XCTAssertEqual(restored.selected, .codex)
    }
}
