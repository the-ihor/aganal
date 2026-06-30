import SwiftUI
import AppKit

/// Three panes: sources → the selected source's sessions → the selected
/// session's analysis. The split view is pinned open with a *constant*
/// `columnVisibility` so the sidebar can never be collapsed (even the View ▸
/// Hide Sidebar command becomes a no-op); the now-useless toggle is removed.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingAdd = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SourceSidebar(showingAdd: $showingAdd)
                // `navigationSplitViewColumnWidth` is ignored for the sidebar
                // column on macOS (FB10749141); a frame on the List is honored.
                .frame(minWidth: 210, idealWidth: 230)
                .toolbar(removing: .sidebarToggle)
        } content: {
            SessionListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            SessionDetailView()
        }
        .task { await model.loadSources() }
        .onChange(of: model.selectedSourceID) { _, _ in model.clearSession() }
        .onChange(of: model.selectedSession) { _, ref in
            if let ref { Task { await model.loadSession(ref) } }
        }
        .sheet(isPresented: $showingAdd) {
            AddSourceSheet().environmentObject(model)
        }
    }
}

/// Left column: configured sources, grouped into built-in providers and
/// user-added custom directories, each with its discovered session count.
struct SourceSidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var showingAdd: Bool

    private var builtIns: [AppModel.SourceEntry] { model.entries.filter { $0.source.isBuiltIn } }
    private var customs: [AppModel.SourceEntry] { model.entries.filter { !$0.source.isBuiltIn } }

    var body: some View {
        List(selection: $model.selectedSourceID) {
            Section("Providers") {
                ForEach(builtIns) { entry in
                    SourceRow(entry: entry).tag(entry.id)
                }
            }
            if !customs.isEmpty {
                Section("Custom") {
                    ForEach(customs) { entry in
                        SourceRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([entry.source.root])
                                }
                                Button("Remove", role: .destructive) {
                                    model.removeSource(entry.id)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.isDiscovering { ProgressView("Discovering…") }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAdd = true
            } label: {
                Label("Add Directory…", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct SourceRow: View {
    let entry: AppModel.SourceEntry

    var body: some View {
        Label(entry.source.name, systemImage: entry.source.kind.systemImage)
            .badge(entry.refs.count)
            .help(entry.source.path)
    }
}

/// Middle column: the selected source's sessions, newest first.
struct SessionListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let entry = model.currentEntry {
                List(selection: $model.selectedSession) {
                    ForEach(entry.refs) { ref in
                        SessionRow(ref: ref).tag(ref)
                    }
                }
            } else {
                ContentUnavailableLabel("No source selected", systemImage: "sidebar.left")
            }
        }
        .navigationTitle("Sessions")
    }
}

struct SessionRow: View {
    @EnvironmentObject var model: AppModel
    let ref: SessionRef
    @State private var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title ?? ref.sessionID)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(title == nil ? .secondary : .primary)
            if let date = ref.modifiedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .task(id: ref.id) {
            title = await model.title(for: ref)
        }
    }
}

/// Small fallback shown where there is nothing to display.
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
