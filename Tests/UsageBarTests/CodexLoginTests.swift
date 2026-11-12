import XCTest
@testable import UsageBar

final class CodexLoginTests: XCTestCase {
    func testLoginUsesCodexCommandAndQuotesPathsWithoutReadingCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBar Codex's-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        let output = directory.appendingPathComponent("args")
        let fake = "#!/bin/bash\nprintf '%s\\n' \"$@\" > \"${0%/*}/args\"\n"
        try fake.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let text = CodexLogin.script(codex: executable)
        let script = directory.appendingPathComponent("login.command")
        try text.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: output), "login\n")
        XCTAssertTrue(text.contains("export PATH="), "o node ao lado do codex precisa estar no PATH, inclusive via Finder")
        XCTAssertFalse(text.contains("auth.json"))
        XCTAssertFalse(text.contains("security find"))
    }
}
