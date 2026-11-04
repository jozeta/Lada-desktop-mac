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

    private func waitUntil(_ condition: @autoclosure () -> Bool, seconds: Double = 5) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    func testWorkSurvivesContainerTabAndSectionSwitches() async throws {
        let mock = MockContainerRuntimeService()
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: mock)
        await appState.refreshAll(isUserInitiated: false)
        if let stopped = appState.containers.first(where: { $0.state != .running }) {
            try await mock.startContainer(id: stopped.id)
            await appState.refreshAll(isUserInitiated: false)
        }
        let running = appState.containers.filter { $0.state == .running }.map(\.id)
        XCTAssertGreaterThanOrEqual(running.count, 2)
        let (a, b) = (running[0], running[1])

        let cli = try makeRecordingCLI()
        // Through the mock too, so a refresh's runtime discovery keeps the stand-in CLI.
        mock.simulatedInstallation = RuntimeInstallation(isInstalled: true, executablePath: cli.path, cliVersion: SemanticVersion(major: 1, minor: 6, patch: 1), helperPluginsPresent: true, defaultKernelInstalled: true)
        appState.installation = mock.simulatedInstallation
        appState.selectedSection = .containers
        appState.selectedContainerID = a
        appState.workspaces.select(.terminal, for: a)

        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 880), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: MainWindowView(appState: appState).frame(width: 1400, height: 880))
        win.orderBack(nil)
        window = win
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(sessions(cli.log), [a], "terminal opens for A")

        // Work in A's shell.
        let shellA = appState.workspaces.workspace(for: a).terminal
        try await waitUntil(shellA.isRunning)
        shellA.sendInput("work-in-A\r")
        try await waitUntil(shellA.outputBuffer.contains("work-in-A"))

        // Unsaved edit in A's Files tab state.
        let filesA = appState.workspaces.workspace(for: a).files
        filesA.currentPath = "/etc/nginx"
        filesA.fileEditorText = "unsaved change"

        // A → B: B gets its own shell and inherits the Terminal tab.
        appState.selectedContainerID = b
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(sessions(cli.log), [a, b])
        XCTAssertEqual(appState.workspaces.workspace(for: b).tab, .terminal)
        appState.workspaces.select(.logs, for: b)
        try await Task.sleep(for: .milliseconds(300))

        // Leave for Networks and the Image Library, then come back.
        appState.selectedSection = .networks
        try await Task.sleep(for: .milliseconds(400))
        appState.selectedSection = .imageLibrary
        try await Task.sleep(for: .milliseconds(400))
        appState.selectedSection = .containers
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(appState.selectedContainerID, b, "selection survives other sections")
        XCTAssertEqual(appState.workspaces.workspace(for: b).tab, .logs, "B is still on Logs")

        // B → A: the same shell, still running, with the earlier work on screen.
        appState.selectedContainerID = a
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(sessions(cli.log), [a, b], "no new session: A's shell kept running")
        XCTAssertTrue(shellA.isRunning)
        XCTAssertTrue(shellA.outputBuffer.contains("work-in-A"), shellA.outputBuffer)
        XCTAssertEqual(appState.workspaces.workspace(for: a).tab, .terminal, "A is still on Terminal")
        XCTAssertEqual(filesA.currentPath, "/etc/nginx")
        XCTAssertEqual(filesA.fileEditorText, "unsaved change")

        // Switching tabs inside A keeps the shell too.
        appState.workspaces.select(.files, for: a)
        try await Task.sleep(for: .milliseconds(300))
        appState.workspaces.select(.terminal, for: a)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(sessions(cli.log), [a, b])
        XCTAssertTrue(shellA.isRunning)
    }

    func testWorkspacesCloseWhenContainersGoAway() async throws {
        let store = ContainerWorkspaceStore()
        let cli = try makeRecordingCLI()
        let a = ContainerModel(id: "gone", imageReference: "alpine", state: .running)
        let ws = store.workspace(for: a.id)
        ws.terminal.startContainerSession(executablePath: cli.path, container: a)
        try await waitUntil(ws.terminal.isRunning)
        store.reconcile(with: [ContainerModel(id: "gone", imageReference: "alpine", state: .stopped)])
        XCTAssertFalse(ws.terminal.isRunning, "a stopped container's shell is ended")
        XCTAssertTrue(store.openContainerIDs.contains("gone"), "but its workspace is kept")
        store.reconcile(with: [])
        XCTAssertFalse(store.openContainerIDs.contains("gone"), "deleted containers lose their workspace")
    }

    func testStackEditsSurviveLeavingTheScreen() async throws {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: MockContainerRuntimeService())
        await appState.refreshAll(isUserInitiated: false)
        appState.editorDraftComposeYAML = "name: from-editor\nservices:\n  web:\n    image: nginx\n"
        appState.selectedSection = .stacks

        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1300, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: MainWindowView(appState: appState).frame(width: 1300, height: 820))
        win.orderBack(nil)
        window = win
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(appState.stacks.yamlText.contains("from-editor"), "editor draft is applied")
        XCTAssertNil(appState.editorDraftComposeYAML, "and consumed once")

        appState.stacks.yamlText += "  db:\n    image: postgres\n"
        appState.stacks.tab = .file
        appState.selectedSection = .networks
        try await Task.sleep(for: .milliseconds(300))
        appState.selectedSection = .stacks
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(appState.stacks.yamlText.contains("image: postgres"), "edits survive leaving Stacks")
        XCTAssertEqual(appState.stacks.tab, .file)
    }

    func testStartedStackIsGroupedInContainers() async throws {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: MockContainerRuntimeService())
        await appState.refreshAll(isUserInitiated: false)
        let template = try XCTUnwrap(ComposeStackTemplate.allTemplates.first { $0.id == "postgres-adminer" })
        appState.stacks.yamlText = template.instantiate()
        await appState.stacks.start(appState: appState)

        let members = appState.containers.filter { $0.composeProject == "pg-admin" }
        XCTAssertEqual(Set(members.map(\.id)), ["pg-admin-db", "pg-admin-ui"])
        XCTAssertEqual(appState.containers.first { $0.id == "pg-admin-db" }?.configuration.labels["com.lada.compose.service"], "db")

        // The table groups them under one collapsible stack row.
        appState.selectedSection = .containers
        appState.selectedContainerID = "stack:pg-admin"
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 880), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: MainWindowView(appState: appState).frame(width: 1400, height: 880))
        win.orderBack(nil)
        window = win
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(appState.selectedContainerID, "stack:pg-admin", "the stack row is a valid selection")

        appState.collapsedContainerStacks.insert("pg-admin")
        try await Task.sleep(for: .milliseconds(200))
        appState.selectedSection = .networks
        try await Task.sleep(for: .milliseconds(200))
        appState.selectedSection = .containers
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(appState.collapsedContainerStacks.contains("pg-admin"), "collapse state is remembered")

        if let dir = ProcessInfo.processInfo.environment["LADA_SNAPSHOT_DIR"], !dir.isEmpty {
            appState.collapsedContainerStacks.remove("pg-admin")
            try await Task.sleep(for: .milliseconds(300))
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if let host = win.contentView, let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("containers-stack-group.png"))
            }
        }
    }

    func testStacksStartEmptyAndClearAfterASuccessfulStart() async throws {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: MockContainerRuntimeService())
        await appState.refreshAll(isUserInitiated: false)
        let work = appState.stacks
        XCTAssertTrue(work.isEmpty, "Stacks starts empty")

        // Build your own: name it, add a service with the form's writer.
        work.newStack(named: "My Shop")
        XCTAssertEqual(work.parsed.projectName, "my-shop")
        work.yamlText = ComposeDocument.upsert(ComposeServiceSpec(serviceName: "web", containerName: "", imageReference: "nginx:1.31-alpine"), in: work.yamlText)
        work.rename(to: "shop")
        XCTAssertEqual(work.parsed.projectName, "shop")
        XCTAssertEqual(work.parsed.services.map(\.serviceName), ["web"])

        await work.start(appState: appState)
        XCTAssertTrue(work.isEmpty, "the window clears after a successful start")
        XCTAssertEqual(work.lastStarted, .init(name: "shop", serviceCount: 1))
        XCTAssertTrue(appState.containers.contains { $0.composeProject == "shop" && $0.state == .running })
        XCTAssertNotNil(work.deployedCompose(for: "shop"))

        // It can be reopened for editing (Containers → Open in Stacks).
        work.reopen(stack: "shop")
        XCTAssertEqual(work.parsed.services.map(\.serviceName), ["web"])

        // A failed start keeps everything so it can be fixed: postgres without a password is rejected.
        work.newStack(named: "broken")
        work.yamlText = ComposeDocument.upsert(ComposeServiceSpec(serviceName: "db", containerName: "", imageReference: "postgres:17-alpine"), in: work.yamlText)
        await work.start(appState: appState)
        XCTAssertFalse(work.isEmpty, "nothing is cleared when a service failed")
        XCTAssertTrue(work.consoleLines.contains { $0.contains("Failed to start 'db'") }, work.consoleLines.joined(separator: "\n"))
    }

    /// Opt-in: types into the real terminal view (synthesized key events, like a keyboard) against
    /// a running container and checks the shell answers. Skipped unless `LADA_LIVE_CONTAINER` is set;
    /// with `LADA_SNAPSHOT_DIR` it also saves a picture of the terminal.
    func testLiveTypingInTerminalView() async throws {
        guard let id = ProcessInfo.processInfo.environment["LADA_LIVE_CONTAINER"], !id.isEmpty else {
            throw XCTSkip("Set LADA_LIVE_CONTAINER to a running container ID.")
        }
        let container = ContainerModel(id: id, imageReference: "live", state: .running)
        let view = InteractiveTerminalView(container: container, executablePath: "/usr/local/bin/container", session: PTYTerminalSession())
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
