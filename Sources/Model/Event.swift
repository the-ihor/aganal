import Foundation

/// Who produced a message, normalized across providers. Codex's `developer`
/// role and Claude's `system` collapse to `.system`.
enum Role: String, Sendable {
    case user, assistant, system, tool, unknown

    init(token: String?) {
        switch token {
        case "user": self = .user
        case "assistant": self = .assistant
        case "system", "developer": self = .system
        case "tool": self = .tool
        default: self = .unknown
        }
    }
}

struct Message: Sendable {
    let role: Role
    let text: String
}

/// Model thinking/reasoning. Note Codex stores reasoning encrypted, so its
/// `text` is frequently empty even when a reasoning record exists.
struct Reasoning: Sendable {
    let text: String
}

/// A model's request to run a tool — Codex `function_call`, Claude `tool_use`.
struct ToolCall: Sendable {
    let id: String?          // pairs with `ToolResult.callID`
    let name: String         // e.g. "Bash", "Read", "exec_command"
    let arguments: String    // raw JSON arguments, preserved verbatim
}

/// The outcome of a tool call — Codex `function_call_output`, Claude
/// `tool_result`.
struct ToolResult: Sendable {
    let callID: String?      // pairs with `ToolCall.id`
    let output: String
    let isError: Bool
    var exitCode: Int?
    var durationSeconds: Double?
}

/// Token accounting for a single turn. Providers report this incrementally so
/// summing across a session is meaningful; `totalTokens` is the cumulative
/// context size at the time of the record where the provider exposes it.
struct TokenUsage: Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedInputTokens: Int?
    var totalTokens: Int?
}

/// Session/turn lifecycle markers.
enum Lifecycle: Sendable {
    case taskStarted
    case taskCompleted
    case patchApplied
    case other(String)
}

/// One normalized record in a session, with its wall-clock time when known.
struct Event: Sendable {
    let timestamp: Date?
    let payload: Payload

    enum Payload: Sendable {
        case message(Message)
        case reasoning(Reasoning)
        case toolCall(ToolCall)
        case toolResult(ToolResult)
        case tokenUsage(TokenUsage)
        case lifecycle(Lifecycle)
    }
}
