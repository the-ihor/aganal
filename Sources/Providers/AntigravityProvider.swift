import Foundation

/// Reads Google Antigravity sessions from its per-session transcript at
/// `~/.gemini/antigravity-cli/brain/<sessionUUID>/.system_generated/logs/transcript.jsonl`.
///
/// Each line is an event tagged with `type`, plus `created_at`, `content`, and
/// (on planner turns) `tool_calls`:
/// - `USER_INPUT` → the human turn (wrapped in `<USER_REQUEST>` tags);
/// - `PLANNER_RESPONSE` → the model turn, with `tool_calls: [{name, args}]`;
/// - other action types (`VIEW_FILE`, `LIST_DIRECTORY`, `RUN_COMMAND`, …) →
///   tool executions, surfaced as tool results;
/// - `CHECKPOINT` / `CONVERSATION_HISTORY` are bookkeeping and skipped.
struct AntigravityProvider: Provider {
    let kind = ProviderKind.antigravity
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var sessionsRoot: URL { home.appending(path: ".gemini/antigravity-cli/brain") }

    func discover(in root: URL) throws -> [SessionRef] {
        // Transcripts live under a hidden `.system_generated` directory.
        FileWalk.files(under: root, includeHidden: true) { $0 == "transcript.jsonl" }
            .map { file in
                SessionRef(
                    provider: kind,
                    sessionID: Self.sessionID(for: file.url),
                    path: file.url,
                    modifiedAt: file.modified)
            }
    }

    /// `…/brain/<UUID>/.system_generated/logs/transcript.jsonl` → `<UUID>`.
    private static func sessionID(for transcript: URL) -> String {
        transcript
            .deletingLastPathComponent()   // logs
            .deletingLastPathComponent()   // .system_generated
            .deletingLastPathComponent()   // <UUID>
            .lastPathComponent
    }

    func previewTitle(_ ref: SessionRef) -> String? {
        var title: String?
        JSONL.scanHead(in: ref.path) { line in
            guard line["type"]?.string == "USER_INPUT" else { return false }
            title = SessionTitle.clean(Self.unwrap(line["content"]?.string ?? ""))
            return title != nil
        }
        return title
    }

    func parse(_ ref: SessionRef) throws -> Session {
        var session = Session(
            provider: kind, id: Self.sessionID(for: ref.path), cwd: nil, gitBranch: nil,
            model: nil, cliVersion: nil, startedAt: nil, events: [])

        try JSONL.forEachLine(in: ref.path) { line in
            let ts = Timestamps.parse(line["created_at"]?.string)
            if session.startedAt == nil { session.startedAt = ts }

            switch line["type"]?.string {
            case "USER_INPUT":
                let text = Self.unwrap(line["content"]?.string ?? "")
                if !text.isEmpty {
                    session.events.append(Event(
                        timestamp: ts, payload: .message(Message(role: .user, text: text))))
                }
            case "PLANNER_RESPONSE":
                if let content = line["content"]?.string, !content.isEmpty {
                    session.events.append(Event(
                        timestamp: ts, payload: .message(Message(role: .assistant, text: content))))
                }
                for call in line["tool_calls"]?.array ?? [] {
                    session.events.append(Event(timestamp: ts, payload: .toolCall(ToolCall(
                        id: nil,
                        name: call["name"]?.string ?? "unknown",
                        arguments: call["args"]?.jsonString ?? ""))))
                }
            case "CHECKPOINT", "CONVERSATION_HISTORY", nil:
                break
            default:
                // Any other action type is a tool execution; its `content` is
                // the result output.
                if let content = line["content"]?.string, !content.isEmpty {
                    let status = (line["status"]?.string ?? "").uppercased()
                    let failed = status.contains("ERROR") || status.contains("FAIL")
                    session.events.append(Event(timestamp: ts, payload: .toolResult(
                        Normalize.toolResult(callID: nil, output: content, isError: failed))))
                }
            }
        }
        return session
    }

    /// Antigravity wraps the prompt in `<USER_REQUEST>…</USER_REQUEST>`; drop the
    /// tags for a clean message/title.
    private static func unwrap(_ text: String) -> String {
        text
            .replacingOccurrences(of: "</?USER_REQUEST>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
