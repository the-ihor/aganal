import SwiftUI

/// Three fixed panes: providers → that provider's sessions → the selected
/// session's analysis. A plain `HStack` is used instead of `NavigationSplitView`
/// so the providers pane can never be collapsed or hidden.
struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ProviderSidebar()
                .frame(width: 210)
            Divider()
            SessionListView()
                .frame(width: 300)
            Divider()
            SessionDetailView()
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await model.loadProviders() }
        .onChange(of: model.selectedProvider) { _ in model.clearSession() }
        .onChange(of: model.selectedSession) { ref in
            if let ref { Task { await model.loadSession(ref) } }
        }
    }
}

/// Left column: one row per provider with its discovered session count.
struct ProviderSidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selectedProvider) {
            Section("Providers") {
                ForEach(model.providers) { entry in
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                        Text(entry.provider.kind.displayName)
                        Spacer()
                        Text("\(entry.refs.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .tag(entry.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.isDiscovering {
                ProgressView("Discovering…")
            }
        }
    }
}

/// Middle column: the selected provider's sessions, newest first.
struct SessionListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let entry = model.currentProviderEntry {
                List(selection: $model.selectedSession) {
                    ForEach(entry.refs) { ref in
                        SessionRow(ref: ref).tag(ref)
                    }
                }
            } else {
                ContentUnavailableLabel("No provider selected", systemImage: "sidebar.left")
            }
        }
    }
}

struct SessionRow: View {
    let ref: SessionRef

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ref.sessionID)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            if let date = ref.modifiedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Small fallback shown where there is nothing to display. (A lightweight
/// stand-in so the app builds on macOS 13, before `ContentUnavailableView`.)
struct ContentUnavailableLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
