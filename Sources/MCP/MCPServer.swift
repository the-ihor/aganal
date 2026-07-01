import Foundation

/// A minimal Model Context Protocol server for AGANAL, spoken over stdio as
/// newline-delimited JSON-RPC 2.0. Started with `AGANAL mcp`; it reuses the
/// providers/model/analysis directly and never touches SwiftUI.
///
/// Exposes six tools (list_sources, list_sessions, search_sessions,
/// session_analytics, session_events, overview) and a session resource
/// (`aganal://session/<path>`), so an AI can find a session and analyze it.
struct MCPServer {
    static let protocolVersion = "2024-11-05"

    func run() {
        log("AGANAL MCP server ready (stdio).")
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("Ignoring non-JSON line.")
                continue
            }
            handle(message)
        }
    }

    // MARK: - Dispatch

    private func handle(_ message: [String: Any]) {
        let id = message["id"]                       // absent for notifications
        let method = message.str("method") ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let version = params.str("protocolVersion") ?? Self.protocolVersion
            reply(id, result: [
                "protocolVersion": version,
                "capabilities": ["tools": [:] as [String: Any], "resources": [:] as [String: Any]],
                "serverInfo": ["name": "aganal", "version": "0.1"],
            ])

        case "notifications/initialized", "initialized", "notifications/cancelled":
            break                                    // notifications: no response

        case "ping":
            reply(id, result: [:])

        case "tools/list":
            reply(id, result: ["tools": MCPTools.definitions])

        case "tools/call":
            let name = params.str("name") ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let output = try MCPTools.call(name, args)
                reply(id, result: ["content": [["type": "text", "text": jsonText(output)]]])
            } catch {
                reply(id, result: [
                    "content": [["type": "text", "text": "Error: \(error)"]],
                    "isError": true,
                ])
            }

        case "resources/list":
            reply(id, result: ["resources": [] as [Any]])

        case "resources/templates/list":
            reply(id, result: ["resourceTemplates": [[
                "uriTemplate": "aganal://session/{path}",
                "name": "AGANAL session file",
                "description": "The raw session log (JSONL) at the given absolute file path.",
                "mimeType": "application/x-ndjson",
            ]]])

        case "resources/read":
            do { reply(id, result: try MCPTools.readSessionResource(uri: params.str("uri") ?? "")) }
            catch { reply(id, error: -32002, message: "\(error)") }

        default:
            if id != nil { reply(id, error: -32601, message: "Method not found: \(method)") }
        }
    }

    // MARK: - Wire format

    private func reply(_ id: Any?, result: [String: Any]) {
        var response: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { response["id"] = id }
        write(response)
    }

    private func reply(_ id: Any?, error code: Int, message: String) {
        var response: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        response["id"] = id ?? NSNull()
        write(response)
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))   // newline-delimited
    }

    /// Tool payloads are returned as a pretty-printed JSON string inside a text
    /// content block, so the model reads structured, readable data.
    private func jsonText(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data(("[aganal-mcp] " + message + "\n").utf8))
    }
}
