import SwiftUI
import AppKit

/// How many sessions each large list renders before a "Show more" footer. Caps
/// the initial `ForEach` so building the list never hitches on thousands of rows.
private let sessionPageSize = 200

/// Footer button that reveals the next page when a session list is capped.
private struct ShowMoreRow: View {
    let shown: Int
    let total: Int
    let more: () -> Void

    var body: some View {
        if total > shown {
            Button(action: more) {
                HStack {
                    Text("Show \(min(sessionPageSize, total - shown)) more")
                    Spacer()
                    Text("\(shown) of \(total)").foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.vertical, 3)
        }
    }
}

/// Which navigator the sidebar shows.
enum SidebarMode: String, CaseIterable, Identifiable {
    case sessions = "Sessions"     // one merged, provider-independent list
    case providers = "Providers"   // source → its sessions → analysis
    var id: Self { self }
}

/// A tabbed navigator. **Sessions** is one merged list of every session across
/// providers; **Providers** keeps the source → sessions → analysis panes. The
/// analysis detail pane is shared by both. Columns are pinned open with a
/// *constant* `columnVisibility` so the sidebar can never be collapsed.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingAdd = false
    @State private var mode: SidebarMode = .sessions

    var body: some View {
        Group {
            switch mode {
            case .sessions:
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    AllSessionsSidebar(mode: $mode)
                        .frame(minWidth: 260, idealWidth: 300)
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    SessionDetailView()
                }
            case .providers:
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    SourceSidebar(showingAdd: $showingAdd, mode: $mode)
                        // `navigationSplitViewColumnWidth` is ignored for the
                        // sidebar column on macOS (FB10749141); a frame is honored.
                        .frame(minWidth: 210, idealWidth: 230)
                        .toolbar(removing: .sidebarToggle)
                } content: {
                    SessionListView()
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
                } detail: {
                    SessionDetailView()
                }
            }
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
    @Binding var mode: SidebarMode

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
            if model.isDiscovering && model.entries.isEmpty { ProgressView("Discovering…") }
        }
        .safeAreaInset(edge: .top) { SidebarModePicker(mode: $mode) }
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

/// The [Sessions | Providers] switch shown at the top of the sidebar.
struct SidebarModePicker: View {
    @Binding var mode: SidebarMode

    var body: some View {
        Picker("View", selection: $mode) {
            ForEach(SidebarMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// The "Sessions" tab: one merged, provider-independent list of every session,
/// newest first. Selecting one loads its analysis in the shared detail pane.
struct AllSessionsSidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var mode: SidebarMode
    @State private var limit = sessionPageSize

    var body: some View {
        List(selection: $model.selectedSession) {
            ForEach(model.allSessions.prefix(limit)) { ref in
                MergedSessionRow(ref: ref).tag(ref)
            }
            ShowMoreRow(shown: min(limit, model.allSessions.count),
                        total: model.allSessions.count) { limit += sessionPageSize }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.isDiscovering && model.allSessions.isEmpty { ProgressView("Discovering…") }
        }
        .safeAreaInset(edge: .top) { SidebarModePicker(mode: $mode) }
        .navigationTitle("Sessions")
    }
}

/// A merged-list row: the originating provider's mark, the session title, and
/// its time — so a flat cross-provider list stays legible.
struct MergedSessionRow: View {
    @EnvironmentObject var model: AppModel
    let ref: SessionRef
    @State private var title: String?

    var body: some View {
        HStack(spacing: 10) {
            ProviderLogo(kind: ref.provider, size: 16).frame(width: 18)
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
        }
        .padding(.vertical, 2)
        .task(id: ref.id) { title = await model.title(for: ref) }
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
            if entry.isLoaded {
                Text("\(entry.refs.count)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
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
    @State private var limit = sessionPageSize

    var body: some View {
        Group {
            if let entry = model.currentEntry {
                List(selection: $model.selectedSession) {
                    ForEach(entry.refs.prefix(limit)) { ref in
                        SessionRow(ref: ref).tag(ref)
                    }
                    ShowMoreRow(shown: min(limit, entry.refs.count),
                                total: entry.refs.count) { limit += sessionPageSize }
                }
            } else {
                ContentUnavailableLabel("No source selected", systemImage: "sidebar.left")
            }
        }
        .navigationTitle("Sessions")
        .onChange(of: model.selectedSourceID) { _, _ in limit = sessionPageSize }
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
