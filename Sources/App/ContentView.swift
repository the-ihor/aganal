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

/// Left column: one flat list of configured sources — built-in providers first,
/// then user-added custom directories — each showing its path and session count.
struct SourceSidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var showingAdd: Bool

    private var builtIns: [AppModel.SourceEntry] { model.entries.filter { $0.source.isBuiltIn } }
    private var customs: [AppModel.SourceEntry] { model.entries.filter { !$0.source.isBuiltIn } }

    var body: some View {
        List(selection: $model.selectedSourceID) {
            ForEach(builtIns + customs) { entry in
                SourceRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.source.root])
                        }
                        if !entry.source.isBuiltIn {
                            Button("Remove", role: .destructive) {
                                model.removeSource(entry.id)
                            }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.isDiscovering { ProgressView("Discovering…") }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 9) {
                AppLogo(size: 26)
                Text("AGANAL")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
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
        HStack(spacing: 10) {
            ProviderLogo(kind: entry.source.kind, size: 18)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text("\(entry.refs.count)")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .help(entry.source.path)
    }

    /// The source path with the home directory abbreviated to `~`.
    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = entry.source.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
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
                .lineLimit(1)
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
