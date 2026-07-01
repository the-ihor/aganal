import Foundation

// AGANAL is a native macOS app, or a command-line tool for AI agents:
//   AGANAL <command>   — CLI (sources/sessions/search/analytics/events/overview)
//   AGANAL             — launches the app
// The CLI path reuses the core and never starts SwiftUI.
let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case let command? where CLI.commands.contains(command) || ["help", "--help", "-h"].contains(command):
    exit(CLI.run(arguments))
default:
    AganalApp.main()
}
