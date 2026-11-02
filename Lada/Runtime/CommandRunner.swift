import Foundation

public struct CommandExecutionResult: Sendable, Equatable {
    public let executablePath: String
    public let redactedCommand: String
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int

    public init(
        executablePath: String,
        redactedCommand: String,
        exitStatus: Int32,
        stdout: String,
        stderr: String,
        durationMs: Int
    ) {
        self.executablePath = executablePath
        self.redactedCommand = redactedCommand
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }

    public var isSuccess: Bool {
        exitStatus == 0
    }

    public var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public protocol CommandExecuting: Sendable {
    func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        stdinData: Data?,
        timeoutSeconds: TimeInterval?
    ) async throws -> CommandExecutionResult

    func stream(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) async throws -> CommandExecutionResult
}

public actor CommandRunner: CommandExecuting {
    public static let shared = CommandRunner()

    public init() {}

    public func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        timeoutSeconds: TimeInterval? = 60
    ) async throws -> CommandExecutionResult {
        let start = Date()
        let correlationID = String(UUID().uuidString.prefix(8)).lowercased()
        let redactedPreview = SecretRedactor.formatCommandPreview(executable: executablePath, arguments: arguments)

        guard executablePath.hasPrefix("/") else {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Executable path must be an absolute path: '\(executablePath)'.",
                suggestedRemediation: "Ensure runtime discovery resolves an absolute path such as `/usr/local/bin/container`.",
                isRetryable: false
            )
        }

        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LadaError(
                category: .missingPrerequisites,
                explanation: "Executable not found or not executable at '\(executablePath)'.",
                suggestedRemediation: "Install Apple's `container` CLI or update the executable path in Settings → Runtime.",
                isRetryable: true
            )
        }

        StructuredLogger.shared.log(.debug, subsystem: "CommandRunner", correlationID: correlationID, "Executing: \(redactedPreview)")

        return try await withTaskCancellationHandler {
            try await runProcess(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                stdinData: stdinData,
                timeoutSeconds: timeoutSeconds,
                redactedPreview: redactedPreview,
                correlationID: correlationID,
                startTime: start
            )
        } onCancel: {
            StructuredLogger.shared.log(.warning, subsystem: "CommandRunner", correlationID: correlationID, "Cancelled: \(redactedPreview)")
        }
    }

    public func stream(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) async throws -> CommandExecutionResult {
        let start = Date()
        let redactedPreview = SecretRedactor.formatCommandPreview(executable: executablePath, arguments: arguments)

        guard executablePath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LadaError(
                category: .missingPrerequisites,
                explanation: "Executable not found at '\(executablePath)'.",
                suggestedRemediation: "Install Apple's `container` CLI first.",
                isRetryable: true
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let standardPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (standardPaths + [existingPath]).filter { !$0.isEmpty }.joined(separator: ":")
        if let customEnv = environment {
            for (k, v) in customEnv { env[k] = v }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let accumulator = StreamAccumulator()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            accumulator.appendStdout(data).forEach(onStdoutLine)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            accumulator.appendStderr(data).forEach(onStderrLine)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    accumulator.appendStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile()).forEach(onStdoutLine)
                    accumulator.appendStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile()).forEach(onStderrLine)
                    let (lastOut, lastErr) = accumulator.flushPartialLines()
                    lastOut.forEach(onStdoutLine)
                    lastErr.forEach(onStderrLine)
                    let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                    let (outStr, errStr) = accumulator.snapshot()
                    let result = CommandExecutionResult(
                        executablePath: executablePath,
                        redactedCommand: redactedPreview,
                        exitStatus: proc.terminationStatus,
                        stdout: outStr,
                        stderr: errStr,
                        durationMs: durationMs
                    )
                    continuation.resume(returning: result)
                }

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: LadaError(
                        category: .internalError,
                        explanation: "Failed to launch process '\(executablePath)': \(error.localizedDescription)",
                        suggestedRemediation: "Verify executable permissions and path.",
                        isRetryable: false
                    ))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        stdinData: Data?,
        timeoutSeconds: TimeInterval?,
        redactedPreview: String,
        correlationID: String,
        startTime: Date
    ) async throws -> CommandExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let standardPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (standardPaths + [existingPath]).filter { !$0.isEmpty }.joined(separator: ":")
        if let customEnv = environment {
            for (k, v) in customEnv { env[k] = v }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if stdinData != nil {
            let p = Pipe()
            process.standardInput = p
            stdinPipe = p
        } else {
            stdinPipe = nil
        }

        let accumulator = StreamAccumulator()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { _ = accumulator.appendStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { _ = accumulator.appendStderr(data) }
        }

        let timeoutBox = TimeoutFlagBox()
        // A Task (Sendable) rather than a DispatchWorkItem, so it can be cancelled from the
        // @Sendable termination and cancellation handlers under Swift 6 strict concurrency.
        let timeoutWorkItem: Task<Void, Never>?
        if let timeoutSeconds, timeoutSeconds > 0 {
            timeoutWorkItem = Task.detached {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                if process.isRunning {
                    timeoutBox.markTimedOut()
                    process.terminate()
                }
            }
        } else {
            timeoutWorkItem = nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    timeoutWorkItem?.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    _ = accumulator.appendStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    _ = accumulator.appendStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())

                    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    let (outStr, errStr) = accumulator.snapshot()

                    if timeoutBox.isTimedOut {
                        continuation.resume(throwing: LadaError(
                            category: .containerLifecycleFailure,
                            explanation: "Command timed out after \(Int(timeoutSeconds ?? 0)) seconds: `\(redactedPreview)`",
                            exitStatus: proc.terminationStatus,
                            diagnosticOutput: errStr.isEmpty ? outStr : errStr,
                            suggestedRemediation: "Check whether the container API server is responsive or retry the operation.",
                            isRetryable: true
                        ))
                        return
                    }

                    let res = CommandExecutionResult(
                        executablePath: executablePath,
                        redactedCommand: redactedPreview,
                        exitStatus: proc.terminationStatus,
                        stdout: outStr,
                        stderr: errStr,
                        durationMs: durationMs
                    )
                    StructuredLogger.shared.log(
                        proc.terminationStatus == 0 ? .debug : .warning,
                        subsystem: "CommandRunner",
                        correlationID: correlationID,
                        "Completed (\(proc.terminationStatus)) in \(durationMs)ms: \(redactedPreview)"
                    )
                    continuation.resume(returning: res)
                }

                do {
                    try process.run()
                    if let stdinData, let stdinPipe {
                        try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                        try? stdinPipe.fileHandleForWriting.close()
                    }
                } catch {
                    timeoutWorkItem?.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: LadaError(
                        category: .internalError,
                        explanation: "Failed to execute '\(executablePath)': \(error.localizedDescription)",
                        suggestedRemediation: "Verify executable permissions and path.",
                        isRetryable: false
                    ))
                }
            }
        } onCancel: {
            timeoutWorkItem?.cancel()
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

/// Collects raw output bytes and splits them into lines.
///
/// Pipe reads arrive in arbitrary chunks, so a multi-byte UTF-8 character (å, ä, ö, emoji) or a
/// line can be split between two reads. Decoding each chunk on its own drops the whole chunk when
/// a character is split, so bytes are kept as `Data` and only complete lines (split on `\n`,
/// which never occurs inside a multi-byte sequence) or the final full buffer are decoded.
final class StreamAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var pendingStdout = Data()
    private var pendingStderr = Data()

    /// Appends a chunk and returns any lines it completed (non-empty, without line terminators).
    func appendStdout(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        stdout.append(chunk)
        return Self.extractLines(from: &pendingStdout, appending: chunk)
    }

    func appendStderr(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        stderr.append(chunk)
        return Self.extractLines(from: &pendingStderr, appending: chunk)
    }

    /// Returns the trailing text that had no final newline, for stdout and stderr.
    func flushPartialLines() -> ([String], [String]) {
        lock.lock()
        defer { lock.unlock() }
        let out = Self.lines(in: pendingStdout)
        let err = Self.lines(in: pendingStderr)
        pendingStdout.removeAll()
        pendingStderr.removeAll()
        return (out, err)
    }

    func snapshot() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
    }

    private static func extractLines(from pending: inout Data, appending chunk: Data) -> [String] {
        pending.append(chunk)
        guard let lastNewline = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[pending.startIndex...lastNewline]
        let lines = lines(in: Data(complete))
        pending = Data(pending[pending.index(after: lastNewline)...])
        return lines
    }

    private static func lines(in data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }
}

private final class TimeoutFlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}
