import SwiftUI
import AppKit

/// AGANAL macOS app entry point.
@main
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
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
