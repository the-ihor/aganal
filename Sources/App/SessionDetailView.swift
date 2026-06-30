import SwiftUI
import Charts

/// Right column: the parsed session's metadata, headline stats, and tool-usage
/// breakdown.
struct SessionDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: DetailMode = .analysis

    var body: some View {
        Group {
            if let ref = model.selectedSession {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $mode) {
                        Text("Analysis").tag(DetailMode.analysis)
                        Text("Raw JSONL").tag(DetailMode.raw)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(8)
                    Divider()
                    switch mode {
                    case .analysis: analysis
                    case .raw: RawSessionView(ref: ref)
                    }
                }
            } else {
                ContentUnavailableLabel("Select a session", systemImage: "doc.text.magnifyingglass")
            }
        }
        .navigationTitle(mode == .raw ? "Raw JSONL" : "Analysis")
    }

    @ViewBuilder private var analysis: some View {
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
            Color.clear
        }
    }
}

/// Metric plotted in the tokens-over-time chart.
enum TokenMetric: String, CaseIterable, Identifiable {
    case cumulative = "Cumulative"
    case perTurn = "Per turn"
    case context = "Context"
    var id: String { rawValue }
}

struct SessionDetailContent: View {
    let session: Session
    let summary: SessionSummary

    @State private var tokenMetric: TokenMetric = .cumulative
    @State private var selectedRange: ClosedRange<Date>?
    @State private var isSelecting = false
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
            if !summary.tokenSeries.isEmpty {
                tokenChart
            }
            eventsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tokenChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tokens over time").font(.headline)
                Spacer()
                Picker("Metric", selection: $tokenMetric) {
                    ForEach(TokenMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Chart {
                ForEach(summary.tokenSeries) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value(tokenMetric.rawValue, tokenValue(point))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Time", point.time),
                        y: .value(tokenMetric.rawValue, tokenValue(point))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Drawn once (not per point) so its translucency doesn't stack.
                if let range = selectedRange {
                    RectangleMark(
                        xStart: .value("Start", range.lowerBound),
                        xEnd: .value("End", range.upperBound)
                    )
                    .foregroundStyle(.gray.opacity(0.2))
                }
            }
            // Custom range selection so the only highlight is our own
            // semi-transparent RectangleMark — the built-in chartXSelection
            // overlay is opaque gray and can't be restyled.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotFrame = proxy.plotFrame {
                        let rect = geo[plotFrame]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard abs(value.translation.width) > 2 else { return }
                                        isSelecting = true
                                        let startX = clampedX(value.startLocation.x, in: rect)
                                        let endX = clampedX(value.location.x, in: rect)
                                        if let a = proxy.value(atX: startX, as: Date.self),
                                           let b = proxy.value(atX: endX, as: Date.self) {
                                            selectedRange = Swift.min(a, b)...Swift.max(a, b)
                                        }
                                    }
                                    .onEnded { value in
                                        isSelecting = false
                                        if abs(value.translation.width) <= 2 {
                                            selectedRange = nil  // a click clears
                                        }
                                    }
                            )
                    }
                }
            }
            .frame(height: 200)

            Text(selectedRange == nil
                 ? "Drag across the chart to select a time range."
                 : "Showing events within the selected range.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tokenValue(_ point: TokenPoint) -> Int {
        switch tokenMetric {
        case .cumulative: return point.cumulativeOutput
        case .perTurn: return point.output
        case .context: return point.context
        }
    }

    /// Drag x in view space → x relative to the plot area's leading edge,
    /// clamped to the plot width (so `ChartProxy.value(atX:)` stays in range).
    private func clampedX(_ x: CGFloat, in rect: CGRect) -> CGFloat {
        min(max(x - rect.minX, 0), rect.width)
    }

    @ViewBuilder private var eventsSection: some View {
        let items = displayedEvents
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selectedRange == nil ? "Events" : "Events in selection")
                    .font(.headline)
                Text("\(items.count)")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedRange != nil {
                    Button("Clear") { selectedRange = nil }
                        .buttonStyle(.borderless)
                }
            }
            if isSelecting {
                // Mid-drag: show only the live count, not the re-rendering list.
                Text("Release to list \(items.count) event\(items.count == 1 ? "" : "s").")
                    .font(.callout).foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("No events in this range.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(items) { EventRow(item: $0) }
                }
            }
        }
    }

    /// Events to list: the selected time range, or all events when nothing is
    /// selected.
    private var displayedEvents: [EventItem] {
        if let range = selectedRange {
            return session.events.enumerated().compactMap { index, event in
                guard let time = event.timestamp, range.contains(time) else { return nil }
                return EventItem(id: index, time: time, payload: event.payload)
            }
        }
        return session.events.enumerated().map { index, event in
            EventItem(id: index, time: event.timestamp, payload: event.payload)
        }
    }

    private struct EventItem: Identifiable {
        let id: Int
        let time: Date?
        let payload: Event.Payload
    }

    private struct EventRow: View {
        let item: EventItem

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.payload.icon)
                    .foregroundStyle(item.payload.isError ? Color.red : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.payload.kindLabel).font(.callout).bold()
                        Spacer()
                        Text(item.time.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    let detail = item.payload.detailText
                        .split(whereSeparator: \.isNewline).joined(separator: " ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.tail)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.displayTitle)
                .font(.title2).bold()
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Label(session.provider.displayName, systemImage: session.provider.systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                .textSelection(.enabled)
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
