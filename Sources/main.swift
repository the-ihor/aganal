import Foundation

// AGANAL runs as a native macOS app, or — when invoked as `AGANAL mcp` — as a
// Model Context Protocol server over stdio, so an AI client can query session
// analytics. The MCP path reuses the core and never starts SwiftUI.
if CommandLine.arguments.dropFirst().first == "mcp" {
    MCPServer().run()
} else {
    AganalApp.main()
}
