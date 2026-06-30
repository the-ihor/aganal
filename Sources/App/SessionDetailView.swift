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
    var id: String { rawValue }
}

struct SessionDetailContent: View {
    let session: Session
    let summary: SessionSummary

    @State private var tokenMetric: TokenMetric = .cumulative
    @State private var appliedRange: ClosedRange<Int>?    // committed event-index window
    @State private var lowerFraction = 0.0                // live range-slider handles
    @State private var upperFraction = 1.0
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
                    StatTile(
                        label: "Peak context",
                        value: summary.peakContextTokens.formatted(),
                        subtitle: session.contextLimit.map {
                            "\(percent(summary.peakContextTokens, of: $0))% of \($0.formatted())"
                        })
                }
            }
            tools
            if fullRange != nil {
                rangeControl
            }
            if !summary.tokenSeries.isEmpty {
                tokenChart
            }
            if !summary.contextBreakdown.isEmpty {
                contextChart
            }
            eventsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tokenChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
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
                ForEach(pauseIndices, id: \.self) { index in
                    RuleMark(x: .value("Event", index))
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        .foregroundStyle(.gray.opacity(0.18))
                }
                ForEach(plottedSeries) { point in
                    AreaMark(
                        x: .value("Event", point.x),
                        y: .value(tokenMetric.rawValue, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Event", point.x),
                        y: .value(tokenMetric.rawValue, point.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXDomain(chartDomain)
            .frame(height: 200)
        }
    }

    private func tokenValue(_ point: TokenPoint) -> Int {
        switch tokenMetric {
        case .cumulative: return point.cumulativeOutput
        case .perTurn: return point.output
        }
    }

    private func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }

    @ViewBuilder private var contextChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context by category").font(.headline)
            Chart {
                ForEach(pauseIndices, id: \.self) { index in
                    RuleMark(x: .value("Event", index))
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        .foregroundStyle(.gray.opacity(0.18))
                }
                ForEach(summary.contextBreakdown) { point in
                    AreaMark(
                        x: .value("Event", point.eventIndex),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(by: .value("Category", point.category))
                    .interpolationMethod(.monotone)
                }
            }
            .chartForegroundStyleScale(
                domain: TokenCategory.allCases.map(\.rawValue),
                range: [Color.blue, .teal, .purple, .orange, .pink])
            .chartXDomain(chartDomain)
            .frame(height: 220)
            Text("Estimated tokens (≈ characters ÷ 4), accumulated by what produced them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Event range (charts and slider are event-indexed, not time)

    private var eventCount: Int { session.events.count }

    private var fullRange: ClosedRange<Int>? {
        eventCount > 1 ? 0...(eventCount - 1) : nil
    }

    /// The x-domain both charts render: the committed range, else the full span.
    private var chartDomain: ClosedRange<Int>? { appliedRange ?? fullRange }

    @ViewBuilder private var rangeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Event range").font(.headline)
                Spacer()
                if lowerFraction > 0.001 || upperFraction < 0.999 {
                    Button("Reset") { resetRange() }.buttonStyle(.borderless)
                }
            }
            RangeSlider(lower: $lowerFraction, upper: $upperFraction,
                        steps: eventCount, onCommit: commitRange)
                .frame(height: 22)
            Text(rangeLabel).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Nearest event index for a 0...1 slider fraction.
    private func eventIndex(_ fraction: Double, maxIndex: Int) -> Int {
        min(max(Int((fraction * Double(maxIndex)).rounded()), 0), maxIndex)
    }

    private var rangeLabel: String {
        guard eventCount >= 2 else { return "" }
        let maxIndex = eventCount - 1
        let lo = eventIndex(lowerFraction, maxIndex: maxIndex)
        let hi = eventIndex(upperFraction, maxIndex: maxIndex)
        if lo <= 0, hi >= maxIndex { return "All \(eventCount) events" }
        return "Events \(lo + 1)–\(hi + 1) of \(eventCount)"
    }

    /// Apply the slider window once, on release.
    private func commitRange() {
        guard eventCount >= 2 else { appliedRange = nil; return }
        let maxIndex = eventCount - 1
        let lo = eventIndex(lowerFraction, maxIndex: maxIndex)
        let hi = max(eventIndex(upperFraction, maxIndex: maxIndex), lo)
        appliedRange = (lo <= 0 && hi >= maxIndex) ? nil : lo...hi
    }

    private func resetRange() {
        lowerFraction = 0
        upperFraction = 1
        appliedRange = nil
    }

    // MARK: - Charts

    /// Token points mapped to the selected metric, plotted by event index.
    private var plottedSeries: [PlotPoint] {
        summary.tokenSeries.map { PlotPoint(id: $0.id, x: $0.eventIndex, value: tokenValue($0)) }
    }

    /// A "long" idle gap: more than 6× the median spacing (with a 30s floor).
    private func gapThreshold(_ sortedDeltas: [TimeInterval]) -> TimeInterval {
        guard !sortedDeltas.isEmpty else { return .infinity }
        return max(sortedDeltas[sortedDeltas.count / 2] * 6, 30)
    }

    /// Event indices where a long pause precedes the event — drawn as gray
    /// markers so idle time stays visible even on the (time-free) event axis.
    private var pauseIndices: [Int] {
        var previous: Date?
        var deltas: [TimeInterval] = []
        var pairs: [(index: Int, gap: TimeInterval)] = []
        for (index, event) in session.events.enumerated() {
            guard let time = event.timestamp else { continue }
            if let previous {
                let gap = time.timeIntervalSince(previous)
                deltas.append(gap)
                pairs.append((index, gap))
            }
            previous = time
        }
        let threshold = gapThreshold(deltas.sorted())
        return pairs.filter { $0.gap > threshold }.map(\.index)
    }

    private struct PlotPoint: Identifiable {
        let id: Int
        let x: Int
        let value: Int
    }

    @ViewBuilder private var eventsSection: some View {
        let items = displayedEvents
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(appliedRange == nil ? "Events" : "Events in range")
                    .font(.headline)
                Text("\(items.count)")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if appliedRange != nil {
                    Button("Clear") { resetRange() }
                        .buttonStyle(.borderless)
                }
            }
            if items.isEmpty {
                Text("No events in this range.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(items) { EventRow(item: $0) }
                }
            }
        }
    }

    /// Events to list: the committed event-index range, or all events.
    private var displayedEvents: [EventItem] {
        session.events.enumerated().compactMap { index, event in
            if let range = appliedRange, !range.contains(index) { return nil }
            return EventItem(id: index, time: event.timestamp, payload: event.payload)
        }
    }

    private struct EventItem: Identifiable {
        let id: Int
        let time: Date?
        let payload: Event.Payload
    }

    private struct EventRow: View {
        let item: EventItem
        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { expanded.toggle() }
                } label: {
                    summaryRow
                }
                .buttonStyle(.plain)

                if expanded {
                    expandedContent
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }

        private var summaryRow: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.payload.icon)
                    .foregroundStyle(item.payload.isError ? Color.red : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.payload.kindLabel).font(.callout).bold()
                        Spacer()
                        Text(item.time.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !expanded {
                        let detail = item.payload.detailText
                            .split(whereSeparator: \.isNewline).joined(separator: " ")
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.callout).foregroundStyle(.secondary)
                                .lineLimit(2).truncationMode(.tail)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }

        @ViewBuilder private var expandedContent: some View {
            let text = item.payload.detailText
            if text.isEmpty {
                Text("(no content)").font(.caption).foregroundStyle(.tertiary)
            } else if let json = JSONHighlighter.highlightedIfJSON(text) {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(capped(text))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private func capped(_ text: String) -> String {
            let limit = 8_000
            return text.count > limit ? String(text.prefix(limit)) + "\n… (truncated)" : text
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

private extension View {
    /// Constrain the chart's x-axis to `range` (zoom); unchanged when nil.
    @ViewBuilder func chartXDomain(_ range: ClosedRange<Int>?) -> some View {
        if let range { chartXScale(domain: range) } else { self }
    }
}

/// A two-thumb range slider over 0...1. Updates the bindings live while
/// dragging, but only fires `onCommit` on release — so expensive observers
/// (the charts) re-render once instead of on every frame.
private struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let steps: Int
    var onCommit: () -> Void

    @State private var movingLower: Bool?
    private let thumb: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule().fill(.tint)
                    .frame(width: CGFloat(upper - lower) * usable, height: 4)
                    .offset(x: CGFloat(lower) * usable + thumb / 2)
                handle.offset(x: CGFloat(lower) * usable)
                handle.offset(x: CGFloat(upper) * usable)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let frac = fraction(value.location.x, usable: usable)
                        if movingLower == nil {
                            let start = fraction(value.startLocation.x, usable: usable)
                            movingLower = abs(start - lower) <= abs(start - upper)
                        }
                        if movingLower == true { lower = min(frac, upper) }
                        else { upper = max(frac, lower) }
                    }
                    .onEnded { _ in movingLower = nil; onCommit() }
            )
        }
    }

    private func fraction(_ x: CGFloat, usable: CGFloat) -> Double {
        let raw = Double(min(max((x - thumb / 2) / usable, 0), 1))
        guard steps > 1 else { return raw }
        let last = Double(steps - 1)
        return (raw * last).rounded() / last   // snap to the nearest event step
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumb, height: thumb)
            .overlay(Circle().stroke(.quaternary, lineWidth: 1))
            .shadow(radius: 1)
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
    var subtitle: String? = nil
    var accent: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3).bold()
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
