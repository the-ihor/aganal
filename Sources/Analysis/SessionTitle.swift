import Foundation

/// Derives a human-readable session title from the first *real* user prompt,
/// skipping the non-human context both providers inject at the start of a
/// session (sandbox/permissions notes, environment context, hook output, …).
enum SessionTitle {
    /// Prefixes of injected, non-prompt user/developer messages to ignore.
    private static let skipPrefixes = [
        "<environment_context",
        "<permissions",
        "<user_instructions",
        "<system-reminder",
        "<command-message",
        "<command-name",
        "<local-command",
        "<user-prompt-submit-hook",
    ]

    /// Normalize a candidate prompt into a one-line title, or `nil` if it is
    /// empty or one of the injected wrappers above.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if skipPrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }
        // Collapse all internal whitespace so the title is a single tidy line.
        let oneLine = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.isEmpty ? nil : oneLine
    }
}

extension Session {
    /// Best display title: the assistant-generated title when present
    /// (Claude's `ai-title`), else the first real user prompt, else the id.
    var displayTitle: String { aiTitle ?? promptTitle ?? id }

    /// The first real user prompt in the session, for display. Computed from
    /// the already-parsed events (no extra I/O).
    var promptTitle: String? {
        for event in events {
            if case .message(let message) = event.payload, message.role == .user,
               let cleaned = SessionTitle.clean(message.text) {
                return cleaned
            }
        }
        return nil
    }
}
