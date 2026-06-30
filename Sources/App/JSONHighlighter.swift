import SwiftUI

/// Lightweight JSON syntax highlighter producing an `AttributedString`: object
/// keys, string values, numbers, and literals (`true`/`false`/`null`) each get
/// their own color; everything else (punctuation/whitespace) is secondary.
enum JSONHighlighter {
    /// Pretty-print `raw` if it is valid JSON, preserving exact values.
    static func prettyJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Highlight already-pretty JSON text, capping the colored span at `limit`
    /// (the remainder is appended plain) to keep large records responsive.
    static func highlight(_ pretty: String, limit: Int = 20_000) -> AttributedString {
        let capped = pretty.count > limit ? String(pretty.prefix(limit)) : pretty
        var result = colorize(capped)
        if pretty.count > limit {
            var tail = AttributedString("\n… (truncated)")
            tail.foregroundColor = .secondary
            result.append(tail)
        }
        return result
    }

    /// Pretty-print and highlight `raw` if it is JSON; otherwise nil.
    static func highlightedIfJSON(_ raw: String, limit: Int = 8_000) -> AttributedString? {
        guard let pretty = prettyJSON(raw) else { return nil }
        return highlight(pretty, limit: limit)
    }

    private static func colorize(_ string: String) -> AttributedString {
        let chars = Array(string)
        var result = AttributedString()
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            var run = AttributedString(plain)
            run.foregroundColor = .secondary
            result.append(run)
            plain.removeAll(keepingCapacity: true)
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                flushPlain()
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "\\", j + 1 < chars.count { j += 2; continue }
                    if chars[j] == "\"" { j += 1; break }
                    j += 1
                }
                // A string is a key when the next non-space character is ':'.
                var k = j
                while k < chars.count, chars[k] == " " || chars[k] == "\n" || chars[k] == "\t" { k += 1 }
                let isKey = k < chars.count && chars[k] == ":"
                var run = AttributedString(String(chars[i..<min(j, chars.count)]))
                run.foregroundColor = isKey ? keyColor : stringColor
                result.append(run)
                i = j
            } else if c.isNumber || (c == "-" && i + 1 < chars.count && chars[i + 1].isNumber) {
                flushPlain()
                var j = i + 1
                while j < chars.count, chars[j].isNumber || "+-.eE".contains(chars[j]) { j += 1 }
                var run = AttributedString(String(chars[i..<j]))
                run.foregroundColor = numberColor
                result.append(run)
                i = j
            } else if let keyword = keyword(chars, at: i) {
                flushPlain()
                var run = AttributedString(keyword)
                run.foregroundColor = keywordColor
                result.append(run)
                i += keyword.count
            } else {
                plain.append(c)
                i += 1
            }
        }
        flushPlain()
        return result
    }

    private static func keyword(_ chars: [Character], at i: Int) -> String? {
        for keyword in ["true", "false", "null"] {
            let end = i + keyword.count
            guard end <= chars.count, String(chars[i..<end]) == keyword else { continue }
            if end == chars.count || !(chars[end].isLetter || chars[end].isNumber) { return keyword }
        }
        return nil
    }

    private static let keyColor = Color(red: 0.40, green: 0.65, blue: 1.00)     // blue
    private static let stringColor = Color(red: 0.90, green: 0.58, blue: 0.32)  // orange
    private static let numberColor = Color(red: 0.70, green: 0.56, blue: 1.00)  // purple
    private static let keywordColor = Color(red: 1.00, green: 0.45, blue: 0.55) // pink
}
