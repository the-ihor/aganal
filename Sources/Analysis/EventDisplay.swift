import Foundation

/// Compact presentation of a normalized event, for the in-selection event list.
extension Event.Payload {
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
            var parts = ["in \(usage.inputTokens ?? 0)", "out \(usage.outputTokens ?? 0)"]
            if let total = usage.totalTokens { parts.append("total \(total)") }
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
