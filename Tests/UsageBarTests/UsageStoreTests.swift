import XCTest
@testable import UsageBar

@MainActor
final class UsageStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageBarStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "UsageBarStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(_ result: Result<RateLimits, UsageReportError>) -> UsageStore {
        UsageStore(fileURL: directory.appendingPathComponent("state.json"), defaults: defaults,
                   fetchReport: { result })
    }

    private func waitForServerCheck(_ store: UsageStore) async throws {
        for _ in 0..<200 where store.isCheckingServer {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isCheckingServer)
    }

    func testServerReadingAtLaunchIsShownAndCached() async throws {
        let limits = try UsageReport.parse(Data(contentsOf: UsageReportTests.fixtureURL))

        let store = makeStore(.success(limits))
        try await waitForServerCheck(store)

        XCTAssertEqual(store.state.fiveHour?.usedPercentage, 25)
        XCTAssertNotNil(store.state.serverCheckedAt)
        XCTAssertNil(store.serverError)
        let cached = try XCTUnwrap(defaults.data(forKey: "usageState"))
        XCTAssertEqual(try JSONDecoder().decode(UsageState.self, from: cached), store.state)
    }

    func testServerFailureKeepsBridgeDataAndReportsError() async throws {
        try FileManager.default.copyItem(at: Fixture.url, to: directory.appendingPathComponent("state.json"))

        let store = makeStore(.failure(.claudeNotFound))
        try await waitForServerCheck(store)

        XCTAssertEqual(store.state.fiveHour?.usedPercentage, 19)
        XCTAssertNil(store.state.serverCheckedAt)
        XCTAssertEqual(store.serverError, .claudeNotFound)
    }

    func testCheckWithoutForceIsThrottled() async throws {
        var calls = 0
        let store = UsageStore(fileURL: directory.appendingPathComponent("state.json"), defaults: defaults,
                               fetchReport: { calls += 1; return .failure(.timedOut) })
        try await waitForServerCheck(store)

        store.checkServer()
        try await waitForServerCheck(store)
        XCTAssertEqual(calls, 1, "a consulta do início já conta para o intervalo mínimo")

        store.checkServer(force: true)
        try await waitForServerCheck(store)
        XCTAssertEqual(calls, 2)
    }
}
