import SwiftUI

/// Observable state backing the UI: the known providers and their discovered
/// sessions, plus the currently selected session parsed into a summary.
/// File I/O (discovery and parsing) runs off the main actor so the window stays
/// responsive over large transcript collections.
@MainActor
final class AppModel: ObservableObject {
    struct ProviderEntry: Identifiable {
        let id: ProviderKind
        let provider: any Provider
        var refs: [SessionRef]
    }

    @Published var providers: [ProviderEntry] = []
    @Published var selectedProvider: ProviderKind?
    @Published var selectedSession: SessionRef?
    @Published var loadedSession: Session?
    @Published var summary: SessionSummary?
    @Published var isDiscovering = false
    @Published var isParsing = false
    @Published var errorMessage: String?

    var currentProviderEntry: ProviderEntry? {
        providers.first { $0.id == selectedProvider }
    }

    /// Discover sessions for every provider, newest first.
    func loadProviders() async {
        guard providers.isEmpty else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        var entries: [ProviderEntry] = []
        for provider in Providers.all {
            let refs = (try? await Task.detached { try provider.discoverSorted() }.value) ?? []
            entries.append(ProviderEntry(id: provider.kind, provider: provider, refs: refs))
        }
        providers = entries
        selectedProvider = entries.first { !$0.refs.isEmpty }?.id ?? entries.first?.id
    }

    /// Parse one session and compute its summary.
    func loadSession(_ ref: SessionRef) async {
        guard let provider = providers.first(where: { $0.id == ref.provider })?.provider else { return }
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

    /// Clear the parsed session when the provider selection changes.
    func clearSession() {
        selectedSession = nil
        loadedSession = nil
        summary = nil
        errorMessage = nil
    }
}
