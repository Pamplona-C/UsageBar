import XCTest
@testable import UsageBar

@MainActor
final class TokenStoreTests: XCTestCase {
    /// Conta as chamadas de `scan`, que rodam fora da main thread.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func increment() { lock.withLock { value += 1 } }
    }

    private struct ScanError: LocalizedError {
        var errorDescription: String? { "sem permissão para ler os históricos" }
    }

    private func oneEvent() -> TokenBuckets {
        var buckets = TokenBuckets()
        buckets.add(TokenEvent(key: "a", date: Date(), count: TokenCount(total: 10, written: 1)))
        return buckets
    }

    private func waitWhileScanning(_ store: TokenStore) async throws {
        for _ in 0..<200 where store.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isScanning)
    }

    func testRefreshPublishesBuckets() async throws {
        let buckets = oneEvent()
        let store = TokenStore(scan: { _ in buckets })
        store.refresh(window: nil)
        try await waitWhileScanning(store)
        XCTAssertEqual(store.status, .ready(buckets))
    }

    func testScanErrorBecomesFailed() async throws {
        let store = TokenStore(scan: { _ in throw ScanError() })
        store.refresh(window: nil)
        try await waitWhileScanning(store)
        XCTAssertEqual(store.status, .failed("sem permissão para ler os históricos"))
    }

    func testRefreshIsThrottled() async throws {
        let calls = Calls()
        let store = TokenStore(scan: { _ in calls.increment(); return TokenBuckets() })
        store.refresh(window: nil)
        try await waitWhileScanning(store)
        store.refresh(window: nil)
        try await waitWhileScanning(store)
        XCTAssertEqual(calls.count, 1)
    }

    func testForceIgnoresThrottle() async throws {
        let calls = Calls()
        let store = TokenStore(scan: { _ in calls.increment(); return TokenBuckets() })
        store.refresh(window: nil)
        try await waitWhileScanning(store)
        store.refresh(window: nil, force: true)
        try await waitWhileScanning(store)
        XCTAssertEqual(calls.count, 2)
    }
}
