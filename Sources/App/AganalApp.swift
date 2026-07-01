import SwiftUI
import AppKit

/// AGANAL macOS app. Launched from `main.swift` (which also routes `AGANAL mcp`
/// to the stdio MCP server without starting the UI).
struct AganalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("AGANAL") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 580)
        }
        .windowStyle(.titleBar)
    }
}

/// Because the app is launched from the command line (`swift run`) rather than
/// from a signed `.app` bundle, it must promote itself to a regular UI app and
/// pull its window to the foreground; otherwise it would launch as a faceless
/// background process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Set the Dock/app icon at runtime: launched via `swift run`, there is
        // no signed bundle to carry an AppIcon asset, so load it from resources.
        if let url = Bundle.module.url(forResource: "AppIcon-1024", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
