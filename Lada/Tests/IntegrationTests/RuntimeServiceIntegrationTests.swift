import XCTest
@testable import Lada

final class SpyCommandRunner: CommandExecuting, @unchecked Sendable {
    struct RecordedInvocation: Sendable {
        let executablePath: String
        let arguments: [String]
        let stdinString: String?
    }

    private let lock = NSLock()
    private(set) var invocations: [RecordedInvocation] = []
    var stubbedOutputs: [String: CommandExecutionResult] = [:]

    func execute(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        stdinData: Data?,
        timeoutSeconds: TimeInterval?
    ) async throws -> CommandExecutionResult {
        let stdinStr = stdinData.flatMap { String(data: $0, encoding: .utf8) }
        lock.withLock {
            invocations.append(RecordedInvocation(
                executablePath: executablePath,
                arguments: arguments,
                stdinString: stdinStr
            ))
        }
        let key = arguments.joined(separator: " ")
        if let result = lock.withLock({ stubbedOutputs[key] }) {
            return result
        }
        return CommandExecutionResult(
            executablePath: executablePath,
            redactedCommand: SecretRedactor.redactArguments([executablePath] + arguments).joined(separator: " "),
            exitStatus: 0,
            stdout: "[]",
            stderr: "",
            durationMs: 5
        )
    }

    func stream(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) async throws -> CommandExecutionResult {
        onStdoutLine("Step 1/2: FROM alpine:3.20")
        onStdoutLine("Successfully built image")
        return try await execute(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            stdinData: nil,
            timeoutSeconds: 60
        )
    }
}

final class RuntimeServiceIntegrationTests: XCTestCase {
    func testContainerCLIClientRegistryLoginUsesPasswordStdinNotCommandLineArguments() async throws {
        let spy = SpyCommandRunner()
        let discovery = RuntimeDiscoveryService(runner: spy)
        let credentialStore = InMemoryCredentialStore()
        let client = ContainerCLIClient(
            discoveryService: discovery,
            runner: spy,
            credentialStore: credentialStore
        )
        // Point to `/bin/sh` so RuntimeDiscoveryService verifies an existing executable path in tests
        client.setCustomExecutablePath("/bin/sh")

        try await client.loginRegistry(
            server: "ghcr.io",
            username: "developer",
            password: "ghp_super_secret_pat_token",
            scheme: "https"
        )

        let loginInvocation = try XCTUnwrap(spy.invocations.first(where: { $0.arguments.first == "registry" }))
        XCTAssertEqual(loginInvocation.executablePath, "/bin/sh")
        XCTAssertTrue(loginInvocation.arguments.contains("--password-stdin"))
        XCTAssertTrue(loginInvocation.arguments.contains("developer"))
        XCTAssertTrue(loginInvocation.arguments.contains("ghcr.io"))
        // Verify password was NEVER passed in arguments and was piped via stdin
        XCTAssertFalse(loginInvocation.arguments.contains("ghp_super_secret_pat_token"))
        XCTAssertEqual(loginInvocation.stdinString, "ghp_super_secret_pat_token\n")
        XCTAssertEqual(try credentialStore.loadPassword(for: "ghcr.io", account: "developer"), "ghp_super_secret_pat_token")
    }

    func testMockContainerRuntimeServiceFullLifecycle() async throws {
        let service = MockContainerRuntimeService()

        let initialContainers = try await service.listContainers(includeStopped: true)
        XCTAssertEqual(initialContainers.count, 2)

        // Create a new container
        let createReq = ContainerCreateRequest(
            name: "integration-worker",
            imageReference: "ghcr.io/apple/swift:6.0-slim"
        )
        let newID = try await service.createOrRunContainer(request: createReq)
        let afterCreate = try await service.listContainers(includeStopped: true)
        XCTAssertEqual(afterCreate.count, 3)
        XCTAssertTrue(afterCreate.contains(where: { $0.id == newID && $0.state == .running }))

        // Stop, start, restart, and delete container
        try await service.stopContainer(id: newID, timeoutSeconds: 5)
        var updated = try await service.inspectContainer(id: newID)
        XCTAssertEqual(updated.state, .stopped)

        try await service.startContainer(id: newID)
        updated = try await service.inspectContainer(id: newID)
        XCTAssertEqual(updated.state, .running)

        try await service.deleteContainer(id: newID, force: true)
        let afterDelete = try await service.listContainers(includeStopped: true)
        XCTAssertFalse(afterDelete.contains(where: { $0.id == newID }))

        // Prune stopped containers
        let pruneSummary = try await service.pruneContainers()
        XCTAssertFalse(pruneSummary.isEmpty)
    }
}
