import Foundation

/// The coding assistant a session originated from. Add a case here when
/// teaching AGANAL to read a new provider's on-disk format.
enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case codex
    case claudeCode = "claude-code"

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }
}
