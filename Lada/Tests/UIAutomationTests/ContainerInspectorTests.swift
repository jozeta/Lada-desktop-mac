import XCTest
import SwiftUI
import AppKit
@testable import Lada

/// Drives the real Containers screen in an off-screen window: switching containers and tabs must
/// reconnect the terminal to the selected container.
@MainActor
final class ContainerInspectorTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.contentView = nil
        window?.orderOut(nil)
        window = nil
    }

    /// Stand-in for the `container` CLI: records the container ID of each
    /// `exec -i -t <id> <shell>` and then echoes stdin like a shell would.
    private func makeRecordingCLI() throws -> (path: String, log: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lada-inspector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("sessions.log")
        let script = dir.appendingPathComponent("container")
        try "#!/bin/sh\necho \"$4\" >> '\(log.path)'\nexec /bin/cat\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script.path, log)
    }

    private func pump(_ seconds: Double = 0.6) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func sessions(_ log: URL) -> [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func testTerminalFollowsContainerAndTabSwitches() async throws {
        let mock = MockContainerRuntimeService()
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: mock)
        await appState.refreshAll(isUserInitiated: false)
        // Two running containers.
        if let stopped = appState.containers.first(where: { $0.state != .running }) {
            try await mock.startContainer(id: stopped.id)
            await appState.refreshAll(isUserInitiated: false)
        }
        let running = appState.containers.filter { $0.state == .running }.map(\.id)
        XCTAssertGreaterThanOrEqual(running.count, 2)
        let (a, b) = (running[0], running[1])

        let cli = try makeRecordingCLI()
        appState.installation = RuntimeInstallation(isInstalled: true, executablePath: cli.path)
        appState.selectedSection = .containers
        appState.selectedContainerID = a
        appState.containerInspectorTab = .terminal

        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1300, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: ContainersView(appState: appState).frame(width: 1300, height: 820))
        win.orderBack(nil)
        window = win
        pump()
        XCTAssertEqual(sessions(cli.log), [a], "terminal opens for the selected container")

        appState.selectedContainerID = b
        pump()
        XCTAssertEqual(sessions(cli.log), [a, b], "selecting another container reconnects the terminal to it")
        XCTAssertEqual(appState.containerInspectorTab, .terminal, "the tab stays on Terminal")

        appState.containerInspectorTab = .logs
        pump()
        appState.containerInspectorTab = .terminal
        pump()
        XCTAssertEqual(sessions(cli.log), [a, b, b], "returning to the Terminal tab starts a fresh session")

        for tab in ContainerDetailView.DetailTab.allCases {
            appState.containerInspectorTab = tab
            pump(0.15)
        }
        XCTAssertEqual(appState.containerInspectorTab, ContainerDetailView.DetailTab.allCases.last)
    }

    /// Opt-in: types into the real terminal view (synthesized key events, like a keyboard) against
    /// a running container and checks the shell answers. Skipped unless `LADA_LIVE_CONTAINER` is set;
    /// with `LADA_SNAPSHOT_DIR` it also saves a picture of the terminal.
    func testLiveTypingInTerminalView() async throws {
        guard let id = ProcessInfo.processInfo.environment["LADA_LIVE_CONTAINER"], !id.isEmpty else {
            throw XCTSkip("Set LADA_LIVE_CONTAINER to a running container ID.")
        }
        let container = ContainerModel(id: id, imageReference: "live", state: .running)
        let view = InteractiveTerminalView(container: container, executablePath: "/usr/local/bin/container")
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view.frame(width: 820, height: 420))
        win.contentView = host
        win.orderBack(nil)
        window = win
        try await Task.sleep(for: .seconds(2.5))

        func findTextView(_ v: NSView) -> InteractivePTYCanvasRepresentable.PTYKeyCapturingTextView? {
            if let t = v as? InteractivePTYCanvasRepresentable.PTYKeyCapturingTextView { return t }
            for sub in v.subviews { if let t = findTextView(sub) { return t } }
            return nil
        }
        let textView = try XCTUnwrap(findTextView(host))
        for ch in "ls /etc | head -3; echo lada-typed-$((6*7))" {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber, context: nil, characters: String(ch), charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0)!
            textView.keyDown(with: e)
        }
        textView.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        try await Task.sleep(for: .seconds(1.5))
        let text = textView.string
        XCTAssertTrue(text.contains("lada-typed-42"), text)
        XCTAssertFalse(text.contains("\u{1B}"), "no raw escape codes on screen")

        if let dir = ProcessInfo.processInfo.environment["LADA_SNAPSHOT_DIR"], !dir.isEmpty {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
                win.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(300))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("terminal-\(name).png"))
                }
            }
        }
    }
}

