import Foundation

public enum ErrorCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case missingPrerequisites = "Missing Prerequisites"
    case unsupportedRuntimeVersion = "Unsupported Runtime Version"
    case permissionError = "Permission Denied"
    case networkFailure = "Network Failure"
    case registryAuthenticationError = "Registry Authentication Error"
    case invalidConfiguration = "Invalid Configuration"
    case missingImage = "Missing Image"
    case containerLifecycleFailure = "Container Lifecycle Failure"
    case apiServerFailure = "Runtime API Server Failure"
    case unsupportedOperation = "Unsupported Operation"
    case internalError = "Application Error"
}

public struct LadaError: Error, LocalizedError, Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let category: ErrorCategory
    public let explanation: String
    public let exitStatus: Int32?
    public let diagnosticOutput: String?
    public let suggestedRemediation: String
    public let isRetryable: Bool
    public let documentationURL: URL?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        category: ErrorCategory,
        explanation: String,
        exitStatus: Int32? = nil,
        diagnosticOutput: String? = nil,
        suggestedRemediation: String,
        isRetryable: Bool = true,
        documentationURL: URL? = URL(string: "https://apple.github.io/container/documentation/"),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.explanation = explanation
        self.exitStatus = exitStatus
        self.diagnosticOutput = diagnosticOutput.map { SecretRedactor.redact($0) }
        self.suggestedRemediation = suggestedRemediation
        self.isRetryable = isRetryable
        self.documentationURL = documentationURL
        self.timestamp = timestamp
    }

    public var errorDescription: String? {
        explanation
    }

    public static func classifyCLIError(
        command: [String],
        exitStatus: Int32,
        stderr: String,
        stdout: String
    ) -> LadaError {
        let combined = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let lower = combined.lowercased()

        if lower.contains("apiserver is not running") || lower.contains("connection refused") || lower.contains("xpc") && lower.contains("unregistered") {
            return LadaError(
                category: .apiServerFailure,
                explanation: "The Apple container API server is not running.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Start the container system service using the 'Start System' action or run `container system start`.",
                isRetryable: true,
                documentationURL: URL(string: "https://github.com/apple/container/blob/main/docs/command-reference.md#container-system-start")
            )
        }

        if lower.contains("unauthorized") || lower.contains("authentication required") || lower.contains("denied: requested access") || lower.contains("401") {
            return LadaError(
                category: .registryAuthenticationError,
                explanation: "Registry authentication failed or credentials have expired.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Sign in to the target registry in the Registries section before pulling or pushing this image.",
                isRetryable: true,
                documentationURL: URL(string: "https://github.com/apple/container/blob/main/docs/command-reference.md#container-registry-login")
            )
        }

        if lower.contains("permission denied") || lower.contains("operation not permitted") || lower.contains("requires administrator") {
            return LadaError(
                category: .permissionError,
                explanation: "The operation was denied due to insufficient permissions.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Verify file permissions on mounted paths or authorize administrator privileges if modifying system DNS or installation files.",
                isRetryable: false
            )
        }

        if lower.contains("not found") && (command.contains("image") || command.contains("run") || command.contains("create") || lower.contains("manifest unknown")) {
            return LadaError(
                category: .missingImage,
                explanation: "The requested container image or tag could not be found.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Verify the image repository name, tag, and platform, or pull the image first.",
                isRetryable: true
            )
        }

        if lower.contains("invalid") || lower.contains("unknown option") || lower.contains("overlap") {
            return LadaError(
                category: .invalidConfiguration,
                explanation: "The runtime rejected the supplied configuration arguments.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Review the configuration fields highlighted in the form and ensure all values match supported formats.",
                isRetryable: false
            )
        }

        if lower.contains("timeout") || lower.contains("network is unreachable") || lower.contains("no such host") || lower.contains("tls") {
            return LadaError(
                category: .networkFailure,
                explanation: "A network error occurred while communicating with the remote endpoint.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Check your internet connection, DNS settings, or proxy configuration and try again.",
                isRetryable: true
            )
        }

        if lower.contains("unsupported") {
            return LadaError(
                category: .unsupportedOperation,
                explanation: "This operation or feature is not supported on the current host or runtime configuration.",
                exitStatus: exitStatus,
                diagnosticOutput: combined,
                suggestedRemediation: "Check hardware and kernel requirements (for example, nested virtualization requires M3+ and a CONFIG_KVM=y kernel).",
                isRetryable: false
            )
        }

        return LadaError(
            category: .containerLifecycleFailure,
            explanation: combined.isEmpty ? "Command `container \(command.first ?? "")` exited with code \(exitStatus)." : firstMeaningfulLine(from: combined),
            exitStatus: exitStatus,
            diagnosticOutput: combined,
            suggestedRemediation: "Inspect the diagnostic output below and verify the container and system service state.",
            isRetryable: true
        )
    }

    private static func firstMeaningfulLine(from text: String) -> String {
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "The runtime operation failed."
        return SecretRedactor.redact(line)
    }
}
