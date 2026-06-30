import Foundation

/// Reads OpenAI Codex CLI sessions from
/// `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`.
///
/// Each line is a record tagged with a top-level `type`: `session_meta`,
/// `turn_context`, `response_item` (the model's output items), or `event_msg`
/// (runtime events). The canonical conversation lives in `response_item`; the
/// duplicated `agent_message` / `user_message` runtime events are skipped.
struct CodexProvider: Provider {
    let kind = ProviderKind.codex
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var sessionsRoot: URL {
        home.appending(path: ".codex/sessions")
    }

    func discover() throws -> [SessionRef] {
        FileWalk.files(under: sessionsRoot) {
            $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl")
        }.map { file in
            SessionRef(
                provider: kind,
                sessionID: Self.id(fromFilename: file.url.lastPathComponent),
                path: file.url,
                modifiedAt: file.modified
            )
        }
    }

    /// `rollout-2026-06-27T00-00-50-<uuid>.jsonl` → `<uuid>` (last five
    /// dash-separated groups). Refined from `session_meta` during `parse`.
    static func id(fromFilename name: String) -> String {
        let stem = name.replacingOccurrences(of: ".jsonl", with: "")
        let parts = stem.split(separator: "-")
        return parts.count >= 5 ? parts.suffix(5).joined(separator: "-") : stem
    }

    func parse(_ ref: SessionRef) throws -> Session {
        var session = Session(
            provider: kind, id: ref.sessionID, cwd: nil, gitBranch: nil,
            model: nil, cliVersion: nil, startedAt: nil, events: [])

        try JSONL.forEachLine(in: ref.path) { line in
            let ts = Timestamps.parse(line["timestamp"]?.string)
            let payload = line["payload"]
            switch line["type"]?.string {
            case "session_meta":
                applyMeta(payload, ts: ts, to: &session)
            case "turn_context":
                if let model = payload?["model"]?.string {
                    var m = session.model ?? ModelInfo()
                    m.name = m.name ?? model
                    session.model = m
                }
            case "response_item":
                if let event = Self.parseResponseItem(payload, ts: ts) {
                    session.events.append(event)
                }
            case "event_msg":
                if let event = Self.parseEventMsg(payload, ts: ts) {
                    session.events.append(event)
                }
            default:
                break
            }
        }
        return session
    }

    private func applyMeta(_ payload: JSONValue?, ts: Date?, to session: inout Session) {
        guard let p = payload else { return }
        session.id = p["id"]?.string ?? session.id
        session.cwd = p["cwd"]?.string ?? session.cwd
        session.cliVersion = p["cli_version"]?.string ?? session.cliVersion
        session.startedAt = session.startedAt ?? ts
        if let providerName = p["model_provider"]?.string {
            session.model = ModelInfo(provider: providerName, name: session.model?.name)
        }
    }

    private static func parseResponseItem(_ payload: JSONValue?, ts: Date?) -> Event? {
        guard let p = payload, let itemType = p["type"]?.string else { return nil }
        switch itemType {
        case "message":
            let message = Message(role: Role(token: p["role"]?.string),
                                  text: Normalize.text(p["content"]))
            return Event(timestamp: ts, payload: .message(message))
        case "reasoning":
            // Summary is plain text; `content` is usually encrypted/absent.
            let text = Normalize.text(p["summary"])
            return Event(timestamp: ts, payload: .reasoning(Reasoning(text: text)))
        case "function_call", "custom_tool_call":
            let call = ToolCall(
                id: p["call_id"]?.string,
                name: p["name"]?.string ?? "unknown",
                arguments: p["arguments"]?.string ?? p["input"]?.jsonString ?? "")
            return Event(timestamp: ts, payload: .toolCall(call))
        case "function_call_output", "custom_tool_call_output":
            let output = p["output"]?.string ?? Normalize.text(p["output"])
            let result = Normalize.toolResult(callID: p["call_id"]?.string, output: output)
            return Event(timestamp: ts, payload: .toolResult(result))
        default:
            return nil
        }
    }

    private static func parseEventMsg(_ payload: JSONValue?, ts: Date?) -> Event? {
        guard let p = payload, let msgType = p["type"]?.string else { return nil }
        switch msgType {
        case "task_started":
            return Event(timestamp: ts, payload: .lifecycle(.taskStarted))
        case "task_complete":
            return Event(timestamp: ts, payload: .lifecycle(.taskCompleted))
        case "patch_apply_end":
            return Event(timestamp: ts, payload: .lifecycle(.patchApplied))
        case "token_count":
            return parseTokenCount(p).map { Event(timestamp: ts, payload: .tokenUsage($0)) }
        default:
            // agent_message / user_message duplicate `response_item` messages.
            return nil
        }
    }

    private static func parseTokenCount(_ p: JSONValue) -> TokenUsage? {
        let info = p["info"]
        // `last_token_usage` is the most recent request's usage (per-turn, so it
        // sums sensibly); `total_token_usage.total_tokens` is the cumulative
        // context size, surfaced as `totalTokens`.
        guard let last = info?["last_token_usage"] ?? info?["total_token_usage"] else {
            return nil
        }
        return TokenUsage(
            inputTokens: last["input_tokens"]?.int,
            outputTokens: last["output_tokens"]?.int,
            cachedInputTokens: last["cached_input_tokens"]?.int,
            totalTokens: info?["total_token_usage"]?["total_tokens"]?.int
                ?? last["total_tokens"]?.int)
    }
}
