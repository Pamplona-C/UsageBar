import XCTest
@testable import UsageBar

final class TranscriptScannerTests: XCTestCase {
    private var root: URL!
    private let since = Date(timeIntervalSince1970: 1_793_232_000) // 2026-10-29 00:00:00 UTC
    private var everything: (Date, Date) { (since, since.addingTimeInterval(86_400)) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBarScanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Linha de histórico com 10 tokens no total e `written` escritos.
    private func line(_ id: String, at time: String = "2026-10-29T12:00:00.000Z", written: Int = 1) -> String {
        #"{"timestamp":"\#(time)","requestId":"r","message":{"id":"\#(id)","model":"m","usage":{"input_tokens":\#(10 - written),"output_tokens":\#(written)}}}"#
    }

    @discardableResult
    private func write(_ text: String, to path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func total(_ scanner: TranscriptScanner) throws -> TokenCount {
        try scanner.scan(since: since).sum(from: everything.0, to: everything.1)
    }

    func testReadsSessionAndSubagentFiles() throws {
        try write(line("a") + "\n", to: "proj/sessao.jsonl")
        try write(line("b") + "\n", to: "proj/sessao/subagents/agent-1.jsonl")
        XCTAssertEqual(try total(TranscriptScanner(root: root)), TokenCount(total: 20, written: 2))
    }

    func testSecondScanReadsOnlyAppendedLines() throws {
        let url = try write(line("a") + "\n", to: "proj/sessao.jsonl")
        let scanner = TranscriptScanner(root: root)
        XCTAssertEqual(try total(scanner), TokenCount(total: 10, written: 1))
        try append(line("b", written: 3) + "\n", to: url)
        XCTAssertEqual(try total(scanner), TokenCount(total: 20, written: 4))
    }

    func testPartialLastLineIsReadNextTime() throws {
        let full = line("a")
        let cut = full.index(full.startIndex, offsetBy: 40)
        let url = try write(String(full[..<cut]), to: "proj/sessao.jsonl")
        let scanner = TranscriptScanner(root: root)
        XCTAssertEqual(try total(scanner), .zero)
        try append(String(full[cut...]) + "\n", to: url)
        XCTAssertEqual(try total(scanner), TokenCount(total: 10, written: 1))
        XCTAssertEqual(try total(scanner), TokenCount(total: 10, written: 1))
    }

    func testTruncatedFileIsReadAgainWithoutDoubleCount() throws {
        let url = try write(line("a") + "\n" + line("b") + "\n", to: "proj/sessao.jsonl")
        let scanner = TranscriptScanner(root: root)
        XCTAssertEqual(try total(scanner), TokenCount(total: 20, written: 2))
        // Mesmo arquivo reescrito menor, com uma resposta já contada.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data((line("a") + "\n").utf8))
        try handle.close()
        XCTAssertEqual(try total(scanner), TokenCount(total: 20, written: 2))
    }

    func testFilesModifiedBeforeSinceAreSkipped() throws {
        let url = try write(line("a") + "\n", to: "proj/antigo.jsonl")
        try FileManager.default.setAttributes([.modificationDate: since.addingTimeInterval(-3600)], ofItemAtPath: url.path)
        XCTAssertEqual(try total(TranscriptScanner(root: root)), .zero)
    }

    func testMissingRootReturnsEmpty() throws {
        let scanner = TranscriptScanner(root: root.appendingPathComponent("nao-existe"))
        XCTAssertTrue(try scanner.scan(since: since).isEmpty)
    }
}
