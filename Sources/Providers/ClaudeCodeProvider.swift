import Foundation

/// Reads Claude Code sessions from
/// `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`.
///
/// Each line is tagged with a top-level `type`. Conversation lives on `user`
/// and `assistant` lines; their `message.content` is either a plain string or
/// an array of typed blocks (`text`, `thinking`, `tool_use`, `tool_result`).
/// Tool results arrive on `user` lines, paired to a `tool_use` by `tool_use_id`.
/// Non-conversational types (`file-history-snapshot`, `mode`, `system`, …) are
/// skipped.
struct ClaudeCodeProvider: Provider {
    let kind = ProviderKind.claudeCode
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var sessionsRoot: URL {
        home.appending(path: ".claude/projects")
    }

    func discover(in root: URL) throws -> [SessionRef] {
        FileWalk.files(under: root) { $0.hasSuffix(".jsonl") }
            .map { file in
                SessionRef(
                    provider: kind,
                    sessionID: file.url.deletingPathExtension().lastPathComponent,
                    path: file.url,
                    modifiedAt: file.modified)
            }
    }

    func previewTitle(_ ref: SessionRef) -> String? {
        var aiTitle: String?
        var prompt: String?
        JSONL.scanHead(in: ref.path) { line in
            switch line["type"]?.string {
            case "ai-title":
                if let title = line["aiTitle"]?.string, !title.isEmpty { aiTitle = title }
            case "user":
                // Use plain string content, or only the `text` blocks — never
                // tool_result/image blocks, which are not the human's prompt.
                if prompt == nil, let content = line["message"]?["content"] {
                    let text = content.string ?? (content.array ?? [])
                        .compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }
                        .joined(separator: " ")
                    prompt = SessionTitle.clean(text)
                }
            default:
                break
            }
            return false  // scan the whole head; ai-title can follow the first prompt
        }
        return aiTitle ?? prompt
    }

    func parse(_ ref: SessionRef) throws -> Session {
        var session = Session(
            provider: kind, id: ref.sessionID, cwd: nil, gitBranch: nil,
            model: nil, cliVersion: nil, startedAt: nil, events: [])

        // Claude Code writes one line per content block, all repeating the same
        // message `usage`; track which message IDs we've already counted so the
        // token total isn't multiplied by the block count.
        var countedUsageIDs = Set<String>()

        try JSONL.forEachLine(in: ref.path) { line in
            let ts = Timestamps.parse(line["timestamp"]?.string)
            session.cwd = session.cwd ?? line["cwd"]?.string
            session.gitBranch = session.gitBranch ?? line["gitBranch"]?.string
            session.cliVersion = session.cliVersion ?? line["version"]?.string
            if let sid = line["sessionId"]?.string { session.id = sid }
            if session.startedAt == nil { session.startedAt = ts }

            switch line["type"]?.string {
            case "user":
                Self.appendUser(line["message"], ts: ts, into: &session)
            case "assistant":
                Self.appendAssistant(line["message"], ts: ts,
                                     countedUsageIDs: &countedUsageIDs, into: &session)
            case "ai-title":
                if let title = line["aiTitle"]?.string, !title.isEmpty {
                    session.aiTitle = title  // last (newest) wins
                }
            default:
                break
            }
        }
        return session
    }

    private static func appendUser(_ message: JSONValue?, ts: Date?, into session: inout Session) {
        guard let message else { return }
        let content = message["content"]
        if let text = content?.string {
            session.events.append(Event(
                timestamp: ts, payload: .message(Message(role: .user, text: text))))
            return
        }
        for block in content?.array ?? [] {
            switch block["type"]?.string {
            case "text":
                session.events.append(Event(
                    timestamp: ts,
                    payload: .message(Message(role: .user, text: block["text"]?.string ?? ""))))
            case "tool_result":
                let result = Normalize.toolResult(
                    callID: block["tool_use_id"]?.string,
                    output: Normalize.text(block["content"]),
                    isError: block["is_error"]?.bool ?? false)
                session.events.append(Event(timestamp: ts, payload: .toolResult(result)))
            default:
                break
            }
        }
    }

    private static func appendAssistant(_ message: JSONValue?, ts: Date?,
                                        countedUsageIDs: inout Set<String>,
                                        into session: inout Session) {
        guard let message else { return }
        if let model = message["model"]?.string {
            session.model = ModelInfo(provider: "anthropic", name: model)
        }
        // Emit a message's usage only once. Every JSONL line of one assistant
        // message repeats the same `usage`, so summing per line over-counts
        // output tokens by the number of content blocks (~3×).
        if let usage = parseUsage(message["usage"]) {
            let id = message["id"]?.string
            if id == nil || countedUsageIDs.insert(id!).inserted {
                session.events.append(Event(timestamp: ts, payload: .tokenUsage(usage)))
            }
        }
        for block in message["content"]?.array ?? [] {
            switch block["type"]?.string {
            case "text":
                session.events.append(Event(
                    timestamp: ts,
                    payload: .message(Message(role: .assistant, text: block["text"]?.string ?? ""))))
            case "thinking":
                session.events.append(Event(
                    timestamp: ts,
                    payload: .reasoning(Reasoning(text: block["thinking"]?.string ?? ""))))
            case "tool_use":
                let call = ToolCall(
                    id: block["id"]?.string,
                    name: block["name"]?.string ?? "unknown",
                    arguments: block["input"]?.jsonString ?? "")
                session.events.append(Event(timestamp: ts, payload: .toolCall(call)))
            default:
                break
            }
        }
    }

    private static func parseUsage(_ usage: JSONValue?) -> TokenUsage? {
        guard let u = usage else { return nil }
        let input = u["input_tokens"]?.int
        let output = u["output_tokens"]?.int
        guard input != nil || output != nil else { return nil }
        let cacheRead = u["cache_read_input_tokens"]?.int
        let cacheCreation = u["cache_creation_input_tokens"]?.int
        // Full prompt/context size = uncached input + cache read + cache creation.
        let context = (input ?? 0) + (cacheRead ?? 0) + (cacheCreation ?? 0)
        return TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cacheRead,
            totalTokens: (input ?? 0) + (output ?? 0),
            contextTokens: context)
    }
}
