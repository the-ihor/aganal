import Foundation

/// Reads opencode sessions from its SQLite database at
/// `~/.local/share/opencode/opencode.db` (opencode moved from per-file JSON to
/// SQLite). A session is a `session` row (title, model, directory, tokens in
/// columns); its turns are `message` rows whose `data` JSON holds the role, and
/// the actual content lives in `part` rows — `text`, `reasoning`, `tool`, and
/// `step-finish` (token accounting).
///
/// Since all sessions share one database file, each `SessionRef` carries a
/// synthetic per-session path (`…/opencode.db/<sessionID>`) for a unique
/// identity; `parse` strips the last component back to the database.
struct OpenCodeProvider: Provider {
    let kind = ProviderKind.opencode
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var sessionsRoot: URL { home.appending(path: ".local/share/opencode") }

    func discover(in root: URL) throws -> [SessionRef] {
        let databaseURL = root.appending(path: "opencode.db")
        guard let db = try? SQLiteDatabase(path: databaseURL.path) else { return [] }
        defer { db.close() }
        return db.rows("SELECT id, time_updated FROM session").compactMap { row in
            guard let id = row["id"] else { return nil }
            return SessionRef(
                provider: kind,
                sessionID: id,
                path: databaseURL.appending(path: id),
                modifiedAt: Self.date(ms: row["time_updated"]))
        }
    }

    func previewTitle(_ ref: SessionRef) -> String? {
        guard let db = try? SQLiteDatabase(path: ref.path.deletingLastPathComponent().path)
        else { return nil }
        defer { db.close() }
        let title = db.rows("SELECT title FROM session WHERE id = ?", [ref.sessionID])
            .first?["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false) ? title : nil
    }

    func parse(_ ref: SessionRef) throws -> Session {
        let databaseURL = ref.path.deletingLastPathComponent()
        let sessionID = ref.sessionID
        var session = Session(
            provider: kind, id: sessionID, cwd: nil, gitBranch: nil,
            model: nil, cliVersion: nil, startedAt: nil, events: [])
        guard let db = try? SQLiteDatabase(path: databaseURL.path) else { return session }
        defer { db.close() }

        if let meta = db.rows(
            "SELECT directory, version, model, time_created FROM session WHERE id = ?",
            [sessionID]).first {
            session.cwd = meta["directory"]
            session.cliVersion = meta["version"]
            session.startedAt = Self.date(ms: meta["time_created"])
            if let model = Self.json(meta["model"]) {
                session.model = ModelInfo(
                    provider: model["providerID"]?.string,
                    name: model["modelID"]?.string ?? model["id"]?.string)
            }
        }

        // Role lives on the message; content lives on its parts.
        var roleByMessage: [String: Role] = [:]
        for message in db.rows("SELECT id, data FROM message WHERE session_id = ?", [sessionID]) {
            if let id = message["id"], let data = Self.json(message["data"]) {
                roleByMessage[id] = Role(token: data["role"]?.string)
            }
        }

        for part in db.rows(
            "SELECT message_id, data, time_created FROM part WHERE session_id = ? ORDER BY time_created, id",
            [sessionID]) {
            guard let data = Self.json(part["data"]) else { continue }
            let role = roleByMessage[part["message_id"] ?? ""] ?? .assistant
            Self.appendPart(data, role: role, ts: Self.date(ms: part["time_created"]), into: &session)
        }
        return session
    }

    private static func appendPart(_ part: JSONValue, role: Role, ts: Date?, into session: inout Session) {
        switch part["type"]?.string {
        case "text":
            let text = part["text"]?.string ?? ""
            if !text.isEmpty {
                session.events.append(Event(
                    timestamp: ts, payload: .message(Message(role: role, text: text))))
            }
        case "reasoning":
            session.events.append(Event(
                timestamp: ts, payload: .reasoning(Reasoning(text: part["text"]?.string ?? ""))))
        case "tool":
            let state = part["state"]
            session.events.append(Event(timestamp: ts, payload: .toolCall(ToolCall(
                id: part["callID"]?.string,
                name: part["tool"]?.string ?? "unknown",
                arguments: state?["input"]?.jsonString ?? ""))))
            if let state, state["status"] != nil || state["output"] != nil {
                session.events.append(Event(timestamp: ts, payload: .toolResult(Normalize.toolResult(
                    callID: part["callID"]?.string,
                    output: state["output"]?.string ?? Normalize.text(state["output"]),
                    isError: state["status"]?.string == "error"))))
            }
        case "step-finish":
            if let usage = Self.usage(part["tokens"]) {
                session.events.append(Event(timestamp: ts, payload: .tokenUsage(usage)))
            }
        default:
            break   // step-start / snapshot markers carry no conversational content
        }
    }

    private static func usage(_ tokens: JSONValue?) -> TokenUsage? {
        guard let tokens else { return nil }
        let input = tokens["input"]?.int
        let output = tokens["output"]?.int
        guard input != nil || output != nil else { return nil }
        let cacheRead = tokens["cache"]?["read"]?.int
        let cacheWrite = tokens["cache"]?["write"]?.int
        return TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: cacheRead,
            totalTokens: tokens["total"]?.int ?? (input ?? 0) + (output ?? 0),
            contextTokens: (input ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0))
    }

    private static func json(_ string: String?) -> JSONValue? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func date(ms: String?) -> Date? {
        guard let ms, let value = Double(ms) else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
}
