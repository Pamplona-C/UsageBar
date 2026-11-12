import XCTest
@testable import UsageBar

final class CodexUsageClientTests: XCTestCase {
    private var directory: URL!
    private var recording: URL { directory.appendingPathComponent("requests.jsonl") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageBarCodex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testHandshakeReadsOnlyAccountAndLimitsWithoutStartingConversations() throws {
        let executable = try fakeCodex()
        let result = CodexUsageClient.run(executable)
        guard case .success(let report) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(report.primary?.usedPercent, 25)
        let requests = try recordedRequests()
        XCTAssertEqual(requests.compactMap { $0["method"] as? String },
                       ["initialize", "initialized", "account/read", "account/rateLimits/read"])
        XCTAssertEqual((requests[0]["params"] as? [String: Any])?["clientInfo"] as? [String: String],
                       ["name": "usagebar", "title": "UsageBar", "version": "0.1.0"])
        XCTAssertEqual((requests[2]["params"] as? [String: Any])?["refreshToken"] as? Bool, false)
    }

    func testLoggedOutDoesNotRequestLimits() throws {
        XCTAssertEqual(CodexUsageClient.run(try fakeCodex(account: NSNull())), .failure(.notLoggedIn))
        XCTAssertEqual(try recordedRequests().count, 3)
    }

    func testAPIKeyLoginOffersChatGPTLoginWithoutRequestingLimits() throws {
        XCTAssertEqual(CodexUsageClient.run(try fakeCodex(account: ["type": "apiKey"])), .failure(.unsupportedLogin))
        XCTAssertEqual(try recordedRequests().count, 3)
        XCTAssertTrue(CodexUsageError.unsupportedLogin.offersLogin)
    }

    func testUnsupportedMethodHasActionableVersionError() throws {
        XCTAssertEqual(CodexUsageClient.run(try fakeCodex(mode: "unsupported")), .failure(.unsupportedVersion))
    }

    func testTimeoutIsBoundedEvenWhenProcessIgnoresTermination() throws {
        let executable = try fakeCodex(mode: "timeout")
        let start = Date()
        XCTAssertEqual(CodexUsageClient.run(executable, timeout: 0.2), .failure(.timedOut))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testNonJSONLogsAndNotificationsDoNotBreakTheResponse() throws {
        guard case .success = CodexUsageClient.run(try fakeCodex(mode: "logs")) else { return XCTFail() }
    }

    func testEarlyExitDoesNotHang() throws {
        let result = CodexUsageClient.run(try fakeCodex(mode: "exit"), timeout: 1)
        guard case .failure(.failed) = result else { return XCTFail("\(result)") }
    }

    func testMissingExecutableReportsLaunchFailure() {
        guard case .failure(.failed) = CodexUsageClient.run(directory.appendingPathComponent("missing")) else { return XCTFail() }
    }

    func testLocatorSkipsNonExecutableFiles() throws {
        let invalid = directory.appendingPathComponent("not-executable")
        try Data().write(to: invalid)
        let executable = try fakeCodex()
        XCTAssertEqual(CodexUsageClient.locateCodex(candidates: [invalid, executable]), executable)
        XCTAssertNil(CodexUsageClient.locateCodex(candidates: [invalid]))
    }

    private func recordedRequests() throws -> [[String: Any]] {
        try String(contentsOf: recording).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    private func fakeCodex(account: Any = ["type": "chatgpt", "planType": "plus"], mode: String = "normal") throws -> URL {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: CodexUsageReportTests.fixtureURL))
        let config: [String: Any] = ["account": account, "mode": mode, "fixture": fixture, "recording": recording.path]
        let encoded = try JSONSerialization.data(withJSONObject: config).base64EncodedString()
        let text = """
        #!/usr/bin/python3
        import base64, json, signal, sys, time
        config = json.loads(base64.b64decode("\(encoded)"))
        initialized = False
        for line in sys.stdin:
            request = json.loads(line)
            with open(config['recording'], 'a') as output:
                output.write(json.dumps(request) + '\\n')
            method = request['method']
            if method == 'initialize':
                if config['mode'] == 'timeout':
                    signal.signal(signal.SIGTERM, signal.SIG_IGN)
                    time.sleep(30)
                if config['mode'] == 'exit':
                    sys.exit(0)
                if config['mode'] == 'logs':
                    print('A non-JSON log', flush=True)
                    print(json.dumps({'method': 'account/updated', 'params': {}}), flush=True)
                result = {}
            elif method == 'initialized':
                initialized = True
                continue
            elif not initialized:
                print(json.dumps({'id': request['id'], 'error': {'code': -1, 'message': 'Not initialized'}}), flush=True)
                continue
            elif method == 'account/read':
                result = {'account': config['account'], 'requiresOpenaiAuth': True}
            elif method == 'account/rateLimits/read':
                if config['mode'] == 'unsupported':
                    print(json.dumps({'id': request['id'], 'error': {'code': -32601, 'message': 'Method not found'}}), flush=True)
                    continue
                result = config['fixture']
            else:
                sys.exit(2)
            print(json.dumps({'id': request['id'], 'result': result}), flush=True)
        """
        let executable = directory.appendingPathComponent("codex")
        try text.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
