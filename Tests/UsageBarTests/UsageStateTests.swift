import XCTest
@testable import UsageBar

final class UsageStateTests: XCTestCase {
    private let reset5h = Date(timeIntervalSince1970: 1_792_086_600)
    private let reset7d = Date(timeIntervalSince1970: 1_792_274_400)
    private let t0 = Date(timeIntervalSince1970: 1_792_080_000)

    private func snapshot(fiveHour: Double?, fiveHourReset: Date? = nil,
                          sevenDay: Double? = nil, sevenDayReset: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(rateLimits: RateLimits(
            fiveHour: fiveHour.map { UsageWindow(usedPercentage: $0, resetsAt: fiveHourReset ?? reset5h) },
            sevenDay: sevenDay.map { UsageWindow(usedPercentage: $0, resetsAt: sevenDayReset ?? reset7d) }
        ))
    }

    func testFirstSnapshotIsAccepted() {
        var state = UsageState()

        state.absorb(snapshot(fiveHour: 16, sevenDay: 50), receivedAt: t0)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 16)
        XCTAssertEqual(state.sevenDay?.usedPercentage, 50)
        XCTAssertEqual(state.updatedAt, t0)
    }

    /// O caso real da captura: a sessão parada grava 5% depois que a ativa gravou 16%.
    func testStaleSessionWithLowerValueInSameWindowIsIgnored() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16, sevenDay: 50), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 5, sevenDay: 48), receivedAt: t0 + 1)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 16)
        XCTAssertEqual(state.sevenDay?.usedPercentage, 50)
        XCTAssertEqual(state.updatedAt, t0, "payload antigo não conta como atualização")
    }

    /// Visto com o app rodando: a janela semanal da sessão parada coincidia e avançava o "atualizado".
    func testStaleSessionWithMatchingWeeklyDoesNotRefreshUpdatedAt() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 23, sevenDay: 50), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 5, sevenDay: 50), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 23)
        XCTAssertEqual(state.updatedAt, t0)
    }

    func testHigherValueInSameWindowIsAccepted() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 19), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 19)
        XCTAssertEqual(state.updatedAt, t0 + 60)
    }

    func testSameValueRefreshesUpdatedAt() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 16), receivedAt: t0 + 60)

        XCTAssertEqual(state.updatedAt, t0 + 60)
    }

    func testNewWindowReplacesHigherValueFromPreviousWindow() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 90), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 3, fiveHourReset: reset5h + 5 * 3600), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 3)
        XCTAssertEqual(state.fiveHour?.resetsAt, reset5h + 5 * 3600)
    }

    func testPayloadFromPreviousWindowIsIgnored() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 3, fiveHourReset: reset5h + 5 * 3600), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 90), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 3)
        XCTAssertEqual(state.updatedAt, t0)
    }

    func testSmallResetDifferenceCountsAsSameWindow() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 20), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 10, fiveHourReset: reset5h + 60), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 20)
    }

    func testWindowsAreMergedIndependently() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16, sevenDay: 50), receivedAt: t0)

        state.absorb(snapshot(fiveHour: nil, sevenDay: 52), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 16, "janela ausente mantém o valor conhecido")
        XCTAssertEqual(state.sevenDay?.usedPercentage, 52)
        XCTAssertEqual(state.updatedAt, t0 + 60)
    }

    func testSnapshotWithoutRateLimitsChangesNothing() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16), receivedAt: t0)

        state.absorb(UsageSnapshot(), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 16)
        XCTAssertEqual(state.updatedAt, t0)
    }

    func testOlderFileDoesNotMoveUpdatedAtBackwards() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16), receivedAt: t0)

        state.absorb(snapshot(fiveHour: 16), receivedAt: t0 - 600)

        XCTAssertEqual(state.updatedAt, t0)
    }

    func testRealFixtureFeedsState() throws {
        var state = UsageState()

        state.absorb(try StateFile.parse(Fixture.data()), receivedAt: t0)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 19)
        XCTAssertEqual(state.sevenDay?.usedPercentage, 50)
    }

    func testStateRoundTripsThroughCodable() throws {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16.5, sevenDay: 50), receivedAt: t0)

        let decoded = try JSONDecoder().decode(UsageState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded, state)
    }

    // MARK: - Consulta ao servidor

    private func reading(fiveHour: Double?, sevenDay: Double? = nil) -> RateLimits {
        RateLimits(fiveHour: fiveHour.map { UsageWindow(usedPercentage: $0, resetsAt: reset5h) },
                   sevenDay: sevenDay.map { UsageWindow(usedPercentage: $0, resetsAt: reset7d) })
    }

    /// O servidor é a referência: vale mesmo abaixo do que o bridge mostrou (ex.: reset de limite concedido).
    func testServerReadingReplacesEvenLowerValues() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 40, sevenDay: 60), receivedAt: t0)

        state.applyServerReading(reading(fiveHour: 0, sevenDay: 55), checkedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 0)
        XCTAssertEqual(state.sevenDay?.usedPercentage, 55)
        XCTAssertEqual(state.updatedAt, t0 + 60)
        XCTAssertEqual(state.serverCheckedAt, t0 + 60)
    }

    func testServerReadingWithoutWindowKeepsKnownValue() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16, sevenDay: 50), receivedAt: t0)

        state.applyServerReading(reading(fiveHour: nil, sevenDay: 52), checkedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 16)
        XCTAssertEqual(state.sevenDay?.usedPercentage, 52)
    }

    /// O timer relê o mesmo `state.json` a cada 30 s: ele não pode desfazer a leitura do servidor.
    func testPayloadWrittenBeforeServerReadingIsIgnored() {
        var state = UsageState()
        state.applyServerReading(reading(fiveHour: 0), checkedAt: t0 + 60)

        state.absorb(snapshot(fiveHour: 40), receivedAt: t0)
        state.absorb(snapshot(fiveHour: 40), receivedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 0)
        XCTAssertEqual(state.updatedAt, t0 + 60)
    }

    func testPayloadAfterServerReadingFollowsSessionRules() {
        var state = UsageState()
        state.applyServerReading(reading(fiveHour: 25), checkedAt: t0)

        state.absorb(snapshot(fiveHour: 5), receivedAt: t0 + 30)
        XCTAssertEqual(state.fiveHour?.usedPercentage, 25, "sessão parada continua ignorada")

        state.absorb(snapshot(fiveHour: 27), receivedAt: t0 + 60)
        XCTAssertEqual(state.fiveHour?.usedPercentage, 27)
        XCTAssertEqual(state.updatedAt, t0 + 60)
    }

    func testRealReportFeedsState() throws {
        var state = UsageState()
        state.absorb(try StateFile.parse(Fixture.data()), receivedAt: t0)

        state.applyServerReading(try UsageReport.parse(Data(contentsOf: UsageReportTests.fixtureURL)),
                                 checkedAt: t0 + 60)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 25)
        XCTAssertEqual(state.sevenDay?.usedPercentage, 56)
    }

    /// Cache gravado por uma versão sem `serverCheckedAt`.
    func testCacheFromPreviousVersionStillDecodes() throws {
        let old = Data(#"{"fiveHour":{"used_percentage":19,"resets_at":1792086600},"updatedAt":0}"#.utf8)

        let state = try JSONDecoder().decode(UsageState.self, from: old)

        XCTAssertEqual(state.fiveHour?.usedPercentage, 19)
        XCTAssertNil(state.serverCheckedAt)
    }

    func testServerStateRoundTripsThroughCodable() throws {
        var state = UsageState()
        state.applyServerReading(reading(fiveHour: 25.5, sevenDay: 56), checkedAt: t0)

        let decoded = try JSONDecoder().decode(UsageState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded, state)
    }

    // MARK: - Exibição

    func testStaleAfterOneHour() {
        var state = UsageState()
        state.absorb(snapshot(fiveHour: 16), receivedAt: t0)

        XCTAssertFalse(state.isStale(at: t0 + 3600))
        XCTAssertTrue(state.isStale(at: t0 + 3601))
    }

    func testWindowPastResetShowsZero() {
        let window = UsageWindow(usedPercentage: 80, resetsAt: reset5h)

        XCTAssertEqual(window.percentage(at: reset5h - 1), 80)
        XCTAssertEqual(window.percentage(at: reset5h), 0)
        XCTAssertTrue(window.hasReset(at: reset5h + 1))
    }

    func testLevelThresholds() {
        XCTAssertEqual(UsageLevel(percentage: 0), .normal)
        XCTAssertEqual(UsageLevel(percentage: 59), .normal)
        XCTAssertEqual(UsageLevel(percentage: 59.6), .warning, "arredonda como na tela: 60%")
        XCTAssertEqual(UsageLevel(percentage: 60), .warning)
        XCTAssertEqual(UsageLevel(percentage: 85), .warning)
        XCTAssertEqual(UsageLevel(percentage: 85.6), .critical)
        XCTAssertEqual(UsageLevel(percentage: 100), .critical)
    }
}
