import Foundation

/// One raw JSONL record from a session file, for the Raw inspection mode.
/// Columns (`type`, `subtype`, `timestamp`) are extracted for the table; `raw`
/// keeps the original line for faithful pretty-printing.
struct RawRecord: Identifiable, Sendable {
    let id: Int            // 0-based record index within the file
    let type: String
    let subtype: String    // inner discriminator (payload.type / message.role)
    let timestamp: Date?
    let raw: String        // original JSON text of the line

    /// Read every non-empty record from a session file. Reads the file whole —
    /// the same cost as parsing it for the Analysis view.
    static func read(_ url: URL) -> [RawRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var out: [RawRecord] = []
        var index = 0
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let value = trimmed.data(using: .utf8).flatMap { try? decoder.decode(JSONValue.self, from: $0) }
            let subtype = value?["payload"]?["type"]?.string
                ?? value?["message"]?["role"]?.string
                ?? ""
            out.append(RawRecord(
                id: index,
                type: value?["type"]?.string ?? "?",
                subtype: subtype,
                timestamp: Timestamps.parse(value?["timestamp"]?.string),
                raw: trimmed))
            index += 1
        }
        return out
    }

    /// Pretty-print the record's JSON for display, preserving exact values from
    /// the original text (integers, key spelling) via `JSONSerialization`.
    static func prettyPrinted(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: pretty, encoding: .utf8)
        else { return raw }
        return string
    }
}
