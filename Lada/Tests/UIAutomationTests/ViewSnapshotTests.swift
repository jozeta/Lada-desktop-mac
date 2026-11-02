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

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 1100, height: 760), settle: TimeInterval = 0.4) throws {
        let dir = try outputDirectory()
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(settle))
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

    /// Varied, realistic-looking samples (snapshot only) so curves, axis labels and the
    /// peak/average footer are visible; the mock's counters grow linearly and plot flat.
    private func injectVariedTelemetry(into state: AppState) {
        let now = Date()
        func sample(_ i: Int) -> ContainerPerformanceSample {
            let t = Double(i)
            return ContainerPerformanceSample(
                timestamp: now.addingTimeInterval(-Double(149 - i) * 2),
                cpuPercent: 18 + 12 * sin(t / 9) + (i % 37 == 0 ? 35 : 0),
                memoryUsageBytes: UInt64(160_000_000 + 20_000_000 * sin(t / 25)),
                memoryLimitBytes: 1_073_741_824,
                memoryPercent: 15 + 2 * sin(t / 25),
                networkRxRateBps: max(0, 60_000 + 50_000 * sin(t / 7)),
                networkTxRateBps: max(0, 25_000 + 20_000 * cos(t / 11)),
                diskReadRateBps: i % 29 < 3 ? 2_400_000 : 40_000,
                diskWriteRateBps: max(0, 300_000 + 250_000 * sin(t / 13)),
                numProcesses: 4,
                cpuCoresUsed: (18 + 12 * sin(t / 9)) / 50,
                allocatedCPUs: 2
            )
        }
        let series = (0..<150).map(sample)
        for c in state.containers where c.state == .running {
            state.containerTelemetryHistory[c.id] = series
        }
        state.systemTelemetryHistory = series
    }

    func testMainWindowSnapshots() async throws {
        _ = try outputDirectory()
        let state = await makeAppState()
        injectVariedTelemetry(into: state)
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

    /// The README screenshots (Mock Sandbox data), written as `readme-<name>-<appearance>.png`.
    func testReadmeScreenshots() async throws {
        _ = try outputDirectory()
        let state = await makeAppState()
        injectVariedTelemetry(into: state)
        let size = CGSize(width: 1400, height: 900)
        let running = state.containers.first { $0.state == .running }
        if let running {
            // Snapshot only: the mock has no rootfs image on disk to measure.
            state.containerDisks[running.id] = ContainerDiskSnapshot.make(allocatedBytes: 226_000_000, logicalSizeBytes: 549_755_813_888, hostAvailableBytes: 229_000_000_000)
        }

        state.selectedSection = .overview
        try snapshot(MainWindowView(appState: state), name: "readme-overview", size: size)

        state.selectedSection = .containers
        state.selectedContainerID = running?.id
        try snapshot(MainWindowView(appState: state), name: "readme-containers-overview", size: size)

        if let running {
            let workspace = state.workspaces.workspace(for: running.id)
            workspace.tab = .files
            workspace.files.entries = (try? await ContainerFileOperations(runtime: state.runtimeService, containerID: running.id).listDirectory("/")) ?? []
            // Longer settle so the mock directory listing has loaded.
            try snapshot(MainWindowView(appState: state), name: "readme-container-files", size: size, settle: 2.5)
            state.workspaces.workspace(for: running.id).tab = .overview
        }

        state.selectedSection = .stacks
        state.stacks.useTemplate(ComposeStackTemplate.allTemplates[0])
        try snapshot(MainWindowView(appState: state), name: "readme-compose-stacks", size: size)

        state.selectedSection = .imageLibrary
        try snapshot(MainWindowView(appState: state), name: "readme-image-library", size: size)

        state.selectedSection = .dockerfileEditor
        try snapshot(MainWindowView(appState: state), name: "readme-dockerfile-editor", size: size)
    }
}
