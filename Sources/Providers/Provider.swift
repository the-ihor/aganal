import Foundation

/// A source of coding-assistant sessions stored on disk. Each implementation
/// knows where its provider writes session files, how to enumerate them cheaply,
/// and how to normalize one into a provider-agnostic `Session`.
///
/// To add a provider: add a `ProviderKind` case and conform a type here.
protocol Provider: Sendable {
    var kind: ProviderKind { get }

    /// Root directory the provider writes sessions under.
    var sessionsRoot: URL { get }

    /// Enumerate session files without fully parsing them.
    func discover() throws -> [SessionRef]

    /// Parse one discovered session into the normalized model.
    func parse(_ ref: SessionRef) throws -> Session
}

extension Provider {
    /// All discovered sessions, newest first.
    func discoverSorted() throws -> [SessionRef] {
        try discover().sorted {
            ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }
    }

    /// Parse every discovered session. Convenient for whole-history analysis;
    /// can be expensive for large transcript collections.
    func parseAll() throws -> [Session] {
        try discover().map(parse)
    }
}

/// The set of providers AGANAL knows how to read, using default on-disk
/// locations under the current user's home directory.
enum Providers {
    static let all: [any Provider] = [
        CodexProvider(),
        ClaudeCodeProvider(),
    ]
}
