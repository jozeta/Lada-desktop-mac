import XCTest
import SwiftUI
import AppKit
@testable import Lada

/// Opt-in visual snapshots for reviewing the UI without launching the app (skipped unless
/// `LADA_SNAPSHOT_DIR` is set):
///
///     LADA_SNAPSHOT_DIR=/tmp/lada-shots swift test --filter ViewSnapshotTests
///
/// Views are hosted in an off-screen window (so AppKit-backed controls such as Form, List and
/// TextEditor render too) against the mock runtime, in light and dark appearance.
@MainActor
final class ViewSnapshotTests: XCTestCase {
    private func outputDirectory() throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["LADA_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set LADA_SNAPSHOT_DIR to write PNG snapshots.")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAppState() async -> AppState {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let state = AppState(preferences: preferences, injectedService: MockContainerRuntimeService())
        await state.refreshAll(isUserInitiated: false)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(40))
            await state.sampleAllRunningContainersTelemetry()
        }
        return state
    }

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 1100, height: 760)) throws {
        let dir = try outputDirectory()
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            window.orderOut(nil)
        }
    }

    func testSettingsSnapshots() async throws {
        _ = try outputDirectory()
        let state = await makeAppState()
        for tab in ["general", "runtime", "resources", "appearance", "notifications", "diagnostics", "advanced"] {
            try snapshot(SettingsView(appState: state, initialTab: tab), name: "settings-\(tab)")
        }
    }

    func testMainWindowSnapshots() async throws {
        _ = try outputDirectory()
        let state = await makeAppState()
        for section in NavigationSection.allCases {
            state.selectedSection = section
            let slug = section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            try snapshot(MainWindowView(appState: state), name: "main-\(slug)", size: CGSize(width: 1400, height: 900))
        }
        // Container inspector for the running mock container.
        state.selectedSection = .containers
        state.selectedContainerID = state.containers.first { $0.state == .running }?.id
        try snapshot(MainWindowView(appState: state), name: "main-container-detail", size: CGSize(width: 1400, height: 900))
    }
}
