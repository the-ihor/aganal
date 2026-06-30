import SwiftUI
import AppKit

/// Sheet for adding a custom session directory: pick a folder, confirm the
/// format (auto-detected), name it, and add it as a new source.
struct AddSourceSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: ProviderKind = .claudeCode
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Session Directory")
                .font(.title2).bold()
            Text("Point AGANAL at any folder of sessions — a second Claude install, "
                 + "a synced cloud Codex instance, or an archive.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                LabeledContent("Directory") {
                    HStack {
                        Text(path.isEmpty ? "No folder chosen" : path)
                            .foregroundStyle(path.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { choose() }
                    }
                }
                Picker("Format", selection: $kind) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                TextField("Name", text: $name, prompt: Text("e.g. Cloud Codex"))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let (n, k, p) = (name, kind, path)
                    Task { await model.addCustomSource(name: n, kind: k, path: p) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a directory containing session files"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        if name.isEmpty { name = url.lastPathComponent }
        kind = Self.detectKind(url)
    }

    /// Shallow guess of the format from a directory's immediate contents: a
    /// Codex sessions root holds `rollout-*` files or year-numbered subfolders.
    private static func detectKind(_ url: URL) -> ProviderKind {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let looksCodex = names.contains {
            $0.hasPrefix("rollout-") || $0.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
        }
        return looksCodex ? .codex : .claudeCode
    }
}
