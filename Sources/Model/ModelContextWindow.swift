import Foundation

/// Predefined maximum context window (in tokens) per model — the capacity a
/// model can hold. Used as the denominator for "context used".
///
/// Providers override this from session data when they report a window (Codex's
/// `model_context_window`). Claude never reports one, so it relies on this
/// table. Edit these to match your account/tier; matching is by longest prefix,
/// so a single `claude-opus-4` entry covers `claude-opus-4-8`, etc.
enum ModelContextWindow {
    static let known: [String: Int] = [
        "claude-opus-4": 1_000_000,
        "claude-sonnet-4": 1_000_000,
        "claude-haiku-4": 200_000,
        "gpt-5": 256_000,
    ]

    /// The window for a model name, matching the longest known prefix.
    static func tokens(forModel model: String?) -> Int? {
        guard let model else { return nil }
        if let exact = known[model] { return exact }
        return known
            .filter { model.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }
}

extension Session {
    /// Resolved context window: what the provider reported, else the predefined
    /// table by model. nil when the model is unknown and nothing was reported.
    var contextLimit: Int? {
        contextWindow ?? ModelContextWindow.tokens(forModel: model?.name)
    }
}
