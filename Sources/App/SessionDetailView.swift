import SwiftUI

/// Right column: the parsed session's metadata, headline stats, and tool-usage
/// breakdown.
struct SessionDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.isParsing {
                ProgressView("Parsing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage {
                ContentUnavailableLabel(error, systemImage: "exclamationmark.triangle")
            } else if let session = model.loadedSession, let summary = model.summary {
                ScrollView {
                    SessionDetailContent(session: session, summary: summary)
                        .padding(20)
                }
            } else {
                ContentUnavailableLabel("Select a session", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
}

struct SessionDetailContent: View {
    let session: Session
    let summary: SessionSummary

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                StatTile(label: "Events", value: session.events.count.formatted())
                StatTile(label: "Messages", value: summary.messages.formatted())
                StatTile(label: "Reasoning", value: summary.reasoning.formatted())
                StatTile(label: "Tool calls", value: summary.toolCalls.formatted())
                StatTile(label: "Tool results",
                         value: summary.toolResults.formatted(),
                         accent: summary.toolFailures > 0 ? "\(summary.toolFailures) failed" : nil)
                StatTile(label: "Output tokens", value: summary.outputTokens.formatted())
                if summary.peakContextTokens > 0 {
                    StatTile(label: "Peak context", value: summary.peakContextTokens.formatted())
                }
            }
            tools
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.provider.displayName)
                    .font(.title2).bold()
                if let model = session.model?.name ?? session.model?.provider {
                    Text(model)
                        .font(.callout)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(session.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if let cwd = session.cwd {
                MetaRow(icon: "folder", text: cwd)
            }
            if let branch = session.gitBranch, !branch.isEmpty {
                MetaRow(icon: "arrow.triangle.branch", text: branch)
            }
            if let started = session.startedAt {
                MetaRow(icon: "clock", text: started.formatted(date: .abbreviated, time: .standard))
            }
        }
    }

    @ViewBuilder private var tools: some View {
        if summary.tools.isEmpty {
            Text("No tool calls in this session.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tool usage")
                    .font(.headline)
                let maxCount = summary.tools.first?.count ?? 1
                ForEach(summary.tools) { tool in
                    ToolBar(name: tool.name, count: tool.count, maxCount: maxCount)
                }
            }
        }
    }
}

private struct MetaRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var accent: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3).bold()
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let accent {
                Text(accent)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToolBar: View {
    let name: String
    let count: Int
    let maxCount: Int

    private var fraction: Double {
        maxCount > 0 ? Double(count) / Double(maxCount) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(count)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(.tint)
                    .frame(width: max(4, geo.size.width * fraction))
            }
            .frame(height: 5)
        }
    }
}
