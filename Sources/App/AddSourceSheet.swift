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
                    HStack(spacing: 8) {
                        TextField("Directory", text: $path,
                                  prompt: Text("~/.claude/projects or /path/to/sessions"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onSubmit { applyManualPath() }
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

            if !path.isEmpty, !pathIsValidDirectory {
                Label("This folder doesn't exist.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let (n, k, p) = (name, kind, resolvedPath)
                    Task { await model.addCustomSource(name: n, kind: k, path: p) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!pathIsValidDirectory)
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
        panel.showsHiddenFiles = true   // session dirs (~/.claude, ~/.codex) are hidden
        panel.prompt = "Choose"
        panel.message = "Choose a directory containing session files"
        if path.isEmpty {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        if name.isEmpty { name = url.lastPathComponent }
        kind = Self.detectKind(url)
    }

    /// The typed path with a leading `~` expanded to the home directory.
    private var resolvedPath: String {
        (path as NSString).expandingTildeInPath
    }

    private var pathIsValidDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Normalize a typed path and, if it resolves to a real directory, fill the
    /// name and auto-detect its format.
    private func applyManualPath() {
        guard pathIsValidDirectory else { return }
        path = resolvedPath
        let url = URL(fileURLWithPath: resolvedPath, isDirectory: true)
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
