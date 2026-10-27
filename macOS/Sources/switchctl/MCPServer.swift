import AgentControlProtocol
import Foundation

/// MCP over stdio: newline-delimited JSON-RPC 2.0. Logs go to stderr only.
struct MCPServer {
    let commands: Commands
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let snapshotWidth = 960

    struct RPCError: Error { let code: Int; let message: String }

    static var tools: [[String: Any]] {
        let buttons: [String: Any] = ["type": "array", "items": ["type": "string", "enum": AgentProtocol.buttons], "uniqueItems": true]
        let hold: [String: Any] = ["type": "integer", "minimum": AgentProtocol.holdRange.lowerBound, "maximum": AgentProtocol.holdRange.upperBound, "default": 100,
                                   "description": "How long to hold, in ms. A new call replaces the current hold without releasing in between."]
        let gap: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 60_000, "default": 60, "description": "Extra wait after the hold ends, in ms."]
        let wait: [String: Any] = ["type": "boolean", "default": true, "description": "Wait for hold + gap before returning. Set false to chain inputs (continuous movement)."]
        func axis(_ text: String) -> [String: Any] { ["type": "number", "minimum": -1, "maximum": 1, "default": 0, "description": text] }
        func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            ["name": name, "description": description,
             "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false] as [String: Any]]
        }
        return [
            tool("switch_status", "Read switch-remote state: capture running and frame age, Pi/Switch link, transport, input RTT, current agent hold."),
            tool("switch_snapshot", "Capture the current Nintendo Switch screen (raw capture-card frame, before effects) as a PNG image.",
                 ["maxWidth": ["type": "integer", "minimum": AgentProtocol.snapshotWidthRange.lowerBound, "maximum": AgentProtocol.snapshotWidthRange.upperBound, "default": snapshotWidth] as [String: Any]]),
            tool("switch_press", "Press buttons together on the Switch controller, hold for holdMs, then release.",
                 ["buttons": buttons.merging(["minItems": 1]) { $1 }, "holdMs": hold, "gapMs": gap, "wait": wait], required: ["buttons"]),
            tool("switch_input", "Send buttons and stick positions (ly/ry positive is up) held for holdMs, then neutral.",
                 ["buttons": buttons, "lx": axis("Left stick X"), "ly": axis("Left stick Y"), "rx": axis("Right stick X"), "ry": axis("Right stick Y"),
                  "holdMs": hold, "gapMs": gap, "wait": wait]),
            tool("switch_release", "Release every agent-held button and stick now.")
        ]
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = handle(line) { FileHandle.standardOutput.write(AgentJSON.line(response)) }
        }
    }

    /// Returns nil for notifications.
    func handle(_ line: String) -> [String: Any]? {
        guard let message = AgentJSON.object(Data(line.utf8)) else { return error(id: nil, RPCError(code: -32700, message: "parse error")) }
        let id = message["id"]
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            return id == nil ? nil : error(id: id, RPCError(code: -32600, message: "invalid request"))
        }
        guard let id else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        do {
            let result: [String: Any]
            switch method {
            case "initialize":
                let requested = params["protocolVersion"] as? String ?? ""
                result = ["protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0],
                          "capabilities": ["tools": ["listChanged": false]],
                          "serverInfo": ["name": "switchctl", "version": "1.0.0"]]
            case "ping": result = [:]
            case "tools/list": result = ["tools": Self.tools]
            case "tools/call": result = try call(params)
            default: throw RPCError(code: -32601, message: "method not found: \(method)")
            }
            return ["jsonrpc": "2.0", "id": id, "result": result]
        } catch let rpc as RPCError {
            return error(id: id, rpc)
        } catch {
            return self.error(id: id, RPCError(code: -32603, message: "\(error)"))
        }
    }

    private func error(id: Any?, _ error: RPCError) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": error.code, "message": error.message]]
    }

    private func text(_ object: [String: Any], isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": AgentJSON.string(object)]], "isError": isError]
    }

    private func call(_ params: [String: Any]) throws -> [String: Any] {
        guard let name = params["name"] as? String else { throw RPCError(code: -32602, message: "missing tool name") }
        let rawArguments = params["arguments"] ?? [String: Any]()
        guard let arguments = rawArguments as? [String: Any] else { throw RPCError(code: -32602, message: "arguments must be an object") }
        func allow(_ keys: Set<String>) throws {
            if let extra = arguments.keys.first(where: { !keys.contains($0) }) { throw RPCError(code: -32602, message: "unknown argument \(extra)") }
        }
        func integer(_ key: String, default value: Int, range: ClosedRange<Int>) throws -> Int {
            guard let raw = arguments[key] else { return value }
            guard let parsed = AgentJSON.integer(raw), range.contains(parsed) else { throw RPCError(code: -32602, message: "\(key) must be an integer in \(range.lowerBound)...\(range.upperBound)") }
            return parsed
        }
        func flag(_ key: String) throws -> Bool {
            guard let raw = arguments[key] else { return true }
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw RPCError(code: -32602, message: "\(key) must be a boolean") }
            return number.boolValue
        }
        let outcome: Outcome
        switch name {
        case "switch_status":
            try allow([]); outcome = commands.status()
        case "switch_release":
            try allow([]); outcome = commands.release()
        case "switch_snapshot":
            try allow(["maxWidth"])
            let width = try integer("maxWidth", default: Self.snapshotWidth, range: AgentProtocol.snapshotWidthRange)
            outcome = commands.snapshot(maxWidth: width, out: nil)
            if outcome.ok, let result = outcome.result, let path = result["path"] as? String {
                guard let png = FileManager.default.contents(atPath: path) else { return text(["error": "cannot read snapshot file"], isError: true) }
                return ["content": [["type": "image", "mimeType": "image/png", "data": png.base64EncodedString()],
                                    ["type": "text", "text": AgentJSON.string(result)]], "isError": false]
            }
        case "switch_press", "switch_input":
            let press = name == "switch_press"
            try allow(press ? ["buttons", "holdMs", "gapMs", "wait"] : ["buttons", "lx", "ly", "rx", "ry", "holdMs", "gapMs", "wait"])
            if press { guard let buttons = arguments["buttons"] as? [Any], !buttons.isEmpty else { throw RPCError(code: -32602, message: "buttons must be a non-empty array") } }
            let parsed: AgentInputArgs
            do { parsed = try AgentInputArgs.parse(arguments.filter { ["buttons", "lx", "ly", "rx", "ry", "holdMs"].contains($0.key) }) }
            catch let error as AgentError { throw RPCError(code: -32602, message: error.message) }
            let gap = try integer("gapMs", default: 60, range: 0...60_000)
            outcome = commands.input(parsed, gapMs: gap, wait: try flag("wait"))
        default:
            throw RPCError(code: -32602, message: "unknown tool \(name)")
        }
        return outcome.ok ? text(outcome.result ?? [:], isError: false) : text(outcome.json, isError: true)
    }
}
