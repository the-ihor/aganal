import Foundation

/// Coarse category of an event — the axis the Events page filters on.
enum EventKind: String, CaseIterable, Identifiable, Hashable {
    case message, reasoning, toolCall, toolResult, tokens, lifecycle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .message: return "Messages"
        case .reasoning: return "Reasoning"
        case .toolCall: return "Tool calls"
        case .toolResult: return "Results"
        case .tokens: return "Tokens"
        case .lifecycle: return "Lifecycle"
        }
    }

    var icon: String {
        switch self {
        case .message: return "bubble.left.fill"
        case .reasoning: return "brain"
        case .toolCall: return "wrench.and.screwdriver.fill"
        case .toolResult: return "arrow.turn.down.right"
        case .tokens: return "number"
        case .lifecycle: return "flag.fill"
        }
    }
}

/// Compact presentation of a normalized event, for the in-selection event list.
extension Event.Payload {
    var kind: EventKind {
        switch self {
        case .message: return .message
        case .reasoning: return .reasoning
        case .toolCall: return .toolCall
        case .toolResult: return .toolResult
        case .tokenUsage: return .tokens
        case .lifecycle: return .lifecycle
        }
    }

    var icon: String {
        switch self {
        case .message(let message): return message.role == .user ? "person.fill" : "bubble.left.fill"
        case .reasoning: return "brain"
        case .toolCall: return "wrench.and.screwdriver.fill"
        case .toolResult(let result): return result.isError ? "exclamationmark.triangle.fill" : "arrow.turn.down.right"
        case .tokenUsage: return "number"
        case .lifecycle: return "flag.fill"
        }
    }

    var kindLabel: String {
        switch self {
        case .message(let message): return "Message · \(message.role.rawValue)"
        case .reasoning: return "Reasoning"
        case .toolCall(let call): return "Tool · \(call.name)"
        case .toolResult: return "Result"
        case .tokenUsage: return "Tokens"
        case .lifecycle: return "Lifecycle"
        }
    }

    var detailText: String {
        switch self {
        case .message(let message): return message.text
        case .reasoning(let reasoning): return reasoning.text
        case .toolCall(let call): return call.arguments
        case .toolResult(let result): return result.output
        case .tokenUsage(let usage):
            // Token records are counts only — no text. Show the full breakdown.
            var parts: [String] = []
            if let value = usage.inputTokens { parts.append("input \(value)") }
            if let value = usage.cachedInputTokens { parts.append("cached \(value)") }
            if let value = usage.outputTokens { parts.append("output \(value)") }
            if let value = usage.contextTokens { parts.append("context \(value)") }
            if let value = usage.totalTokens { parts.append("total \(value)") }
            return parts.joined(separator: " · ")
        case .lifecycle(let lifecycle):
            switch lifecycle {
            case .taskStarted: return "task started"
            case .taskCompleted: return "task completed"
            case .patchApplied: return "patch applied"
            case .other(let name): return name
            }
        }
    }

    var isError: Bool {
        if case .toolResult(let result) = self { return result.isError }
        return false
    }
}
