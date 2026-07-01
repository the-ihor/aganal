import SwiftUI
import Charts
import AppKit

/// Right column: the parsed session's metadata, headline stats, and tool-usage
/// breakdown.
struct SessionDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: DetailMode = .analysis

    // Event-index window, shared across tabs. Lifted here so it lives above the
    // tab selector and applies to both the Analysis and Events views.
    @State private var lowerFraction = 0.0
    @State private var upperFraction = 1.0
    @State private var appliedRange: ClosedRange<Int>?

    // Metrics recomputed for the selected window; nil means "use the whole
    // session". Recomputed only on commit (not while dragging the slider).
    @State private var scopedSummary: SessionSummary?

    // Filters applied on the Events tab; also the target of a tool-usage click.
    @State private var filter = EventFilter()

    var body: some View {
        Group {
            if let ref = model.selectedSession {
                VStack(spacing: 0) {
                    if (mode == .analysis || mode == .events), let session = model.loadedSession,
                       session.events.count > 1 {
                        EventRangeControl(
                            eventCount: session.events.count,
                            lowerFraction: $lowerFraction,
                            upperFraction: $upperFraction,
                            appliedRange: $appliedRange)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                        Divider()
                    }
                    Picker("Mode", selection: $mode) {
                        Text("Analysis").tag(DetailMode.analysis)
                        Text("Agent").tag(DetailMode.agent)
                        Text("Events").tag(DetailMode.events)
                        if rawAvailable {
                            Text("Raw JSONL").tag(DetailMode.raw)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(8)
                    Divider()
                    switch mode {
                    case .analysis: analysis
                    case .agent: agent
                    case .events: events
                    case .raw: if rawAvailable { RawSessionView(ref: ref) } else { analysis }
                    }
                }
                // Reset the shared window and filters whenever a session loads;
                // also leave Raw if it isn't available for this provider.
                .onChange(of: model.selectedSession?.id) {
                    clearRange()
                    filter = EventFilter()
                    if mode == .raw, !rawAvailable { mode = .analysis }
                }
                // Rescope the analysis metrics when the committed window changes.
                .onChange(of: appliedRange) { recomputeScopedSummary() }
            } else {
                ContentUnavailableLabel("Select a session", systemImage: "doc.text.magnifyingglass")
            }
        }
        .navigationTitle(navigationTitle)
    }

    /// opencode stores sessions in SQLite, not a JSONL file, so Raw is hidden.
    private var rawAvailable: Bool { model.selectedSession?.provider != .opencode }

    private var navigationTitle: String {
        switch mode {
        case .analysis: return "Analysis"
        case .agent: return "Analyse with Agent"
        case .events: return "Events"
        case .raw: return "Raw JSONL"
        }
    }

    @ViewBuilder private var analysis: some View {
        if model.isParsing {
            ProgressView("Parsing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            ContentUnavailableLabel(error, systemImage: "exclamationmark.triangle")
        } else if let session = model.loadedSession, let summary = model.summary {
            ScrollView {
                SessionDetailContent(session: session,
                                     summary: scopedSummary ?? summary,
                                     appliedRange: appliedRange,
                                     onSelectTool: showEvents(forTool:))
                    .padding(20)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var events: some View {
        if model.isParsing {
            ProgressView("Parsing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            ContentUnavailableLabel(error, systemImage: "exclamationmark.triangle")
        } else if let session = model.loadedSession {
            EventsView(session: session, appliedRange: appliedRange, filter: $filter)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var agent: some View {
        if model.isParsing {
            ProgressView("Parsing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let session = model.loadedSession, let ref = model.selectedSession {
            AgentPromptView(session: session, path: ref.path.path)
        } else {
            Color.clear
        }
    }

    /// Filter the Events tab to one tool's calls and results, then switch to it.
    private func showEvents(forTool name: String) {
        filter = EventFilter(kinds: [.toolCall, .toolResult], toolName: name)
        mode = .events
    }

    private func clearRange() {
        lowerFraction = 0
        upperFraction = 1
        appliedRange = nil
    }

    /// Recompute the range-scoped metrics, or drop back to the whole session.
    private func recomputeScopedSummary() {
        if let range = appliedRange, let session = model.loadedSession {
            scopedSummary = SessionSummary(session, range: range)
        } else {
            scopedSummary = nil
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
    let appliedRange: ClosedRange<Int>?          // committed event-index window (from parent)
    var onSelectTool: (String) -> Void = { _ in }

    @State private var tokenMetric: TokenMetric = .cumulative
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                StatTile(label: "Events", value: summary.events.formatted())
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
            if !summary.tokenSeries.isEmpty {
                tokenChart
            }
            if !summary.contextBreakdown.isEmpty {
                contextChart
            }
            if !summary.toolBreakdown.isEmpty {
                toolChart
            }
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

    @ViewBuilder private var toolChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tool calls over time").font(.headline)
            Chart {
                ForEach(pauseIndices, id: \.self) { index in
                    RuleMark(x: .value("Event", index))
                        .lineStyle(StrokeStyle(lineWidth: 6))
                        .foregroundStyle(.gray.opacity(0.18))
                }
                ForEach(summary.toolBreakdown) { point in
                    AreaMark(
                        x: .value("Event", point.eventIndex),
                        y: .value("Calls", point.count)
                    )
                    .foregroundStyle(by: .value("Tool", point.tool))
                    .interpolationMethod(.monotone)
                }
            }
            .chartForegroundStyleScale(domain: summary.tools.map(\.name))
            .chartXDomain(chartDomain)
            .frame(height: 220)
            Text("Cumulative tool calls, stacked by tool.")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.displayTitle)
                .font(.title2).bold()
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ProviderLogo(kind: session.provider, size: 15)
                    Text(session.provider.displayName)
                }
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
                    Button { onSelectTool(tool.name) } label: {
                        ToolBar(name: tool.name, count: tool.count, maxCount: maxCount)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(tool.name) events")
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

/// Event-index window selector shown above the tab picker. Owns the live
/// slider fractions (bound from the parent so the window survives tab switches)
/// and commits the chosen span to `appliedRange` on release.
private struct EventRangeControl: View {
    let eventCount: Int
    @Binding var lowerFraction: Double
    @Binding var upperFraction: Double
    @Binding var appliedRange: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Event range").font(.headline)
                Spacer()
                if lowerFraction > 0.001 || upperFraction < 0.999 {
                    Button("Reset") { reset() }.buttonStyle(.borderless)
                }
            }
            RangeSlider(lower: $lowerFraction, upper: $upperFraction,
                        steps: eventCount, onCommit: commit)
                .frame(height: 22)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Nearest event index for a 0...1 slider fraction.
    private func eventIndex(_ fraction: Double, maxIndex: Int) -> Int {
        min(max(Int((fraction * Double(maxIndex)).rounded()), 0), maxIndex)
    }

    private var label: String {
        guard eventCount >= 2 else { return "" }
        let maxIndex = eventCount - 1
        let lo = eventIndex(lowerFraction, maxIndex: maxIndex)
        let hi = eventIndex(upperFraction, maxIndex: maxIndex)
        if lo <= 0, hi >= maxIndex { return "All \(eventCount) events" }
        return "Events \(lo + 1)–\(hi + 1) of \(eventCount)"
    }

    /// Apply the slider window once, on release.
    private func commit() {
        guard eventCount >= 2 else { appliedRange = nil; return }
        let maxIndex = eventCount - 1
        let lo = eventIndex(lowerFraction, maxIndex: maxIndex)
        let hi = max(eventIndex(upperFraction, maxIndex: maxIndex), lo)
        appliedRange = (lo <= 0 && hi >= maxIndex) ? nil : lo...hi
    }

    private func reset() {
        lowerFraction = 0
        upperFraction = 1
        appliedRange = nil
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
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

/// The kinds of ready-to-paste prompt the Agent tab can produce.
enum AgentPromptKind: String, CaseIterable, Identifiable {
    case analyze = "Analyze"
    case summarize = "Summarize"
    case findErrors = "Find errors"
    case cost = "Cost review"
    case critique = "Critique"
    case handoff = "Continue"

    var id: String { rawValue }

    /// The kind-specific task, appended to the shared preamble.
    fileprivate var task: String {
        switch self {
        case .analyze:
            return """
            Then write a short analysis:
              • What was the agent asked to do, and did it finish?
              • What did it actually do — dominant tools, notable steps, errors or retries?
              • Token & context cost — output tokens, and peak context vs the window.
              • Anything notable or worth improving.
            """
        case .summarize:
            return "Then write a tight summary (5–8 bullets): the goal, the key steps the agent " +
                   "took, the outcome, and anything surprising. No fluff."
        case .findErrors:
            return "Then hunt for what went wrong. Start with `events … --type toolResult --limit 200` " +
                   "and find results with \"isError\": true. For each, quote the failing command/args and " +
                   "the error, explain the likely cause and the fix, and note any repeated retries."
        case .cost:
            return "Then focus on token & context cost. From `analytics`, report output tokens and peak " +
                   "context vs the window; use the tokens-over-time series to find the turns that drove the " +
                   "spend, and suggest concrete ways to cut it (leaner tool output, tighter context, fewer " +
                   "redundant reads)."
        case .critique:
            return "Then critique the approach. Where did the agent waste steps, re-read files, or go down " +
                   "dead ends? What would a senior engineer have done differently? Be specific and cite events."
        case .handoff:
            return "Then produce a handoff brief so another agent can continue: the original goal, what's " +
                   "already done, what's left, the repo/cwd and branch, and the exact next steps."
        }
    }

    /// The full prompt for a session, with the CLI paths filled in.
    static func prompt(_ kind: AgentPromptKind, session: Session, path: String) -> String {
        let bin = Bundle.main.executableURL?.path ?? "aganal"
        return """
        You are analyzing one AI coding-agent session with the AGANAL CLI, which reads the \
        session log and reports metrics. Use it to load the data, then follow the task below.

        Session
          provider: \(session.provider.rawValue)
          title:    \(session.displayTitle)
          file:     \(path)

        Load the data (each command prints JSON):
          "\(bin)" analytics "\(path)"
              summary counts, tool usage, tokens over time, context by category
          "\(bin)" events "\(path)" --type toolResult --limit 100
              tool results — look for "isError": true
          "\(bin)" events "\(path)" --search "<keyword>"
              find specific moments (replace <keyword>)
          "\(bin)" --help
              every command and its options
        You can also read the raw log directly at the file path above.

        \(kind.task)
        """
    }
}

/// The "Analyse with Agent" tab: pick a prompt kind, then copy the ready-to-paste
/// prompt (with this session's path and provider filled in).
private struct AgentPromptView: View {
    let session: Session
    let path: String
    @State private var kind: AgentPromptKind = .analyze
    @State private var copied = false

    private var prompt: String { AgentPromptKind.prompt(kind, session: session, path: path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label("Prompt for an agent", systemImage: "sparkles")
                    .font(.headline)
                Spacer(minLength: 8)
                Picker("Kind", selection: $kind) {
                    ForEach(AgentPromptKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy prompt",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()
            ScrollView {
                Text(prompt)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .onChange(of: kind) { copied = false }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}
