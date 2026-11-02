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

    func testAccumulatorKeepsMultibyteCharacterSplitAcrossChunks() {
        let bytes = Array("Låda ✓\n".utf8)
        // Split inside "å" (0xC3 0xA5): the first chunk ends with half a character.
        let splitIndex = 2
        let acc = StreamAccumulator()
        XCTAssertEqual(acc.appendStdout(Data(bytes[..<splitIndex])), [])
        XCTAssertEqual(acc.appendStdout(Data(bytes[splitIndex...])), ["Låda ✓"])
        XCTAssertEqual(acc.snapshot().0, "Låda ✓\n")
    }

    func testAccumulatorJoinsLineSplitAcrossChunksAndFlushesTail() {
        let acc = StreamAccumulator()
        XCTAssertEqual(acc.appendStderr(Data("#1 [inter".utf8)), [])
        XCTAssertEqual(acc.appendStderr(Data("nal] load\n#2 DO".utf8)), ["#1 [internal] load"])
        XCTAssertEqual(acc.flushPartialLines().1, ["#2 DO"])
    }

    func testStreamDeliversWholeLines() async throws {
        let lines = LineCollector()
        let result = try await CommandRunner().stream(
            executablePath: "/usr/bin/printf",
            arguments: ["a1\\nbå2\\nc3"],
            onStdoutLine: { lines.add($0) },
            onStderrLine: { _ in }
        )
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(lines.all, ["a1", "bå2", "c3"])
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
