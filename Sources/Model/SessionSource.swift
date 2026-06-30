import Foundation

/// A directory of sessions to analyze, paired with the provider format that
/// parses it.
///
/// Built-in sources point at each provider's default location. Custom sources
/// are user-added directories — a second Claude install (`~/.claude-alina`), a
/// synced cloud Codex instance, an archive — and are persisted across launches.
struct SessionSource: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var kind: ProviderKind   // which format/parser reads this directory
    var path: String
    var isBuiltIn: Bool

    var root: URL { URL(fileURLWithPath: path) }

    init(id: UUID = UUID(), name: String, kind: ProviderKind, path: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.path = path
        self.isBuiltIn = isBuiltIn
    }

    /// The default source for a provider, at its standard on-disk location.
    init(builtInFor provider: any Provider) {
        self.init(
            name: provider.kind.displayName,
            kind: provider.kind,
            path: provider.sessionsRoot.path,
            isBuiltIn: true)
    }
}
