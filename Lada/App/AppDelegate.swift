import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public weak var appState: AppState?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        guard let appState else { return }
        Task {
            await appState.refreshAll()
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func application(_ sender: NSApplication, open urls: [URL]) {
        guard let appState, let first = urls.first else { return }
        _ = appState.handleDroppedDockerfile(url: first)
    }
}
