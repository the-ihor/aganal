import Foundation

/// Reading helpers for the line-delimited JSON (`.jsonl`) format every provider
/// uses for session transcripts.
enum JSONL {
    /// Decode each non-empty line of a JSONL file into a `JSONValue`, invoking
    /// `handle` once per record. Malformed lines are skipped rather than failing
    /// the whole session.
    ///
    /// The file is read into memory once. That is fine for typical sessions, but
    /// very large rollouts (Codex transcripts can reach hundreds of MB) are read
    /// whole — a streaming reader is a future refinement.
    static func forEachLine(in url: URL, _ handle: (JSONValue) -> Void) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let value = try? decoder.decode(JSONValue.self, from: data) {
                handle(value)
            }
        }
    }
}
