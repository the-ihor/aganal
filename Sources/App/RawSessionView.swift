import SwiftUI
import AppKit

/// Which view of a session the detail pane shows.
enum DetailMode: Hashable {
    case analysis
    case events
    case raw
}

/// Raw inspection mode: the session's JSONL records in a sortable table, with
/// the selected record's pretty-printed JSON below in a resizable split.
struct RawSessionView: View {
    let ref: SessionRef

    @State private var records: [RawRecord] = []
    @State private var selection: RawRecord.ID?
    @State private var loading = true

    var body: some View {
        VSplitView {
            recordTable
                .frame(minHeight: 150)
            jsonPane
                .frame(minHeight: 150)
        }
        .overlay {
            if loading { ProgressView("Loading…") }
        }
        .task(id: ref.id) { await load() }
    }

    private var recordTable: some View {
        Table(records, selection: $selection) {
            TableColumn("#") { record in
                Text("\(record.id)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(44)
            TableColumn("Type") { record in
                Text(record.type)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 110, ideal: 150)
            TableColumn("Detail") { record in
                Text(record.subtype)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 150)
            TableColumn("Time") { record in
                Text(record.timestamp.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
    }

    @ViewBuilder private var jsonPane: some View {
        if let record = selectedRecord {
            let pretty = RawRecord.prettyPrinted(record.raw)
            ScrollView {
                jsonText(pretty)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    copy(pretty)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy JSON")
                .padding(8)
            }
        } else {
            Text("Select a record to view its JSON")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Syntax-highlighted JSON for reasonable sizes; plain text for very large
    /// records (highlighting every line would be wasteful).
    private func jsonText(_ pretty: String) -> Text {
        pretty.count <= 40_000 ? Text(JSONHighlighter.highlight(pretty, limit: 40_000)) : Text(pretty)
    }

    private var selectedRecord: RawRecord? {
        guard let id = selection else { return nil }
        return records.first { $0.id == id }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let path = ref.path
        let loaded = await Task.detached { RawRecord.read(path) }.value
        records = loaded
        selection = loaded.first?.id
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
