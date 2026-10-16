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
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            accumulator.appendStdout(chunk)
            for line in chunk.components(separatedBy: .newlines) where !line.isEmpty {
                onStdoutLine(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            accumulator.appendStderr(chunk)
            for line in chunk.components(separatedBy: .newlines) where !line.isEmpty {
                onStderrLine(line)
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    let remOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if let s = String(data: remOut, encoding: .utf8), !s.isEmpty {
                        accumulator.appendStdout(s)
                    }
                    let remErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    if let s = String(data: remErr, encoding: .utf8), !s.isEmpty {
                        accumulator.appendStderr(s)
                    }
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
            if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                accumulator.appendStdout(chunk)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                accumulator.appendStderr(chunk)
            }
        }

        let timeoutBox = TimeoutFlagBox()
        let timeoutWorkItem: DispatchWorkItem?
        if let timeoutSeconds, timeoutSeconds > 0 {
            let item = DispatchWorkItem {
                if process.isRunning {
                    timeoutBox.markTimedOut()
                    process.terminate()
                }
            }
            timeoutWorkItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: item)
        } else {
            timeoutWorkItem = nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    timeoutWorkItem?.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let remOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if let s = String(data: remOut, encoding: .utf8), !s.isEmpty {
                        accumulator.appendStdout(s)
                    }
                    let remErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    if let s = String(data: remErr, encoding: .utf8), !s.isEmpty {
                        accumulator.appendStderr(s)
                    }

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

private final class StreamAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    func appendStdout(_ chunk: String) {
        lock.lock()
        stdout.append(chunk)
        lock.unlock()
    }

    func appendStderr(_ chunk: String) {
        lock.lock()
        stderr.append(chunk)
        lock.unlock()
    }

    func snapshot() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr)
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
