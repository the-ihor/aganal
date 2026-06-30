import Foundation

/// Tolerant ISO 8601 parsing for the timestamps providers stamp on records.
/// Both Codex and Claude Code emit RFC 3339 with a `Z` zone; Codex includes
/// fractional seconds (`2026-06-26T23:00:50.462Z`), so we try that form first.
enum Timestamps {
    // Single-threaded use only; `ISO8601DateFormatter` is not `Sendable`.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let s = string else { return nil }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}
