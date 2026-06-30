import SwiftUI

/// Observable state backing the UI: the configured sources (built-in plus
/// user-added custom directories) and their discovered sessions, plus the
/// currently selected session parsed into a summary. File I/O runs off the main
/// actor so the window stays responsive over large transcript collections.
@MainActor
final class AppModel: ObservableObject {
    /// A source together with the sessions discovered under it.
    struct SourceEntry: Identifiable {
        let source: SessionSource
        var refs: [SessionRef]
        var id: SessionSource.ID { source.id }
    }

    @Published var sources: [SessionSource]
    @Published var entries: [SourceEntry] = []
    @Published var selectedSourceID: SessionSource.ID?
    @Published var selectedSession: SessionRef?
    @Published var loadedSession: Session?
    @Published var summary: SessionSummary?
    @Published var isDiscovering = false
    @Published var isParsing = false
    @Published var errorMessage: String?

    /// Session titles resolved lazily per row, keyed by file path. Not
    /// `@Published` — rows hold their own resolved title — so filling the cache
    /// doesn't invalidate the whole list.
    private var titleCache: [URL: String] = [:]

    init() {
        let builtIns = Providers.all.map { SessionSource(builtInFor: $0) }
        self.sources = builtIns + AppModel.loadCustomSources()
    }

    var currentEntry: SourceEntry? {
        entries.first { $0.id == selectedSourceID }
    }

    // MARK: - Discovery

    /// Discover sessions for every configured source. Runs once; re-discovery on
    /// add/remove is handled incrementally.
    func loadSources() async {
        guard entries.isEmpty else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        var built: [SourceEntry] = []
        for source in sources {
            built.append(SourceEntry(source: source, refs: await discover(source)))
        }
        entries = built
        if selectedSourceID == nil {
            selectedSourceID = built.first { !$0.refs.isEmpty }?.id ?? built.first?.id
        }
    }

    private func discover(_ source: SessionSource) async -> [SessionRef] {
        let provider = Providers.forKind(source.kind)
        let root = source.root
        return (try? await Task.detached { try provider.discoverSorted(in: root) }.value) ?? []
    }

    // MARK: - Custom sources

    func addCustomSource(name: String, kind: ProviderKind, path: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = SessionSource(
            name: trimmed.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmed,
            kind: kind,
            path: path,
            isBuiltIn: false)
        sources.append(source)
        saveCustomSources()
        let refs = await discover(source)
        entries.append(SourceEntry(source: source, refs: refs))
        selectedSourceID = source.id
    }

    func removeSource(_ id: SessionSource.ID) {
        guard let source = sources.first(where: { $0.id == id }), !source.isBuiltIn else { return }
        sources.removeAll { $0.id == id }
        entries.removeAll { $0.id == id }
        saveCustomSources()
        if selectedSourceID == id {
            selectedSourceID = entries.first?.id
            clearSession()
        }
    }

    // MARK: - Session selection / titles

    func title(for ref: SessionRef) async -> String {
        if let cached = titleCache[ref.id] { return cached }
        let provider = Providers.forKind(ref.provider)
        let resolved = await Task.detached { provider.previewTitle(ref) }.value ?? ref.sessionID
        titleCache[ref.id] = resolved
        return resolved
    }

    func loadSession(_ ref: SessionRef) async {
        let provider = Providers.forKind(ref.provider)
        isParsing = true
        defer { isParsing = false }
        do {
            let session = try await Task.detached { try provider.parse(ref) }.value
            guard selectedSession == ref else { return }  // selection moved on
            loadedSession = session
            summary = SessionSummary(session)
            errorMessage = nil
        } catch {
            loadedSession = nil
            summary = nil
            errorMessage = String(describing: error)
        }
    }

    func clearSession() {
        selectedSession = nil
        loadedSession = nil
        summary = nil
        errorMessage = nil
    }

    // MARK: - Persistence

    /// Custom sources live in Application Support so they survive launches
    /// regardless of how the (unbundled) binary is started.
    private static var customSourcesURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "AGANAL/sources.json")
    }

    private func saveCustomSources() {
        let customs = sources.filter { !$0.isBuiltIn }
        let url = Self.customSourcesURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(customs) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadCustomSources() -> [SessionSource] {
        guard let data = try? Data(contentsOf: customSourcesURL),
              let decoded = try? JSONDecoder().decode([SessionSource].self, from: data)
        else { return [] }
        return decoded
    }
}
