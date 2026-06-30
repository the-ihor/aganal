import Foundation

/// Cross-provider helpers for turning raw provider records into normalized
/// values.
enum Normalize {
    /// Pull human-readable text out of a `content` value, which may be a plain
    /// string or an array of typed blocks (`{type, text}` / `{content}`).
    static func text(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        if let s = value.string { return s }
        if let arr = value.array {
            return arr.compactMap { block in
                block.string ?? block["text"]?.string ?? block["content"]?.string
            }.joined(separator: "\n")
        }
        return ""
    }

    /// Build a `ToolResult`, parsing Codex's `exited with code N` /
    /// `Wall time: N seconds` output footer when present. `isError`, when known
    /// from the provider (Claude's `is_error`), wins over the inferred value.
    static func toolResult(callID: String?, output: String, isError: Bool? = nil) -> ToolResult {
        let exit = firstInt(in: output, pattern: #"exited with code (\d+)"#)
        let wall = firstDouble(in: output, pattern: #"Wall time: ([\d.]+) seconds"#)
        let failed = isError ?? (exit.map { $0 != 0 } ?? false)
        return ToolResult(
            callID: callID, output: output, isError: failed,
            exitCode: exit, durationSeconds: wall)
    }

    private static func firstInt(in s: String, pattern: String) -> Int? {
        firstMatch(in: s, pattern: pattern).flatMap { Int($0) }
    }

    private static func firstDouble(in s: String, pattern: String) -> Double? {
        firstMatch(in: s, pattern: pattern).flatMap { Double($0) }
    }

    private static func firstMatch(in s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
