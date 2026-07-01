import Foundation

/// The AGANAL MCP tools. Each returns a JSON-serializable value (`[String: Any]`)
/// that the server wraps in a tool-result content block. Everything is computed
/// from the same providers/model/analysis the app uses — no interpretation, just
/// the data.
enum MCPTools {
    // MARK: - Definitions (advertised via tools/list)

    static var definitions: [[String: Any]] {
        let providerEnum = ProviderKind.allCases.map(\.rawValue)
        return [
            [
                "name": "list_sources",
                "description": "List the configured agent sources (built-in providers plus custom directories) with their session counts and on-disk roots.",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
            ],
            [
                "name": "list_sessions",
                "description": "List sessions across all sources (or one provider), newest first. Each result includes the absolute file path so you can analyze it further or open it directly.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "provider": ["type": "string", "enum": providerEnum, "description": "Restrict to one provider format."],
                        "since": ["type": "string", "description": "Only sessions modified on/after this date (ISO 8601 or yyyy-MM-dd)."],
                        "until": ["type": "string", "description": "Only sessions modified on/before this date."],
                        "limit": ["type": "integer", "description": "Max results (default 50, max 500)."],
                        "offset": ["type": "integer", "description": "Skip this many results (paging)."],
                    ],
                ],
            ],
            [
                "name": "search_sessions",
                "description": "Find sessions by keyword. Matches the session title and file path by default; set searchContent to also scan the raw file contents of the most recent sessions.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Keyword to look for (case-insensitive)."],
                        "provider": ["type": "string", "enum": providerEnum],
                        "searchContent": ["type": "boolean", "description": "Also grep raw file contents (slower; scans recent sessions)."],
                        "limit": ["type": "integer", "description": "Max matches (default 20, max 100)."],
                    ],
                    "required": ["query"],
                ],
            ],
            [
                "name": "session_analytics",
                "description": "Full analytics for one session: metadata, summary counts, tool usage, tokens over time, and estimated context by category. Key on the path + provider returned by list_sessions/search_sessions.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute path to the session file."],
                        "provider": ["type": "string", "enum": providerEnum],
                        "range": [
                            "type": "object",
                            "description": "Optional inclusive event-index range to scope the metrics.",
                            "properties": ["start": ["type": "integer"], "end": ["type": "integer"]],
                        ],
                    ],
                    "required": ["path", "provider"],
                ],
            ],
            [
                "name": "session_events",
                "description": "The normalized events of a session (messages, reasoning, tool calls, tool results, token usage, lifecycle) for structured analysis. Filter by type, search text, or event-index range.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                        "provider": ["type": "string", "enum": providerEnum],
                        "types": ["type": "array", "items": ["type": "string", "enum": ["message", "reasoning", "toolCall", "toolResult", "tokenUsage", "lifecycle"]]],
                        "search": ["type": "string", "description": "Only events whose text/name/args/output contains this."],
                        "range": ["type": "object", "properties": ["start": ["type": "integer"], "end": ["type": "integer"]]],
                        "limit": ["type": "integer", "description": "Max events (default 200, max 1000)."],
                        "offset": ["type": "integer"],
                    ],
                    "required": ["path", "provider"],
                ],
            ],
            [
                "name": "overview",
                "description": "Aggregate analytics across every source: total sessions, a per-provider breakdown (counts and date span), and the busiest days. Fast — based on session discovery, not full parsing.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "provider": ["type": "string", "enum": providerEnum],
                        "since": ["type": "string", "description": "Only count sessions modified on/after this date."],
                    ],
                ],
            ],
        ]
    }

    // MARK: - Dispatch

    static func call(_ name: String, _ args: [String: Any]) throws -> Any {
        switch name {
        case "list_sources": return listSources()
        case "list_sessions": return listSessions(args)
        case "search_sessions": return searchSessions(args)
        case "session_analytics": return try sessionAnalytics(args)
        case "session_events": return try sessionEvents(args)
        case "overview": return overview(args)
        default: throw MCPError.badRequest("Unknown tool: \(name)")
        }
    }

    // MARK: - Tools

    private static func listSources() -> [String: Any] {
        let sources = SessionStore.allSources().map { source -> [String: Any] in
            [
                "id": source.id.uuidString,
                "name": source.name,
                "provider": source.kind.rawValue,
                "path": source.path,
                "builtIn": source.isBuiltIn,
                "sessionCount": SessionStore.discover(source).count,
            ]
        }
        return ["sources": sources]
    }

    private static func listSessions(_ args: [String: Any]) -> [String: Any] {
        let filter = ProviderKind(rawValue: args.str("provider") ?? "")
        let since = parseDate(args.str("since"))
        let until = parseDate(args.str("until"))
        let limit = clamp(args.int("limit") ?? 50, 1, 500)
        let offset = max(args.int("offset") ?? 0, 0)

        var refs = SessionStore.allSessions(provider: filter)
        if let since { refs = refs.filter { ($0.modifiedAt ?? .distantPast) >= since } }
        if let until { refs = refs.filter { ($0.modifiedAt ?? .distantFuture) <= until } }
        let total = refs.count
        let page = Array(refs.dropFirst(offset).prefix(limit))

        let sessions = page.map { ref -> [String: Any] in
            let provider = Providers.forKind(ref.provider)
            return [
                "provider": ref.provider.rawValue,
                "title": provider.previewTitle(ref) ?? ref.sessionID,
                "path": ref.path.path,
                "sessionId": ref.sessionID,
                "modifiedAt": iso(ref.modifiedAt),
            ]
        }
        return ["total": total, "returned": sessions.count, "offset": offset, "sessions": sessions]
    }

    private static func searchSessions(_ args: [String: Any]) -> [String: Any] {
        guard let query = args.str("query"), !query.isEmpty else {
            return ["matches": [], "error": "query is required"]
        }
        let filter = ProviderKind(rawValue: args.str("provider") ?? "")
        let searchContent = args.bool("searchContent") ?? false
        let limit = clamp(args.int("limit") ?? 20, 1, 100)
        let maxScan = 1500, maxContentScan = 200
        let needle = query.lowercased()

        let refs = Array(SessionStore.allSessions(provider: filter).prefix(maxScan))
        var scored: [(Int, [String: Any])] = []
        var contentScanned = 0

        for ref in refs {
            let provider = Providers.forKind(ref.provider)
            let title = provider.previewTitle(ref) ?? ref.sessionID
            let path = ref.path.path
            var score = 0, matchedIn = ""

            if title.lowercased().contains(needle) { score = 3; matchedIn = "title" }
            else if path.lowercased().contains(needle) { score = 2; matchedIn = "path" }
            else if searchContent, contentScanned < maxContentScan {
                contentScanned += 1
                if let text = try? String(contentsOf: ref.path, encoding: .utf8),
                   text.lowercased().contains(needle) { score = 1; matchedIn = "content" }
            }
            guard score > 0 else { continue }
            scored.append((score, [
                "provider": ref.provider.rawValue, "title": title, "path": path,
                "matchedIn": matchedIn, "modifiedAt": iso(ref.modifiedAt),
            ]))
        }

        let matches = scored.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
        return ["query": query, "scanned": refs.count, "matches": Array(matches)]
    }

    private static func sessionAnalytics(_ args: [String: Any]) throws -> [String: Any] {
        let (session, path) = try loadSession(args)
        let range = eventRange(args["range"] as? [String: Any], count: session.events.count)
        let summary = SessionSummary(session, range: range)
        let limit = session.contextLimit

        var meta: [String: Any] = [
            "provider": session.provider.rawValue,
            "sessionId": session.id,
            "path": path,
            "title": session.displayTitle,
            "cwd": orNull(session.cwd),
            "gitBranch": orNull(session.gitBranch),
            "model": orNull(session.model?.name),
            "modelProvider": orNull(session.model?.provider),
            "startedAt": iso(session.startedAt),
            "contextLimit": orNull(limit),
        ]
        if let range { meta["range"] = ["start": range.lowerBound, "end": range.upperBound] }

        var sum: [String: Any] = [
            "events": summary.events, "messages": summary.messages, "reasoning": summary.reasoning,
            "toolCalls": summary.toolCalls, "toolResults": summary.toolResults,
            "toolFailures": summary.toolFailures, "outputTokens": summary.outputTokens,
            "peakContextTokens": summary.peakContextTokens,
        ]
        if let limit, limit > 0 {
            sum["peakContextPercent"] = Int((Double(summary.peakContextTokens) / Double(limit) * 100).rounded())
        }

        return [
            "meta": meta,
            "summary": sum,
            "toolUsage": summary.tools.prefix(20).map { ["name": $0.name, "count": $0.count] },
            "contextByCategory": contextTotals(session, range: range),
            "tokensOverTime": summary.tokenSeries.map {
                ["eventIndex": $0.eventIndex, "output": $0.output,
                 "cumulativeOutput": $0.cumulativeOutput, "context": $0.context]
            },
        ]
    }

    private static func sessionEvents(_ args: [String: Any]) throws -> [String: Any] {
        let (session, _) = try loadSession(args)
        let typeFilter = Set(args.strArray("types") ?? [])
        let search = args.str("search")?.lowercased()
        let range = eventRange(args["range"] as? [String: Any], count: session.events.count)
        let limit = clamp(args.int("limit") ?? 200, 1, 1000)
        let offset = max(args.int("offset") ?? 0, 0)

        var out: [[String: Any]] = []
        var matched = 0
        for (index, event) in session.events.enumerated() {
            if let range, !range.contains(index) { continue }
            let described = describe(event)
            if !typeFilter.isEmpty, !typeFilter.contains(described.type) { continue }
            if let search, !described.searchText.lowercased().contains(search) { continue }
            matched += 1
            if matched <= offset || out.count >= limit { continue }
            var full = described.fields
            full["index"] = index
            full["type"] = described.type
            full["timestamp"] = iso(event.timestamp)
            out.append(full)
        }
        return ["total": matched, "returned": out.count, "offset": offset, "events": out]
    }

    private static func overview(_ args: [String: Any]) -> [String: Any] {
        let filter = ProviderKind(rawValue: args.str("provider") ?? "")
        let since = parseDate(args.str("since"))
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.timeZone = .current

        struct Agg { var count = 0; var newest: Date?; var oldest: Date?; var name = "" }
        var perProvider: [String: Agg] = [:]
        var dayCounts: [String: Int] = [:]
        var total = 0

        for ref in SessionStore.allSessions(provider: filter) {
            if let since, (ref.modifiedAt ?? .distantPast) < since { continue }
            total += 1
            var agg = perProvider[ref.provider.rawValue] ?? Agg()
            agg.name = ref.provider.displayName
            agg.count += 1
            if let m = ref.modifiedAt {
                agg.newest = max(agg.newest ?? m, m)
                agg.oldest = min(agg.oldest ?? m, m)
                dayCounts[dayFmt.string(from: m), default: 0] += 1
            }
            perProvider[ref.provider.rawValue] = agg
        }

        let providers = perProvider
            .map { key, v -> [String: Any] in
                ["provider": key, "name": v.name, "sessions": v.count,
                 "newest": iso(v.newest), "oldest": iso(v.oldest)]
            }
            .sorted { ($0["sessions"] as! Int) > ($1["sessions"] as! Int) }
        let busiest = dayCounts.sorted { $0.value > $1.value }.prefix(7)
            .map { ["date": $0.key, "sessions": $0.value] }

        return ["totalSessions": total, "providers": providers, "busiestDays": Array(busiest)]
    }

    // MARK: - Resource read (aganal://session/<path>)

    static func readSessionResource(uri: String) throws -> [String: Any] {
        let prefix = "aganal://session/"
        guard uri.hasPrefix(prefix) else { throw MCPError.badRequest("Unknown resource URI: \(uri)") }
        let encoded = String(uri.dropFirst(prefix.count))
        let path = encoded.removingPercentEncoding ?? encoded
        guard var text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            throw MCPError.badRequest("Cannot read session file as text: \(path)")
        }
        let cap = 1_000_000
        if text.count > cap { text = String(text.prefix(cap)) + "\n…[truncated]" }
        return ["contents": [["uri": uri, "mimeType": "application/x-ndjson", "text": text]]]
    }

    // MARK: - Helpers

    private static func loadSession(_ args: [String: Any]) throws -> (Session, String) {
        guard let path = args.str("path") else { throw MCPError.badRequest("path is required") }
        guard let kind = ProviderKind(rawValue: args.str("provider") ?? "") else {
            throw MCPError.badRequest("provider is required (one of \(ProviderKind.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let ref = SessionStore.ref(path: path, provider: kind)
        return (try Providers.forKind(kind).parse(ref), path)
    }

    private static func eventRange(_ dict: [String: Any]?, count: Int) -> ClosedRange<Int>? {
        guard count > 0, let dict, let start = dict.int("start"), let end = dict.int("end"), start <= end
        else { return nil }
        return max(0, start) ... min(end, count - 1)
    }

    private static func contextTotals(_ session: Session, range: ClosedRange<Int>?) -> [String: Int] {
        var totals: [TokenCategory: Int] = [:]
        for (index, event) in session.events.enumerated() {
            if let range, !range.contains(index) { continue }
            switch event.payload {
            case .message(let m): totals[m.role == .user ? .user : .assistant, default: 0] += SessionSummary.estimateTokens(m.text)
            case .reasoning(let r): totals[.reasoning, default: 0] += SessionSummary.estimateTokens(r.text)
            case .toolCall(let c): totals[.toolCalls, default: 0] += SessionSummary.estimateTokens(c.arguments)
            case .toolResult(let r): totals[.toolResults, default: 0] += SessionSummary.estimateTokens(r.output)
            default: break
            }
        }
        var out: [String: Int] = [:]
        for category in TokenCategory.allCases { out[category.rawValue] = totals[category] ?? 0 }
        return out
    }

    private struct Described { let type: String; var fields: [String: Any]; let searchText: String }

    private static func describe(_ event: Event) -> Described {
        switch event.payload {
        case .message(let m):
            let (text, cut) = cap(m.text)
            var f: [String: Any] = ["role": String(describing: m.role), "text": text]
            if cut { f["truncated"] = true }
            return Described(type: "message", fields: f, searchText: m.text)
        case .reasoning(let r):
            let (text, cut) = cap(r.text)
            var f: [String: Any] = ["text": text]
            if cut { f["truncated"] = true }
            return Described(type: "reasoning", fields: f, searchText: r.text)
        case .toolCall(let c):
            let (arguments, cut) = cap(c.arguments)
            var f: [String: Any] = ["name": c.name, "arguments": arguments, "callId": orNull(c.id)]
            if cut { f["truncated"] = true }
            return Described(type: "toolCall", fields: f, searchText: c.name + " " + c.arguments)
        case .toolResult(let r):
            let (output, cut) = cap(r.output)
            var f: [String: Any] = ["isError": r.isError, "callId": orNull(r.callID), "output": output]
            if let code = r.exitCode { f["exitCode"] = code }
            if let dur = r.durationSeconds { f["durationSeconds"] = dur }
            if cut { f["truncated"] = true }
            return Described(type: "toolResult", fields: f, searchText: r.output)
        case .tokenUsage(let u):
            let f: [String: Any] = [
                "input": orNull(u.inputTokens), "output": orNull(u.outputTokens),
                "cached": orNull(u.cachedInputTokens), "total": orNull(u.totalTokens),
                "context": orNull(u.contextTokens),
            ]
            return Described(type: "tokenUsage", fields: f, searchText: "")
        case .lifecycle(let l):
            return Described(type: "lifecycle", fields: ["kind": String(describing: l)], searchText: "")
        }
    }

    private static func cap(_ text: String, _ max: Int = 4000) -> (String, Bool) {
        text.count > max ? (String(text.prefix(max)), true) : (text, false)
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
    private static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    private static func iso(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: string)
    }
}

/// Minimal typed access to a JSON-RPC params object.
extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func strArray(_ key: String) -> [String]? { self[key] as? [String] }
    func int(_ key: String) -> Int? {
        if let i = self[key] as? Int { return i }
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }
}

enum MCPError: Error, CustomStringConvertible {
    case badRequest(String)
    var description: String { switch self { case .badRequest(let m): return m } }
}
