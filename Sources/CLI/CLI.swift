import Foundation

/// A command-line front end over the same analytics the MCP server exposes, so
/// an agent can shell out to `aganal <command>` (discoverable via `--help`)
/// instead of running an MCP server. Results are JSON on stdout; errors and
/// help go to stderr / stdout as text.
enum CLI {
    static let commands: Set<String> = ["sources", "sessions", "search", "analytics", "events", "overview"]

    static func run(_ args: [String]) -> Int32 {
        guard let command = args.first else { printTopHelp(); return 1 }
        let rest = Array(args.dropFirst())

        if command == "help" || command == "--help" || command == "-h" {
            if let sub = rest.first, commands.contains(sub) { printCommandHelp(sub) } else { printTopHelp() }
            return 0
        }
        if rest.contains("--help") || rest.contains("-h") { printCommandHelp(command); return 0 }

        do {
            let result: Any
            switch command {
            case "sources":   result = try MCPTools.call("list_sources", [:])
            case "sessions":  result = try MCPTools.call("list_sessions", sessionsArgs(rest))
            case "search":    result = try MCPTools.call("search_sessions", searchArgs(rest))
            case "analytics": result = try MCPTools.call("session_analytics", try analyticsArgs(rest))
            case "events":    result = try MCPTools.call("session_events", try eventsArgs(rest))
            case "overview":  result = try MCPTools.call("overview", overviewArgs(rest))
            default:
                err("unknown command '\(command)'")
                printTopHelp(toStderr: true)
                return 1
            }
            try emit(result)
            return 0
        } catch {
            err("\(error)")
            return 1
        }
    }

    // MARK: - Argument mapping (to the MCPTools param shape)

    private static func sessionsArgs(_ args: [String]) -> [String: Any] {
        let (_, o) = parse(args)
        var d: [String: Any] = [:]
        for key in ["provider", "since", "until", "limit", "offset"] {
            if let v = o[key]?.first { d[key] = v }
        }
        return d
    }

    private static func searchArgs(_ args: [String]) -> [String: Any] {
        let (positionals, o) = parse(args, boolFlags: ["content"])
        var d: [String: Any] = [:]
        if let query = positionals.first { d["query"] = query }
        if let p = o["provider"]?.first { d["provider"] = p }
        if o["content"] != nil { d["searchContent"] = true }
        if let l = o["limit"]?.first { d["limit"] = l }
        return d
    }

    private static func analyticsArgs(_ args: [String]) throws -> [String: Any] {
        let (positionals, o) = parse(args)
        guard let path = positionals.first else {
            throw CLIError("usage: aganal analytics <path> [--provider <kind>] [--start N --end N]")
        }
        var d: [String: Any] = ["path": path, "provider": try resolveProvider(o, path: path)]
        if let s = o["start"]?.first, let e = o["end"]?.first { d["range"] = ["start": s, "end": e] }
        return d
    }

    private static func eventsArgs(_ args: [String]) throws -> [String: Any] {
        let (positionals, o) = parse(args)
        guard let path = positionals.first else {
            throw CLIError("usage: aganal events <path> [--provider <kind>] [--type <t>]… [--search <q>] [--limit N]")
        }
        var d: [String: Any] = ["path": path, "provider": try resolveProvider(o, path: path)]
        if let types = o["type"] { d["types"] = types }
        if let s = o["search"]?.first { d["search"] = s }
        if let st = o["start"]?.first, let e = o["end"]?.first { d["range"] = ["start": st, "end": e] }
        if let l = o["limit"]?.first { d["limit"] = l }
        if let off = o["offset"]?.first { d["offset"] = off }
        return d
    }

    private static func overviewArgs(_ args: [String]) -> [String: Any] {
        let (_, o) = parse(args)
        var d: [String: Any] = [:]
        if let p = o["provider"]?.first { d["provider"] = p }
        if let s = o["since"]?.first { d["since"] = s }
        return d
    }

    /// The provider from `--provider`, else inferred from which source root
    /// contains the path.
    private static func resolveProvider(_ o: [String: [String]], path: String) throws -> String {
        if let p = o["provider"]?.first { return p }
        if let inferred = inferProvider(path) { return inferred.rawValue }
        throw CLIError("could not infer the provider from the path — pass --provider <\(ProviderKind.allCases.map(\.rawValue).joined(separator: "|"))>")
    }

    private static func inferProvider(_ path: String) -> ProviderKind? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        var best: (length: Int, kind: ProviderKind)?
        for source in SessionStore.allSources() {
            let root = source.root.standardizedFileURL.path
            guard target == root || target.hasPrefix(root + "/") else { continue }
            if best == nil || root.count > best!.length { best = (root.count, source.kind) }
        }
        return best?.kind
    }

    // MARK: - Parsing

    /// Split `["--provider", "codex", "path", "--content"]` into positionals and
    /// options. Options in `boolFlags` (and any flag not followed by a value) are
    /// stored as "true"; keys may repeat (e.g. `--type` for `events`).
    private static func parse(_ args: [String], boolFlags: Set<String> = []) -> (positionals: [String], options: [String: [String]]) {
        var positionals: [String] = []
        var options: [String: [String]] = [:]
        var index = 0
        while index < args.count {
            let token = args[index]
            if token.hasPrefix("--") {
                let key = String(token.dropFirst(2))
                if boolFlags.contains(key) {
                    options[key, default: []].append("true"); index += 1
                } else if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    options[key, default: []].append(args[index + 1]); index += 2
                } else {
                    options[key, default: []].append("true"); index += 1
                }
            } else {
                positionals.append(token); index += 1
            }
        }
        return (positionals, options)
    }

    // MARK: - Output

    private static func emit(_ object: Any) throws {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            throw CLIError("could not serialize result")
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private static func err(_ message: String) {
        FileHandle.standardError.write(Data(("aganal: " + message + "\n").utf8))
    }

    private static func write(_ text: String, toStderr: Bool = false) {
        (toStderr ? FileHandle.standardError : FileHandle.standardOutput).write(Data(text.utf8))
    }

    // MARK: - Help

    private static func printTopHelp(toStderr: Bool = false) {
        write("""
        aganal — analytics for your AI coding-agent sessions

        USAGE
          aganal <command> [options]

        COMMANDS
          sources                      List configured sources with session counts
          sessions [options]           List sessions, newest first
          search <query> [options]     Find sessions by keyword
          analytics <path> [options]   Full analytics for one session
          events <path> [options]      Normalized events of a session
          overview [options]           Aggregate stats across all sources
          mcp                          Run as an MCP server over stdio

        Results are JSON on stdout. Run 'aganal <command> --help' for options.

        EXAMPLE — analyze the latest session
          aganal sessions --limit 1     # find it, note its "path"
          aganal analytics <path>       # provider is inferred from the path

        """, toStderr: toStderr)
    }

    private static func printCommandHelp(_ command: String) {
        let providers = ProviderKind.allCases.map(\.rawValue).joined(separator: ", ")
        let text: String
        switch command {
        case "sources":
            text = "aganal sources\n  List configured sources with session counts. No options.\n"
        case "sessions":
            text = """
            aganal sessions [options]
              List sessions across sources, newest first. Each result includes the
              absolute "path" (and "provider") to pass to analytics/events.
              --provider <kind>   one of: \(providers)
              --since <date>      ISO 8601 or yyyy-MM-dd
              --until <date>
              --limit <n>         default 50, max 500
              --offset <n>

            """
        case "search":
            text = """
            aganal search <query> [options]
              Find sessions by keyword (title/path; add --content to scan file text).
              --provider <kind>   one of: \(providers)
              --content           also grep raw file contents (slower)
              --limit <n>         default 20, max 100

            """
        case "analytics":
            text = """
            aganal analytics <path> [options]
              Full analytics for one session: metadata, summary counts, tool usage,
              tokens over time, and estimated context by category.
              --provider <kind>   one of: \(providers) (inferred from <path> if omitted)
              --start <n> --end <n>   inclusive event-index range to scope metrics

            """
        case "events":
            text = """
            aganal events <path> [options]
              The normalized events of a session for structured analysis.
              --provider <kind>   one of: \(providers) (inferred from <path> if omitted)
              --type <t>          repeatable: message, reasoning, toolCall, toolResult, tokenUsage, lifecycle
              --search <q>        only events whose text/name/args/output contains this
              --start <n> --end <n>
              --limit <n>         default 200, max 1000
              --offset <n>

            """
        case "overview":
            text = """
            aganal overview [options]
              Aggregate stats across all sources: totals per provider and busiest days.
              --provider <kind>   one of: \(providers)
              --since <date>

            """
        default:
            printTopHelp(); return
        }
        write(text)
    }
}

struct CLIError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
