import Foundation

/// One tool's usage count within a session.
struct ToolStat: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let count: Int
}

/// Aggregate, provider-agnostic metrics over a normalized `Session` — the
/// per-session view AGANAL presents. Headlined by tool usage.
struct SessionSummary: Sendable {
    let messages: Int
    let reasoning: Int
    let toolCalls: Int
    let toolResults: Int
    let toolFailures: Int
    let outputTokens: Int
    let peakContextTokens: Int
    let tools: [ToolStat]   // sorted by count, descending

    init(_ session: Session) {
        var counts: [String: Int] = [:]
        var messages = 0, reasoning = 0, toolCalls = 0, toolResults = 0, failures = 0
        var outputTokens = 0, peak = 0

        for event in session.events {
            switch event.payload {
            case .message:
                messages += 1
            case .reasoning:
                reasoning += 1
            case .toolCall(let call):
                toolCalls += 1
                counts[call.name, default: 0] += 1
            case .toolResult(let result):
                toolResults += 1
                if result.isError { failures += 1 }
            case .tokenUsage(let usage):
                outputTokens += usage.outputTokens ?? 0
                peak = max(peak, usage.totalTokens ?? 0)
            case .lifecycle:
                break
            }
        }

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
    }
}
