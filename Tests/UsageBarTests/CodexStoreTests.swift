import XCTest
@testable import UsageBar

@MainActor
final class CodexStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let reading = CodexUsageReport(primary: CodexUsageWindow(usedPercent: 20, windowDurationMins: 300), planType: "plus")

    override func setUp() async throws {
        suite = "UsageBarCodexStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testCodexCacheDoesNotOverwriteClaudeCache() async throws {
        let original = Data("Claude cache".utf8)
        defaults.set(original, forKey: "usageState")
        let store = makeStore()
        store.check()
        try await wait(store)
        XCTAssertEqual(store.report, reading)
        XCTAssertNotNil(store.checkedAt)
        XCTAssertNil(store.error)
        XCTAssertEqual(defaults.data(forKey: "usageState"), original)
        let restored = makeStore()
        XCTAssertEqual(restored.report, reading)
    }

    func testAuthenticationFailureClearsOldAccountData() async throws {
        var result: Result<CodexUsageReport, CodexUsageError> = .success(reading)
        let store = CodexStore(defaults: defaults, fetch: { result }, startAutomatically: false)
        store.check()
        try await wait(store)
        result = .failure(.notLoggedIn)
        store.check(force: true)
        try await wait(store)
        XCTAssertNil(store.report)
        XCTAssertNil(store.checkedAt)
        XCTAssertNil(defaults.data(forKey: "codexUsageState"))
        XCTAssertTrue(store.needsConnection)
    }

    func testNetworkFailureKeepsLastReading() async throws {
        var result: Result<CodexUsageReport, CodexUsageError> = .success(reading)
        let store = CodexStore(defaults: defaults, fetch: { result }, startAutomatically: false)
        store.check()
        try await wait(store)
        result = .failure(.timedOut)
        store.check(force: true)
        try await wait(store)
        XCTAssertEqual(store.report, reading)
        XCTAssertEqual(store.error, .timedOut)
    }

    func testDisconnectDuringRequestCannotRestoreCache() async throws {
        var continuation: CheckedContinuation<Result<CodexUsageReport, CodexUsageError>, Never>?
        let store = CodexStore(defaults: defaults, fetch: { await withCheckedContinuation { continuation = $0 } }, startAutomatically: false)
        store.check()
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try XCTUnwrap(continuation)
        store.disconnect()
        pending.resume(returning: .success(reading))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(store.report)
        XCTAssertFalse(store.isEnabled)
        XCTAssertFalse(store.isChecking)
        XCTAssertNil(defaults.data(forKey: "codexUsageState"))
    }

    func testDisabledConnectionSurvivesRelaunchAndDoesNotFetch() async throws {
        makeStore().disconnect()
        var calls = 0
        let store = CodexStore(defaults: defaults, fetch: { calls += 1; return .failure(.notLoggedIn) }, startAutomatically: false)
        store.check(force: true)
        await Task.yield()
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(calls, 0)
    }

    func testOpenLoginFailureIsVisibleAndDoesNotStartWaiting() async throws {
        let store = CodexStore(defaults: defaults, openLogin: { .notFound }, startAutomatically: false)
        store.connect()
        try await wait(store)
        XCTAssertEqual(store.error, .notFound)
        XCTAssertFalse(store.isAwaitingLogin)
    }

    func testConnectWaitsForLoginAndSuccessfulCheckFinishesIt() async throws {
        let store = CodexStore(defaults: defaults, fetch: { .success(self.reading) }, openLogin: { nil }, startAutomatically: false)
        store.connect()
        try await wait(store)
        XCTAssertTrue(store.isAwaitingLogin)
        store.check(force: true)
        try await wait(store)
        XCTAssertFalse(store.isAwaitingLogin)
        XCTAssertEqual(store.report, reading)
    }

    func testChecksAreThrottledPerProvider() async throws {
        var calls = 0
        let store = CodexStore(defaults: defaults, fetch: { calls += 1; return .failure(.timedOut) }, startAutomatically: false)
        store.check()
        try await wait(store)
        store.check()
        XCTAssertEqual(calls, 1)
        store.check(force: true)
        try await wait(store)
        XCTAssertEqual(calls, 2)
    }

    private func makeStore() -> CodexStore {
        CodexStore(defaults: defaults, fetch: { .success(self.reading) }, startAutomatically: false)
    }

    private func wait(_ store: CodexStore) async throws {
        for _ in 0..<200 where store.isChecking || store.isOpeningLogin {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isChecking)
        XCTAssertFalse(store.isOpeningLogin)
    }
}
