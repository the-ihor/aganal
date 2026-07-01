import Foundation

/// One tool's usage count within a session.
struct ToolStat: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let count: Int
}

/// A token-usage data point at a position in the session, for charting.
struct TokenPoint: Identifiable, Sendable {
    let id: Int
    let eventIndex: Int        // position in the session's event sequence
    let output: Int            // per-turn output tokens
    let cumulativeOutput: Int  // running total of output tokens
    let context: Int           // total/context tokens reported at this point
}

/// Aggregate, provider-agnostic metrics over a normalized `Session` — the
/// per-session view AGANAL presents. Headlined by tool usage.
struct SessionSummary: Sendable {
    let events: Int
    let messages: Int
    let reasoning: Int
    let toolCalls: Int
    let toolResults: Int
    let toolFailures: Int
    let outputTokens: Int
    let peakContextTokens: Int
    let tools: [ToolStat]          // sorted by count, descending
    let tokenSeries: [TokenPoint]      // time-ordered, points with timestamps only
    let contextBreakdown: [ContextPoint]  // cumulative estimated tokens by category

    /// Aggregate metrics over `session`. When `range` is given, only events whose
    /// index falls in it are counted, so the whole page can scope to a selection.
    /// Event indices in the chart series stay absolute so they align with the
    /// (range-zoomed) chart x-axis; cumulative totals restart within the range.
    init(_ session: Session, range: ClosedRange<Int>? = nil) {
        var counts: [String: Int] = [:]
        var events = 0
        var messages = 0, reasoning = 0, toolCalls = 0, toolResults = 0, failures = 0
        var outputTokens = 0, peak = 0
        var series: [TokenPoint] = []
        var cumulativeOutput = 0
        var breakdown: [ContextPoint] = []
        var runningByCategory: [TokenCategory: Int] = [:]

        for (eventIndex, event) in session.events.enumerated() {
            if let range, !range.contains(eventIndex) { continue }
            events += 1
            var contribution: (TokenCategory, Int)?
            switch event.payload {
            case .message(let message):
                messages += 1
                contribution = (message.role == .user ? .user : .assistant,
                                Self.estimateTokens(message.text))
            case .reasoning(let reasoningEvent):
                reasoning += 1
                contribution = (.reasoning, Self.estimateTokens(reasoningEvent.text))
            case .toolCall(let call):
                toolCalls += 1
                counts[call.name, default: 0] += 1
                contribution = (.toolCalls, Self.estimateTokens(call.arguments))
            case .toolResult(let result):
                toolResults += 1
                if result.isError { failures += 1 }
                contribution = (.toolResults, Self.estimateTokens(result.output))
            case .tokenUsage(let usage):
                let out = usage.outputTokens ?? 0
                outputTokens += out
                let context = usage.contextTokens ?? usage.totalTokens ?? 0
                peak = max(peak, context)
                cumulativeOutput += out
                series.append(TokenPoint(
                    id: series.count,
                    eventIndex: eventIndex,
                    output: out,
                    cumulativeOutput: cumulativeOutput,
                    context: context))
            case .lifecycle:
                break
            }

            // Snapshot cumulative tokens for every category at each text event,
            // so the stacked area is fully defined at every x.
            if let (category, tokens) = contribution, tokens > 0 {
                runningByCategory[category, default: 0] += tokens
                for category in TokenCategory.allCases {
                    breakdown.append(ContextPoint(
                        id: breakdown.count,
                        eventIndex: eventIndex,
                        category: category.rawValue,
                        tokens: runningByCategory[category, default: 0]))
                }
            }
        }

        self.events = events
        self.messages = messages
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.toolFailures = failures
        self.outputTokens = outputTokens
        self.peakContextTokens = peak
        self.tools = counts
            .map { ToolStat(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        self.tokenSeries = series
        self.contextBreakdown = breakdown
    }

    /// Rough token estimate for a piece of text (≈ 4 characters per token).
    static func estimateTokens(_ text: String) -> Int {
        text.isEmpty ? 0 : max(text.count / 4, 1)
    }
}
