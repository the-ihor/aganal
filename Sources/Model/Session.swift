import Foundation

/// A session file located on disk, before it is parsed. Discovery produces
/// these cheaply (filename + mtime) so callers can sort/filter before paying to
/// read full transcripts.
struct SessionRef: Sendable, Hashable, Identifiable {
    let provider: ProviderKind
    let sessionID: String
    let path: URL
    let modifiedAt: Date?

    /// Stable, unique identity for lists — the file path (one session per file).
    var id: URL { path }
}

/// Model identity, best-effort and normalized across providers.
struct ModelInfo: Sendable, Hashable {
    var provider: String?   // e.g. "anthropic", "openai"
    var name: String?       // e.g. "claude-opus-4-8", "gpt-5-codex"
}

/// A fully normalized session: provider-agnostic metadata plus a flat,
/// time-ordered list of `Event`s. This is the shape every analysis in AGANAL
/// runs against, no matter which assistant produced the transcript.
struct Session: Sendable {
    let provider: ProviderKind
    var id: String
    var cwd: String?
    var gitBranch: String?
    var model: ModelInfo?
    var cliVersion: String?
    var startedAt: Date?
    var events: [Event]
}
