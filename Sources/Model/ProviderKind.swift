import Foundation

/// The coding assistant a session originated from. Add a case here when
/// teaching AGANAL to read a new provider's on-disk format.
enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case codex
    case claudeCode = "claude-code"
    case geminiCli = "gemini-cli"
    case qwenCode = "qwen-code"
    case cursor
    case opencode
    case antigravity

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .geminiCli: return "Gemini CLI"
        case .qwenCode: return "Qwen Code"
        case .cursor: return "Cursor"
        case .opencode: return "opencode"
        case .antigravity: return "Antigravity"
        }
    }

    /// SF Symbol fallback for the provider (the real logo is drawn by `ProviderLogo`).
    var systemImage: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claudeCode: return "sparkles"
        case .geminiCli: return "sparkle"
        case .qwenCode: return "circle.hexagongrid"
        case .cursor: return "cube"
        case .opencode: return "square.on.square"
        case .antigravity: return "arrow.up.circle"
        }
    }
}
