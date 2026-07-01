import Foundation

/// Reads Gemini CLI (and its fork Qwen Code) session transcripts, written by
/// `chatRecordingService` as JSONL under
/// `~/.gemini/tmp/<project_hash>/chats/session-*.jsonl` (Qwen: `~/.qwen/tmp/...`).
///
/// Lines are discriminated structurally, not by a `type` tag alone:
/// - an initial metadata record has `sessionId` + `projectHash` + `startTime`;
/// - a message record has `id` + `type` (`"user"` | `"gemini"`) + `content`
///   (a Gemini `Part[]`: `{text}` / `{functionCall}` / `{functionResponse}`),
///   plus optional `model`, `thoughts`, `tokens`, `toolCalls`;
/// - checkpoint/rewind records (`$set`, `$rewindTo`) are skipped.
///
/// Note: implemented to the documented format; Qwen Code shares it verbatim.
struct GeminiProvider: Provider {
    let kind: ProviderKind
    let sessionsRoot: URL

    static func geminiCli(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> GeminiProvider {
        GeminiProvider(kind: .geminiCli, sessionsRoot: home.appending(path: ".gemini/tmp"))
    }

    static func qwenCode(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> GeminiProvider {
        GeminiProvider(kind: .qwenCode, sessionsRoot: home.appending(path: ".qwen/tmp"))
    }

    func discover(in root: URL) throws -> [SessionRef] {
        FileWalk.files(under: root) { $0.hasSuffix(".jsonl") }
            .filter { $0.url.pathComponents.contains("chats") }
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
            guard prompt == nil, line["type"]?.string == "user" else { return false }
            prompt = SessionTitle.clean(Self.partsText(line["content"]))
            return prompt != nil
        }
        return prompt
    }

    func parse(_ ref: SessionRef) throws -> Session {
        var session = Session(
            provider: kind, id: ref.sessionID, cwd: nil, gitBranch: nil,
            model: nil, cliVersion: nil, startedAt: nil, events: [])

        try JSONL.forEachLine(in: ref.path) { line in
            // Initial/metadata record.
            if let sid = line["sessionId"]?.string { session.id = sid }
            if session.cwd == nil { session.cwd = line["directories"]?[0]?.string }
            if session.startedAt == nil {
                session.startedAt = Timestamps.parse(line["startTime"]?.string)
            }

            // Message record.
            guard line["id"] != nil, let type = line["type"]?.string else { return }
            let ts = Timestamps.parse(line["timestamp"]?.string)
            if session.startedAt == nil { session.startedAt = ts }

            switch type {
            case "user":
                let text = Self.partsText(line["content"])
                if !text.isEmpty {
                    session.events.append(Event(
                        timestamp: ts, payload: .message(Message(role: .user, text: text))))
                }
                Self.appendFunctionResponses(line["content"], ts: ts, into: &session)
            case "gemini":
                if let model = line["model"]?.string {
                    session.model = ModelInfo(provider: "google", name: model)
                }
                for thought in line["thoughts"]?.array ?? [] {
                    let text = [thought["subject"]?.string, thought["description"]?.string]
                        .compactMap { $0 }.joined(separator: "\n")
                    session.events.append(Event(
                        timestamp: ts, payload: .reasoning(Reasoning(text: text))))
                }
                let text = Self.partsText(line["content"])
                if !text.isEmpty {
                    session.events.append(Event(
                        timestamp: ts, payload: .message(Message(role: .assistant, text: text))))
                }
                Self.appendFunctionCalls(line["content"], ts: ts, into: &session)
                Self.appendToolCalls(line["toolCalls"], ts: ts, into: &session)
                if let usage = Self.parseUsage(line["tokens"]) {
                    session.events.append(Event(timestamp: ts, payload: .tokenUsage(usage)))
                }
            default:
                break
            }
        }
        return session
    }

    // MARK: - Gemini `Part[]` content

    /// Concatenate the `text` of every textual part (`content` may be a plain
    /// string or a `Part[]`).
    private static func partsText(_ content: JSONValue?) -> String {
        guard let content else { return "" }
        if let s = content.string { return s }
        return (content.array ?? [])
            .compactMap { $0["text"]?.string }
            .joined(separator: "\n")
    }

    private static func appendFunctionCalls(_ content: JSONValue?, ts: Date?, into session: inout Session) {
        for part in content?.array ?? [] {
            guard let call = part["functionCall"] else { continue }
            session.events.append(Event(timestamp: ts, payload: .toolCall(ToolCall(
                id: call["id"]?.string,
                name: call["name"]?.string ?? "unknown",
                arguments: call["args"]?.jsonString ?? ""))))
        }
    }

    private static func appendFunctionResponses(_ content: JSONValue?, ts: Date?, into session: inout Session) {
        for part in content?.array ?? [] {
            guard let response = part["functionResponse"] else { continue }
            session.events.append(Event(timestamp: ts, payload: .toolResult(Normalize.toolResult(
                callID: response["id"]?.string,
                output: Normalize.text(response["response"]) ))))
        }
    }

    /// Some records also carry a resolved `toolCalls` array (call + result).
    private static func appendToolCalls(_ toolCalls: JSONValue?, ts: Date?, into session: inout Session) {
        for entry in toolCalls?.array ?? [] {
            session.events.append(Event(timestamp: ts, payload: .toolCall(ToolCall(
                id: entry["id"]?.string,
                name: entry["name"]?.string ?? "unknown",
                arguments: entry["args"]?.jsonString ?? ""))))
            if let result = entry["result"] ?? entry["response"] {
                session.events.append(Event(timestamp: ts, payload: .toolResult(Normalize.toolResult(
                    callID: entry["id"]?.string,
                    output: Normalize.text(result),
                    isError: entry["status"]?.string == "error"))))
            }
        }
    }

    private static func parseUsage(_ tokens: JSONValue?) -> TokenUsage? {
        guard let tokens else { return nil }
        let input = tokens["input"]?.int
        let output = tokens["output"]?.int
        guard input != nil || output != nil else { return nil }
        let cached = tokens["cached"]?.int
        return TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cached,
            totalTokens: tokens["total"]?.int ?? (input ?? 0) + (output ?? 0),
            contextTokens: (input ?? 0) + (cached ?? 0))
    }
}
