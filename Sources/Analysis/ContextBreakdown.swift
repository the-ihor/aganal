import Foundation

/// What produced a chunk of context — the categories of the breakdown chart.
enum TokenCategory: String, CaseIterable, Sendable {
    case user = "User"
    case assistant = "Assistant"
    case reasoning = "Reasoning"
    case toolCalls = "Tool calls"
    case toolResults = "Tool results"
}

/// One stacked-area data point: a category's *cumulative* estimated tokens at a
/// moment in the session. Token counts are estimated (≈ chars ÷ 4) because the
/// transcripts don't attribute tokens to a source.
struct ContextPoint: Identifiable, Sendable {
    let id: Int
    let eventIndex: Int
    let category: String
    let tokens: Int
}
