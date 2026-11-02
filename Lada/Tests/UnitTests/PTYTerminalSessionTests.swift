import XCTest
@testable import Lada

@MainActor
final class PTYTerminalSessionTests: XCTestCase {
    /// Regression: the PTY read handler runs on a background queue; under Swift 6 it trapped
    /// (dispatch_assert_queue) the moment output arrived, crashing the app when the Terminal tab
    /// was opened.
    func testOutputArrivingOnBackgroundQueueIsDelivered() async throws {
        let session = PTYTerminalSession()
        let container = ContainerModel(id: "pty-test", imageReference: "alpine:latest", state: .running)
        // /bin/echo stands in for the CLI: it prints its arguments (`exec -i -t pty-test /bin/sh`)
        // into the pseudo-terminal and exits.
        session.startContainerSession(executablePath: "/bin/echo", container: container, shell: "/bin/sh")
        let deadline = Date().addingTimeInterval(5)
        while !session.outputBuffer.contains("exec -i -t pty-test /bin/sh"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(session.outputBuffer.contains("exec -i -t pty-test /bin/sh"), session.outputBuffer)
        while session.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(session.isRunning)
        session.terminateSession()
    }

    func testDecoderKeepsMultibyteCharactersSplitAcrossReads() {
        let decoder = PTYOutputDecoder()
        let bytes = Array("Låda ✓ ok".utf8)
        var out = ""
        for b in bytes { out += decoder.decode([b]) }   // worst case: one byte per read
        XCTAssertEqual(out, "Låda ✓ ok")
    }

    /// Opt-in: a real `container exec -i -t` session (skipped unless `LADA_LIVE_CONTAINER` is set).
    func testLiveShellSessionRoundTrip() async throws {
        guard let id = ProcessInfo.processInfo.environment["LADA_LIVE_CONTAINER"], !id.isEmpty else {
            throw XCTSkip("Set LADA_LIVE_CONTAINER to a running container ID.")
        }
        let session = PTYTerminalSession()
        let container = ContainerModel(id: id, imageReference: "live", state: .running)
        session.startContainerSession(executablePath: "/usr/local/bin/container", container: container, shell: "/bin/sh")
        try await Task.sleep(for: .seconds(2))
        session.sendInput("echo lada-pty-$((40+2))\n")
        let deadline = Date().addingTimeInterval(10)
        while !session.outputBuffer.contains("lada-pty-42"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(session.outputBuffer.contains("lada-pty-42"), session.outputBuffer)
        session.terminateSession()
    }

    /// A stand-in for `container exec -i -t …`: ignores its arguments and echoes stdin back.
    private func makeEchoShell() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lada-pty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("fake-container")
        try "#!/bin/sh\nexec /bin/cat\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    private func waitFor(_ condition: @autoclosure () -> Bool, seconds: Double = 5) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    /// Regression: when a session was replaced (switching tabs or containers), the old process's
    /// exit handler ran afterwards and tore down the *new* session, so typed commands were dropped.
    func testReplacingASessionKeepsTheNewOneUsable() async throws {
        let shell = try makeEchoShell()
        let session = PTYTerminalSession()
        let first = ContainerModel(id: "first", imageReference: "alpine", state: .running)
        let second = ContainerModel(id: "second", imageReference: "alpine", state: .running)

        session.startContainerSession(executablePath: shell, container: first)
        try await waitFor(session.isRunning)
        session.startContainerSession(executablePath: shell, container: second)
        // Give the first process's termination handler time to run.
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertTrue(session.isRunning, "new session was torn down by the old one's exit handler")
        session.sendInput("echo-after-switch\n")
        try await waitFor(session.outputBuffer.contains("echo-after-switch"))
        XCTAssertTrue(session.outputBuffer.contains("echo-after-switch"), session.outputBuffer)
        XCTAssertTrue(session.outputBuffer.contains("second"), "banner should name the new container")
        session.terminateSession()
    }
}

