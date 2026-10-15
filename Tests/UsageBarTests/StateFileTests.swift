import XCTest
@testable import UsageBar

final class StateFileTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageBarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixture real

    func testParsesRealFixture() throws {
        let snapshot = try StateFile.parse(Fixture.data())

        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.usedPercentage, 19)
        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_792_086_600))
        XCTAssertEqual(snapshot.rateLimits?.sevenDay?.usedPercentage, 50)
        XCTAssertEqual(snapshot.rateLimits?.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_792_274_400))
    }

    func testLoadsRealFixtureFromDiskWithModificationDate() throws {
        let url = tempDir.appendingPathComponent("state.json")
        try Fixture.data().write(to: url)
        let modifiedAt = Date(timeIntervalSince1970: 1_792_080_000)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)

        let contents = try StateFile.load(from: url)

        XCTAssertEqual(contents.snapshot.rateLimits?.fiveHour?.usedPercentage, 19)
        XCTAssertEqual(contents.modifiedAt, modifiedAt)
    }

    // MARK: - Campos ausentes, novos ou inesperados

    func testFixtureWithoutRateLimitsParsesToEmptySnapshot() throws {
        let data = try Fixture.modified { $0.removeValue(forKey: "rate_limits") }

        let snapshot = try StateFile.parse(data)

        XCTAssertNil(snapshot.rateLimits)
    }

    func testEachWindowCanBeAbsentIndependently() throws {
        let data = try Fixture.modified { json in
            var limits = json["rate_limits"] as! [String: Any]
            limits.removeValue(forKey: "five_hour")
            json["rate_limits"] = limits
        }

        let snapshot = try StateFile.parse(data)

        XCTAssertNil(snapshot.rateLimits?.fiveHour)
        XCTAssertEqual(snapshot.rateLimits?.sevenDay?.usedPercentage, 50)
    }

    func testAcceptsDecimalPercentage() throws {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}"#

        let snapshot = try StateFile.parse(Data(json.utf8))

        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.usedPercentage, 23.5)
    }

    func testIgnoresUnknownFields() throws {
        let data = try Fixture.modified { json in
            var limits = json["rate_limits"] as! [String: Any]
            limits["spend_limit"] = ["used_percentage": 62.8, "period": "monthly"]
            json["rate_limits"] = limits
            json["campo_do_futuro"] = ["qualquer": true]
        }

        let snapshot = try StateFile.parse(data)

        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.usedPercentage, 19)
    }

    func testFieldWithUnexpectedTypeBecomesNilWithoutLosingTheRest() throws {
        let json = #"""
        {"rate_limits":{
          "five_hour":{"used_percentage":"muito","resets_at":1792086600},
          "seven_day":{"used_percentage":50,"resets_at":1792274400}
        }}
        """#

        let snapshot = try StateFile.parse(Data(json.utf8))

        XCTAssertNil(snapshot.rateLimits?.fiveHour?.usedPercentage)
        XCTAssertEqual(snapshot.rateLimits?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_792_086_600))
        XCTAssertEqual(snapshot.rateLimits?.sevenDay?.usedPercentage, 50)
    }

    func testNullRateLimitsParsesToEmptySnapshot() throws {
        let snapshot = try StateFile.parse(Data(#"{"rate_limits":null}"#.utf8))

        XCTAssertNil(snapshot.rateLimits)
    }

    // MARK: - Arquivo inválido ou ausente

    func testCorruptedJSONThrowsInvalidJSON() {
        let truncated = Fixture.data().prefix(200)

        XCTAssertThrowsError(try StateFile.parse(truncated)) { error in
            XCTAssertEqual(error as? StateFileError, .invalidJSON)
        }
    }

    func testEmptyFileThrowsInvalidJSON() throws {
        let url = tempDir.appendingPathComponent("state.json")
        try Data().write(to: url)

        XCTAssertThrowsError(try StateFile.load(from: url)) { error in
            XCTAssertEqual(error as? StateFileError, .invalidJSON)
        }
    }

    func testNonObjectJSONThrowsInvalidJSON() {
        XCTAssertThrowsError(try StateFile.parse(Data("[1, 2, 3]".utf8))) { error in
            XCTAssertEqual(error as? StateFileError, .invalidJSON)
        }
    }

    func testMissingFileThrowsNotFound() {
        let url = tempDir.appendingPathComponent("nao-existe.json")

        XCTAssertThrowsError(try StateFile.load(from: url)) { error in
            XCTAssertEqual(error as? StateFileError, .notFound)
        }
    }

    // MARK: - Codable

    func testWindowRoundTripsResetAsEpochSeconds() throws {
        let window = UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1_792_086_600))

        let data = try JSONEncoder().encode(window)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["resets_at"] as? Double, 1_792_086_600)
        XCTAssertEqual(try JSONDecoder().decode(UsageWindow.self, from: data), window)
    }
}

enum Fixture {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fixtures/statusline-sample.json")

    static func data() -> Data {
        try! Data(contentsOf: url)
    }

    /// A fixture real com uma alteração aplicada, para os casos de campos ausentes ou novos.
    static func modified(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
}
