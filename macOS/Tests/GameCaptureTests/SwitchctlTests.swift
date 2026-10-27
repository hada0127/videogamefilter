import XCTest
import AgentControlProtocol
@testable import GameCapture

/// Runs the built `switchctl` binary against the real socket server with a fake host.
final class SwitchctlTests: XCTestCase {
    private var root: URL!
    private var socketPath: String { root.appendingPathComponent("agent.sock").path }
    private var binary: URL { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("switchctl") }

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sc-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), binary.path)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func start(_ fake: FakeAgentHost) throws -> AgentControlServer {
        let server = AgentControlServer(socketPath: socketPath, snapshotDirectory: root.appendingPathComponent("snapshots"), host: fake.host, hostQueue: fake.queue)
        try server.start()
        return server
    }

    private func run(_ arguments: [String], stdin: String? = nil) throws -> (code: Int32, lines: [[String: Any]], seconds: Double) {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--socket", socketPath] + arguments
        let output = Pipe(), input = Pipe()
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = input
        let started = Date()
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = data.split(separator: 10).map { AgentJSON.object(Data($0)) ?? ["unparsed": String(decoding: $0, as: UTF8.self)] }
        return (process.terminationStatus, lines, Date().timeIntervalSince(started))
    }

    func testExitCodes() throws {
        let missing = try run(["status"])
        XCTAssertEqual(missing.code, 3); XCTAssertEqual(missing.lines.count, 1)
        XCTAssertEqual(try run(["bogus"]).code, 2)
        XCTAssertEqual(try run(["press"]).code, 2)
        XCTAssertEqual(try run(["press", "TURBO"]).code, 2)
        XCTAssertEqual(try run(["input", "--lx", "2"]).code, 2)
        XCTAssertEqual(try run(["input", "--hold-ms", "60001"]).code, 2)
        XCTAssertEqual(try run(["snapshot", "--max-width", "10"]).code, 2)

        let fake = FakeAgentHost(); fake.frame = AgentControlServerTests.bgra(width: 1280, height: 720)
        let server = try start(fake); defer { server.stop() }
        let status = try run(["status"])
        XCTAssertEqual(status.code, 0); XCTAssertEqual(status.lines.count, 1)
        XCTAssertEqual(status.lines[0]["ok"] as? Bool, true)
        XCTAssertEqual(try run(["release"]).code, 0)
        let out = root.appendingPathComponent("copy.png").path
        let snapshot = try run(["snapshot", "--max-width", "320", "--out", out])
        XCTAssertEqual(snapshot.code, 0)
        XCTAssertEqual((snapshot.lines[0]["result"] as? [String: Any])?["out"] as? String, out)
        XCTAssertNotNil(NSImage(contentsOfFile: out))

        fake.lock.lock(); fake.connected = false; fake.lock.unlock()
        let refused = try run(["press", "B", "--no-wait"])
        XCTAssertEqual(refused.code, 4)
        XCTAssertEqual((refused.lines[0]["error"] as? [String: Any])?["code"] as? String, "not_connected")
    }

    func testPressWaitsForHoldPlusGapAndNoWaitChains() throws {
        let fake = FakeAgentHost()
        let server = try start(fake); defer { server.stop() }
        let press = try run(["press", "dpad_right,B", "--hold-ms", "150", "--gap-ms", "60"])
        XCTAssertEqual(press.code, 0)
        XCTAssertGreaterThanOrEqual(press.seconds, 0.21)
        XCTAssertEqual(fake.inputs.last, AgentInputArgs(buttons: ["DPAD_RIGHT", "B"], holdMs: 150))

        let chained = try run(["input", "--lx", "1", "--hold-ms", "60000", "--no-wait"])
        XCTAssertEqual(chained.code, 0)
        XCTAssertLessThan(chained.seconds, 5)
        XCTAssertEqual(fake.inputs.last, AgentInputArgs(lx: 1, holdMs: 60_000))
    }

    func testMCPRoundTrip() throws {
        let fake = FakeAgentHost(); fake.frame = AgentControlServerTests.bgra(width: 1920, height: 1080)
        let server = try start(fake); defer { server.stop() }
        let script = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"switch_snapshot","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"switch_press","arguments":{"buttons":["HOME"],"holdMs":20,"gapMs":0}}}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"switch_input","arguments":{"lx":2}}}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"no_such_tool"}}"#,
            #"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":8,"method":"ping"}"#,
            #"{"jsonrpc":"2.0","id":9,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#,
            "not json"
        ].joined(separator: "\n") + "\n"
        let result = try run(["mcp"], stdin: script)
        XCTAssertEqual(result.code, 0)
        var byID: [Int: [String: Any]] = [:]
        for line in result.lines { if let id = line["id"] as? Int { byID[id] = line } }
        XCTAssertEqual(result.lines.count, 10) // notification gets no reply; parse error gets id null

        XCTAssertEqual((byID[1]?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        let tools = ((byID[2]?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(tools, ["switch_status", "switch_snapshot", "switch_press", "switch_input", "switch_release"])

        let snapshot = try XCTUnwrap(byID[3]?["result"] as? [String: Any])
        XCTAssertEqual(snapshot["isError"] as? Bool, false)
        let content = try XCTUnwrap(snapshot["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "image")
        XCTAssertEqual(content.first?["mimeType"] as? String, "image/png")
        let png = try XCTUnwrap(Data(base64Encoded: content.first?["data"] as? String ?? ""))
        let image = try XCTUnwrap(NSImage(data: png)?.representations.first)
        XCTAssertEqual(image.pixelsWide, 960); XCTAssertEqual(image.pixelsHigh, 540)
        XCTAssertEqual(content.last?["type"] as? String, "text")

        XCTAssertEqual((byID[4]?["result"] as? [String: Any])?["isError"] as? Bool, false)
        XCTAssertEqual(fake.inputs.last, AgentInputArgs(buttons: ["HOME"], holdMs: 20))
        XCTAssertEqual((byID[5]?["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertEqual((byID[6]?["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertEqual((byID[7]?["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertNotNil(byID[8]?["result"] as? [String: Any])
        XCTAssertEqual((byID[9]?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertTrue(result.lines.contains { ($0["error"] as? [String: Any])?["code"] as? Int == -32700 })

        fake.lock.lock(); fake.connected = false; fake.lock.unlock()
        let refused = try run(["mcp"], stdin: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"switch_press","arguments":{"buttons":["B"],"wait":false}}}"# + "\n")
        XCTAssertEqual((refused.lines.first?["result"] as? [String: Any])?["isError"] as? Bool, true)
    }
}
