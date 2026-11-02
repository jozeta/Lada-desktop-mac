import XCTest
@testable import Lada

/// Exercises the real `CommandRunner` against system binaries (no shell, no `container` CLI needed).
final class CommandRunnerTests: XCTestCase {
    func testCapturesStdoutAndExitStatus() async throws {
        let result = try await CommandRunner().execute(
            executablePath: "/bin/echo",
            arguments: ["hello", "Låda"],
            timeoutSeconds: 10
        )
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello Låda")
    }

    func testPassesStdinToProcess() async throws {
        let result = try await CommandRunner().execute(
            executablePath: "/bin/cat",
            arguments: [],
            stdinData: Data("from-stdin".utf8),
            timeoutSeconds: 10
        )
        XCTAssertEqual(result.stdout, "from-stdin")
    }

    func testNonZeroExitIsReportedNotThrown() async throws {
        let result = try await CommandRunner().execute(
            executablePath: "/usr/bin/false",
            arguments: [],
            timeoutSeconds: 10
        )
        XCTAssertFalse(result.isSuccess)
    }

    func testTimeoutTerminatesProcessAndThrows() async {
        let start = Date()
        do {
            _ = try await CommandRunner().execute(
                executablePath: "/bin/sleep",
                arguments: ["30"],
                timeoutSeconds: 1
            )
            XCTFail("Expected a timeout error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("timed out"), "Unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "Process was not terminated at the timeout")
    }

    func testRejectsRelativeExecutablePath() async {
        do {
            _ = try await CommandRunner().execute(executablePath: "echo", arguments: ["x"], timeoutSeconds: 5)
            XCTFail("Expected relative executable path to be rejected")
        } catch {
            // expected
        }
    }
}
