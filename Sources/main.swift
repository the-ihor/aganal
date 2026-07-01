import Foundation

// AGANAL is a native macOS app, or a command-line tool for AI agents:
//   AGANAL <command>   — CLI (sources/sessions/search/analytics/events/overview)
//   AGANAL mcp         — Model Context Protocol server over stdio
//   AGANAL             — launches the app
// The CLI/MCP paths reuse the core and never start SwiftUI.
let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "mcp":
    MCPServer().run()
case let command? where CLI.commands.contains(command) || ["help", "--help", "-h"].contains(command):
    exit(CLI.run(arguments))
default:
    AganalApp.main()
}
