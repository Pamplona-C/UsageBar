import XCTest
@testable import UsageBar

final class ClaudeLoginTests: XCTestCase {
    func testScriptRunsDocumentedLoginCommand() {
        let script = ClaudeLogin.script(claude: URL(fileURLWithPath: "/Users/usuario/.local/bin/claude"))

        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(script.contains("\n'/Users/usuario/.local/bin/claude' auth login\n"))
    }

    func testScriptQuotesPathWithSpacesAndApostrophes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageBar Login's-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("saida")
        // `claude` falso que grava os argumentos, num caminho com espaço e apóstrofo.
        let claude = directory.appendingPathComponent("claude")
        try "#!/bin/bash\nprintf '%s\\n' \"$@\" > \"\(output.path)\"\n".write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        let script = directory.appendingPathComponent("login.command")
        try ClaudeLogin.script(claude: claude).write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "auth\nlogin\n")
    }
}
