import Foundation

/// Foundation-only access to the configured sources and their sessions, shared
/// by the SwiftUI app and the CLI. Built-in sources point at
/// each provider's default location; custom sources are read from the same
/// `sources.json` the app persists.
enum SessionStore {
    /// Where the app stores user-added custom sources.
    static var customSourcesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "AGANAL/sources.json")
    }

    static func customSources() -> [SessionSource] {
        guard let data = try? Data(contentsOf: customSourcesURL),
              let decoded = try? JSONDecoder().decode([SessionSource].self, from: data)
        else { return [] }
        return decoded
    }

    /// Every configured source: built-in providers first, then custom directories.
    static func allSources() -> [SessionSource] {
        Providers.all.map { SessionSource(builtInFor: $0) } + customSources()
    }

    /// Discover sessions under a source, newest first (no parsing).
    static func discover(_ source: SessionSource) -> [SessionRef] {
        let provider = Providers.forKind(source.kind)
        return (try? provider.discoverSorted(in: source.root)) ?? []
    }

    /// Every session across the configured sources (optionally one provider),
    /// newest first, de-duplicated by file path.
    static func allSessions(provider filter: ProviderKind? = nil) -> [SessionRef] {
        var seen = Set<String>()
        var refs: [SessionRef] = []
        for source in allSources() {
            if let filter, source.kind != filter { continue }
            for ref in discover(source) where seen.insert(ref.path.path).inserted {
                refs.append(ref)
            }
        }
        return refs.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
    }

    /// A `SessionRef` for an arbitrary file path under a given provider — for the
    /// analytics/events/read tools, which key on the absolute path.
    static func ref(path: String, provider kind: ProviderKind) -> SessionRef {
        let url = URL(fileURLWithPath: path)
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return SessionRef(provider: kind,
                          sessionID: url.deletingPathExtension().lastPathComponent,
                          path: url,
                          modifiedAt: mtime)
    }
}
