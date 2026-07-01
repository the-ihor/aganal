import Foundation

/// A session *format*: how to enumerate and parse one coding assistant's
/// on-disk transcripts. A provider is independent of *where* the files live —
/// `discover(in:)` takes the root — so the same format can read its default
/// location and any number of custom directories.
protocol Provider: Sendable {
    var kind: ProviderKind { get }

    /// The provider's default on-disk root (used for the built-in source).
    var sessionsRoot: URL { get }

    /// Enumerate session files under `root` without parsing them.
    func discover(in root: URL) throws -> [SessionRef]

    /// Parse one discovered session into the normalized model.
    func parse(_ ref: SessionRef) throws -> Session

    /// Cheaply read a display title (first real user prompt) from the file head.
    func previewTitle(_ ref: SessionRef) -> String?
}

extension Provider {
    /// Sessions under `root`, newest first.
    func discoverSorted(in root: URL) throws -> [SessionRef] {
        try discover(in: root).sorted {
            ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }
    }
}

/// The set of session formats AGANAL can read.
enum Providers {
    static let all: [any Provider] = [
        ClaudeCodeProvider(),
        CodexProvider(),
        GeminiProvider.geminiCli(),
        GeminiProvider.qwenCode(),
        CursorProvider(),
        OpenCodeProvider(),
        AntigravityProvider(),
    ]

    /// The provider that parses a given format.
    static func forKind(_ kind: ProviderKind) -> any Provider {
        all.first { $0.kind == kind } ?? all[0]
    }
}
