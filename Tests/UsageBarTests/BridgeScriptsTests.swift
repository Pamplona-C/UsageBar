import XCTest

/// Roda os scripts de `scripts/` contra um diretório do Claude Code falso (`USAGEBAR_CLAUDE_DIR`).
final class BridgeScriptsTests: XCTestCase {
    private var claudeDir: URL!
    private var settings: URL { claudeDir.appendingPathComponent("settings.json") }
    private var bridge: URL { claudeDir.appendingPathComponent("usagebar-bridge.sh") }
    private var dataDir: URL { claudeDir.appendingPathComponent("usagebar") }

    private static let scriptsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts")

    /// Formato que o Claude Code grava: 2 espaços e quebra de linha no final.
    private let settingsWithStatusline = """
    {
      "model": "opus",
      "statusLine": {
        "type": "command",
        "command": "cat > /dev/null; echo ORIGINAL",
        "padding": 0
      },
      "enabledPlugins": {
        "exemplo@ç": true
      },
      "hooks": []
    }

    """

    override func setUpWithError() throws {
        claudeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageBarBridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dataDir.path)
        try? FileManager.default.removeItem(at: claudeDir)
    }

    // MARK: - Com statusline existente

    func testInstallChainsExistingStatuslineAndUninstallRestoresExactBytes() throws {
        try settingsWithStatusline.write(to: settings, atomically: true, encoding: .utf8)

        let install = try script("install-bridge.sh", "--yes")
        XCTAssertEqual(install.status, 0, install.stderr)
        XCTAssertEqual(try statusLine()?["command"] as? String, bridge.path)
        XCTAssertEqual(try statusLine()?["padding"] as? Int, 0, "outros campos do statusLine são mantidos")
        XCTAssertEqual(try backups().count, 1)

        let bridged = try runBridge(payload: Fixture.data())
        XCTAssertEqual(bridged.status, 0)
        XCTAssertEqual(bridged.stdout, "ORIGINAL\n", "repassa o stdout da statusline original")
        XCTAssertEqual(bridged.stderr, "")
        let state = try Data(contentsOf: dataDir.appendingPathComponent("state.json"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: state) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Fixture.data()) as? NSDictionary)

        let uninstall = try script("uninstall-bridge.sh", "--yes")
        XCTAssertEqual(uninstall.status, 0, uninstall.stderr)
        XCTAssertEqual(try String(contentsOf: settings), settingsWithStatusline)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.path))
    }

    func testInstallTwiceDoesNotDuplicateAnything() throws {
        try settingsWithStatusline.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertEqual(try script("install-bridge.sh", "--yes").status, 0)
        let afterFirst = try Data(contentsOf: settings)
        let originalSaved = try Data(contentsOf: dataDir.appendingPathComponent("original-command"))

        let second = try script("install-bridge.sh", "--yes")

        XCTAssertEqual(second.status, 0)
        XCTAssertTrue(second.stdout.contains("já está instalado"))
        XCTAssertEqual(try Data(contentsOf: settings), afterFirst)
        XCTAssertEqual(try Data(contentsOf: dataDir.appendingPathComponent("original-command")), originalSaved,
                       "a segunda instalação não pode guardar o próprio bridge como statusline original")
        XCTAssertEqual(try backups().count, 1)
        XCTAssertEqual(try runBridge(payload: Fixture.data()).stdout, "ORIGINAL\n")
    }

    func testUninstallTwiceIsNoOp() throws {
        try settingsWithStatusline.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertEqual(try script("install-bridge.sh", "--yes").status, 0)
        XCTAssertEqual(try script("uninstall-bridge.sh", "--yes").status, 0)

        let second = try script("uninstall-bridge.sh", "--yes")

        XCTAssertEqual(second.status, 0)
        XCTAssertTrue(second.stdout.contains("não aponta para o bridge"))
        XCTAssertEqual(try String(contentsOf: settings), settingsWithStatusline)
    }

    func testInstallWithoutConfirmationChangesNothing() throws {
        try settingsWithStatusline.write(to: settings, atomically: true, encoding: .utf8)

        let result = try script("install-bridge.sh", stdin: Data("n\n".utf8))

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(try String(contentsOf: settings), settingsWithStatusline)
        XCTAssertEqual(try backups().count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.path))
    }

    // MARK: - Sem statusline ou sem settings.json

    func testWithoutPreviousStatuslineBridgePrintsSimpleLineAndUninstallRemovesKey() throws {
        let original = "{\n  \"model\": \"opus\"\n}\n"
        try original.write(to: settings, atomically: true, encoding: .utf8)

        XCTAssertEqual(try script("install-bridge.sh", "--yes").status, 0)
        let bridged = try runBridge(payload: Fixture.data(), cwd: claudeDir)
        XCTAssertEqual(bridged.stdout, claudeDir.lastPathComponent + "\n")

        XCTAssertEqual(try script("uninstall-bridge.sh", "--yes").status, 0)
        XCTAssertEqual(try String(contentsOf: settings), original)
    }

    func testMissingSettingsFileIsCreatedAndRemovedOnUninstall() throws {
        XCTAssertEqual(try script("install-bridge.sh", "--yes").status, 0)
        XCTAssertEqual(try statusLine()?["command"] as? String, bridge.path)

        XCTAssertEqual(try script("uninstall-bridge.sh", "--yes").status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settings.path))
        XCTAssertEqual(try backups().count, 0)
    }

    // MARK: - Robustez do bridge

    func testBridgeIgnoresWriteFailuresAndStillPrintsOriginalStatusline() throws {
        try settingsWithStatusline.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertEqual(try script("install-bridge.sh", "--yes").status, 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dataDir.path)

        let bridged = try runBridge(payload: Fixture.data())

        XCTAssertEqual(bridged.status, 0)
        XCTAssertEqual(bridged.stdout, "ORIGINAL\n")
        XCTAssertEqual(bridged.stderr, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("state.json").path))
    }

    func testBridgeWithEmptyStdinKeepsPreviousState() throws {
        try settingsWithStatusline.write(to: settings, atomically: true, encoding: .utf8)
        XCTAssertEqual(try script("install-bridge.sh", "--yes").status, 0)
        XCTAssertEqual(try runBridge(payload: Fixture.data()).status, 0)

        let bridged = try runBridge(payload: Data())

        XCTAssertEqual(bridged.stdout, "ORIGINAL\n")
        let state = try Data(contentsOf: dataDir.appendingPathComponent("state.json"))
        XCTAssertFalse(state.isEmpty)
    }

    // MARK: - Ajudantes

    private struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func script(_ name: String, _ arguments: String..., stdin: Data = Data()) throws -> Result {
        try run("/bin/bash", [Self.scriptsDir.appendingPathComponent(name).path] + arguments, stdin: stdin)
    }

    /// Como o Claude Code: o `command` roda num shell, com o JSON no stdin.
    private func runBridge(payload: Data, cwd: URL? = nil) throws -> Result {
        try run("/bin/sh", ["-c", bridge.path], stdin: payload, cwd: cwd)
    }

    private func run(_ executable: String, _ arguments: [String], stdin: Data, cwd: URL? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["USAGEBAR_CLAUDE_DIR": claudeDir.path]) { $1 }
        if let cwd { process.currentDirectoryURL = cwd }
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        input.fileHandleForWriting.write(stdin)
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      stdout: String(decoding: out, as: UTF8.self),
                      stderr: String(decoding: err, as: UTF8.self))
    }

    private func statusLine() throws -> [String: Any]? {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
        return json?["statusLine"] as? [String: Any]
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: claudeDir.path)
            .filter { $0.hasPrefix("settings.json.bak-") }
    }
}
