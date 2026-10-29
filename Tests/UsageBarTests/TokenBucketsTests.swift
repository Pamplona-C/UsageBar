import XCTest
@testable import UsageBar

final class TokenBucketsTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_793_275_200) // 2026-10-29 12:00:00 UTC

    private func event(_ key: String, at offset: TimeInterval, total: Int = 100, written: Int = 10) -> TokenEvent {
        TokenEvent(key: key, date: base.addingTimeInterval(offset), count: TokenCount(total: total, written: written))
    }

    private var all: (Date, Date) { (base.addingTimeInterval(-86_400), base.addingTimeInterval(86_400)) }

    func testDuplicateKeyIsCountedOnce() {
        var buckets = TokenBuckets()
        buckets.add(event("a", at: 0))
        buckets.add(event("a", at: 1))
        XCTAssertEqual(buckets.sum(from: all.0, to: all.1), TokenCount(total: 100, written: 10))
    }

    func testSumUsesHalfOpenRange() {
        var buckets = TokenBuckets()
        buckets.add(event("before", at: -1))      // 11:59:59
        buckets.add(event("start", at: 0))        // 12:00:00
        buckets.add(event("end", at: 3600))       // 13:00:00, fora de [12:00, 13:00)
        XCTAssertEqual(buckets.sum(from: base, to: base.addingTimeInterval(3600)),
                       TokenCount(total: 100, written: 10))
    }

    func testSumAcrossMinutes() {
        var buckets = TokenBuckets()
        buckets.add(event("a", at: 0, total: 1, written: 1))
        buckets.add(event("b", at: 90, total: 2, written: 2))
        buckets.add(event("c", at: 600, total: 4, written: 4))
        XCTAssertEqual(buckets.sum(from: all.0, to: all.1), TokenCount(total: 7, written: 7))
    }

    func testPruneDropsOldBucketsAndKeys() {
        var buckets = TokenBuckets()
        buckets.add(event("old", at: -7200))
        buckets.add(event("new", at: 0))
        buckets.prune(before: base.addingTimeInterval(-60))
        XCTAssertEqual(buckets.sum(from: all.0, to: all.1), TokenCount(total: 100, written: 10))
        XCTAssertFalse(buckets.hasSeen("old"))
        XCTAssertTrue(buckets.hasSeen("new"))
    }

    func testAddBeforePruneLimitIsIgnored() {
        var buckets = TokenBuckets()
        buckets.prune(before: base)
        buckets.add(event("old", at: -60))
        XCTAssertTrue(buckets.isEmpty)
        XCTAssertEqual(buckets.sum(from: all.0, to: all.1), .zero)
    }
}
