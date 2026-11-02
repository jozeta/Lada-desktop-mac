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
}

