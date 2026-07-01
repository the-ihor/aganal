import Foundation

/// Reads Cursor agent transcripts from
/// `~/.cursor/projects/<encoded-cwd>/agent-transcripts/<uuid>/<uuid>.jsonl`.
///
/// Cursor's canonical chat store is SQLite; this reads its secondary JSONL
/// agent-transcript artifact. Each line is either a message —
/// `{role: "user"|"assistant", message: {content: [blocks]}}` with `text` and
/// `tool_use` blocks (Anthropic-shaped) — or a `{type: "turn_ended", status}`
/// marker. Lines carry no timestamps, so events are ordered but untimed.
struct CursorProvider: Provider {
    let kind = ProviderKind.cursor
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var sessionsRoot: URL {
        home.appending(path: ".cursor/projects")
    }

    func discover(in root: URL) throws -> [SessionRef] {
        FileWalk.files(under: root) { $0.hasSuffix(".jsonl") }
            .filter { $0.url.pathComponents.contains("agent-transcripts") }
            .map { file in
                SessionRef(
                    provider: kind,
                    sessionID: file.url.deletingPathExtension().lastPathComponent,
                    path: file.url,
                    modifiedAt: file.modified)
            }
    }

    func previewTitle(_ ref: SessionRef) -> String? {
        var prompt: String?
        JSONL.scanHead(in: ref.path) { line in
            guard prompt == nil, line["role"]?.string == "user" else { return false }
            let text = (line["message"]?["content"]?.array ?? [])
                .compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }
                .joined(separator: " ")
            prompt = SessionTitle.clean(Self.unwrap(text))
            return prompt != nil
        }
        return prompt
    }

    /// Cursor wraps prompts as `<timestamp>…</timestamp> <user_query>…</user_query>`;
    /// drop the timestamp preamble and the query tags for a clean title.
    private static func unwrap(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: "<timestamp>.*?</timestamp>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</?user_query>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parse(_ ref: SessionRef) throws -> Session {
        var session = Session(
            provider: kind, id: ref.sessionID, cwd: nil, gitBranch: nil,
            model: nil, cliVersion: nil, startedAt: nil, events: [])

        try JSONL.forEachLine(in: ref.path) { line in
            switch line["role"]?.string {
            case "user":
                Self.appendBlocks(line["message"], role: .user, into: &session)
            case "assistant":
                Self.appendBlocks(line["message"], role: .assistant, into: &session)
            default:
                break   // turn_ended and other control markers carry no content
            }
        }
        return session
    }

    private static func appendBlocks(_ message: JSONValue?, role: Role, into session: inout Session) {
        for block in message?["content"]?.array ?? [] {
            switch block["type"]?.string {
            case "text":
                let text = block["text"]?.string ?? ""
                session.events.append(Event(
                    timestamp: nil, payload: .message(Message(role: role, text: text))))
            case "thinking":
                session.events.append(Event(
                    timestamp: nil,
                    payload: .reasoning(Reasoning(text: block["thinking"]?.string ?? ""))))
            case "tool_use":
                let call = ToolCall(
                    id: block["id"]?.string,
                    name: block["name"]?.string ?? "unknown",
                    arguments: block["input"]?.jsonString ?? "")
                session.events.append(Event(timestamp: nil, payload: .toolCall(call)))
            case "tool_result":
                let result = Normalize.toolResult(
                    callID: block["tool_use_id"]?.string,
                    output: Normalize.text(block["content"]),
                    isError: block["is_error"]?.bool ?? false)
                session.events.append(Event(timestamp: nil, payload: .toolResult(result)))
            default:
                break
            }
        }
    }
}
