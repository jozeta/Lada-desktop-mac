import Foundation

/// Live implementation of `ContainerRuntimeService` backed by Apple's `container` CLI.
public final class ContainerCLIClient: ContainerRuntimeService, @unchecked Sendable {
    private let discoveryService: RuntimeDiscoveryService
    private let runner: CommandExecuting
    private let credentialStore: CredentialStore
    private let lock = NSLock()
    private var cachedExecutablePath: String?

    public init(
        discoveryService: RuntimeDiscoveryService = RuntimeDiscoveryService(),
        runner: CommandExecuting = CommandRunner.shared,
        credentialStore: CredentialStore = KeychainCredentialStore()
    ) {
        self.discoveryService = discoveryService
        self.runner = runner
        self.credentialStore = credentialStore
    }

    public func setCustomExecutablePath(_ path: String?) {
        lock.lock()
        cachedExecutablePath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
    }

    private func resolveExecutable() async throws -> String {
        let custom: String? = {
            lock.lock()
            defer { lock.unlock() }
            return cachedExecutablePath
        }()
        let installation = await discoveryService.discoverRuntime(customExecutablePath: custom)
        guard let exec = installation.executablePath else {
            throw LadaError(
                category: .missingPrerequisites,
                explanation: "Apple's `container` CLI is not installed on this Mac.",
                suggestedRemediation: "Open Setup or Settings → Runtime to download and install the official signed `container` package.",
                isRetryable: true,
                documentationURL: RuntimeHealthService.officialReleasesURL
            )
        }
        return exec
    }

    private func runCLI(
        _ arguments: [String],
        stdinData: Data? = nil,
        timeoutSeconds: TimeInterval = 45
    ) async throws -> CommandExecutionResult {
        let exec = try await resolveExecutable()
        let result = try await runner.execute(
            executablePath: exec,
            arguments: arguments,
            environment: nil,
            stdinData: stdinData,
            timeoutSeconds: timeoutSeconds
        )
        guard result.isSuccess else {
            throw LadaError.classifyCLIError(
                command: arguments,
                exitStatus: result.exitStatus,
                stderr: result.stderr,
                stdout: result.stdout
            )
        }
        return result
    }

    // MARK: - Discovery & System

    public func detectHostEnvironment() -> HostEnvironmentInfo {
        discoveryService.detectHostEnvironment()
    }

    public func discoverRuntime(customExecutablePath: String? = nil) async throws -> RuntimeInstallation {
        if let customExecutablePath {
            setCustomExecutablePath(customExecutablePath)
        }
        let custom: String? = {
            lock.lock()
            defer { lock.unlock() }
            return cachedExecutablePath
        }()
        return await discoveryService.discoverRuntime(customExecutablePath: custom)
    }

    public func getCapabilities(installation: RuntimeInstallation, host: HostEnvironmentInfo) -> RuntimeCapabilities {
        RuntimeCapabilities(detectedVersion: installation.cliVersion, hostEnvironment: host)
    }

    public func getSystemStatus() async throws -> RuntimeSystemStatus {
        let installation = try await discoverRuntime()
        guard let exec = installation.executablePath else {
            return RuntimeSystemStatus(
                state: .missingCLI,
                statusMessage: "Apple `container` CLI not installed"
            )
        }

        let result = try await runner.execute(
            executablePath: exec,
            arguments: ["system", "status", "--format", "json"],
            environment: nil,
            stdinData: nil,
            timeoutSeconds: 12
        )

        if let parsed = try? ContainerOutputParser.parseSystemStatus(jsonString: result.stdout) {
            return parsed
        }

        let combined = (result.stderr + "\n" + result.stdout).lowercased()
        if combined.contains("unregistered") {
            return RuntimeSystemStatus(
                state: .unregistered,
                statusMessage: "API server is not registered with launchd"
            )
        }
        return RuntimeSystemStatus(
            state: result.isSuccess ? .running : .stopped,
            statusMessage: result.stderr.isEmpty ? result.stdout : result.stderr
        )
    }

    public func getSystemVersions() async throws -> [RuntimeComponentVersion] {
        let res = try await runCLI(["system", "version", "--format", "json"], timeoutSeconds: 10)
        return try ContainerOutputParser.parseSystemVersions(jsonString: res.stdout)
    }

    public func getSystemDiskUsage() async throws -> DiskUsageSummary {
        let res = try await runCLI(["system", "df", "--format", "json"], timeoutSeconds: 20)
        return try ContainerOutputParser.parseDiskUsage(jsonString: res.stdout)
    }

    public func getSystemProperties() async throws -> SystemProperties {
        let res = try await runCLI(["system", "property", "list", "--format", "json"], timeoutSeconds: 10)
        return try ContainerOutputParser.parseSystemProperties(jsonString: res.stdout)
    }

    public func startSystemService(enableKernelInstall: Bool = true) async throws {
        var args = ["system", "start"]
        args.append(enableKernelInstall ? "--enable-kernel-install" : "--disable-kernel-install")
        _ = try await runCLI(args, timeoutSeconds: 180)
    }

    public func stopSystemService() async throws {
        _ = try await runCLI(["system", "stop"], timeoutSeconds: 30)
    }

    public func installRecommendedKernel() async throws {
        _ = try await runCLI(["system", "kernel", "set", "--recommended"], timeoutSeconds: 300)
    }

    public func fetchSystemLogs(lastPeriod: String = "15m") async throws -> String {
        let res = try await runCLI(["system", "logs", "--last", lastPeriod], timeoutSeconds: 20)
        return res.stdout
    }

    public func listDNSDomains() async throws -> [String] {
        let res = try await runCLI(["system", "dns", "list", "--format", "json"], timeoutSeconds: 10)
        guard let data = res.stdout.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }

    // MARK: - Containers

    public func listContainers(includeStopped: Bool = true) async throws -> [ContainerModel] {
        var args = ["list", "--format", "json"]
        if includeStopped {
            args.append("--all")
        }
        let res = try await runCLI(args, timeoutSeconds: 15)
        return try ContainerOutputParser.parseContainers(jsonString: res.stdout)
    }

    public func inspectContainer(id: String) async throws -> ContainerModel {
        let res = try await runCLI(["inspect", id], timeoutSeconds: 15)
        let parsed = try ContainerOutputParser.parseContainers(jsonString: res.stdout)
        guard let first = parsed.first else {
            throw LadaError(
                category: .containerLifecycleFailure,
                explanation: "Container '\(id)' not found.",
                suggestedRemediation: "Refresh the container list and verify that the container still exists.",
                isRetryable: false
            )
        }
        return first
    }

    public func getContainerStats(ids: [String] = []) async throws -> [ContainerStatsModel] {
        var args = ["stats", "--format", "json", "--no-stream"]
        args.append(contentsOf: ids)
        let res = try await runCLI(args, timeoutSeconds: 12)
        return try ContainerOutputParser.parseContainerStats(jsonString: res.stdout)
    }

    public func createOrRunContainer(request: ContainerCreateRequest) async throws -> String {
        let validationErrors = ValidationUtils.validateContainerCreateRequest(request)
        if let firstIssue = validationErrors.first {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: firstIssue,
                suggestedRemediation: "Resolve all validation errors in the Create Container form before proceeding.",
                isRetryable: false
            )
        }
        let args = request.buildCLIArguments()
        let res = try await runCLI(args, timeoutSeconds: 180)
        let id = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? request.name : id
    }

    public func startContainer(id: String) async throws {
        _ = try await runCLI(["start", id], timeoutSeconds: 30)
    }

    public func stopContainer(id: String, timeoutSeconds: Int = 5) async throws {
        _ = try await runCLI(["stop", "--time", "\(timeoutSeconds)", id], timeoutSeconds: TimeInterval(timeoutSeconds + 15))
    }

    public func restartContainer(id: String) async throws {
        // Documented sequence: stop then start
        _ = try await runCLI(["stop", id], timeoutSeconds: 30)
        _ = try await runCLI(["start", id], timeoutSeconds: 30)
    }

    public func killContainer(id: String, signal: String = "KILL") async throws {
        _ = try await runCLI(["kill", "--signal", signal, id], timeoutSeconds: 15)
    }

    public func deleteContainer(id: String, force: Bool = false) async throws {
        var args = ["delete"]
        if force { args.append("--force") }
        args.append(id)
        _ = try await runCLI(args, timeoutSeconds: 30)
    }

    public func cleanContainer(id: String) async throws {
        _ = try await runCLI(["clean", id], timeoutSeconds: 30)
    }

    public func pruneContainers() async throws -> String {
        let res = try await runCLI(["prune"], timeoutSeconds: 60)
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func exportContainer(id: String, outputPath: String) async throws {
        _ = try await runCLI(["export", "--output", outputPath, id], timeoutSeconds: 180)
    }

    public func fetchContainerLogs(id: String, bootLogs: Bool = false, tailLines: Int? = 500) async throws -> String {
        var args = ["logs"]
        if bootLogs {
            args.append("--boot")
        }
        if let tailLines {
            args.append(contentsOf: ["-n", "\(tailLines)"])
        }
        args.append(id)
        let res = try await runCLI(args, timeoutSeconds: 20)
        return res.stdout.isEmpty ? res.stderr : res.stdout
    }

    public func execCommand(
        containerID: String,
        command: [String],
        user: String? = nil,
        workdir: String? = nil,
        env: [String] = []
    ) async throws -> CommandExecutionResult {
        var args = ["exec"]
        if let user, !user.isEmpty {
            args.append(contentsOf: ["--user", user])
        }
        if let workdir, !workdir.isEmpty {
            args.append(contentsOf: ["--workdir", workdir])
        }
        for e in env where !e.isEmpty {
            args.append(contentsOf: ["--env", e])
        }
        args.append(containerID)
        args.append(contentsOf: command)
        let exec = try await resolveExecutable()
        return try await runner.execute(
            executablePath: exec,
            arguments: args,
            environment: nil,
            stdinData: nil,
            timeoutSeconds: 60
        )
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageModel] {
        let res = try await runCLI(["image", "list", "--format", "json"], timeoutSeconds: 20)
        return try ContainerOutputParser.parseImages(jsonString: res.stdout)
    }

    public func inspectImage(reference: String) async throws -> ImageModel {
        let res = try await runCLI(["image", "inspect", reference], timeoutSeconds: 15)
        let parsed = try ContainerOutputParser.parseImages(jsonString: res.stdout)
        guard let first = parsed.first else {
            throw LadaError(
                category: .missingImage,
                explanation: "Image '\(reference)' not found.",
                suggestedRemediation: "Refresh the image list or pull the image from its registry.",
                isRetryable: false
            )
        }
        return first
    }

    public func pullImage(
        request: ImagePullRequest,
        onProgressLine: @escaping @Sendable (String) -> Void
    ) async throws {
        let exec = try await resolveExecutable()
        let args = request.buildCLIArguments()
        let res = try await runner.stream(
            executablePath: exec,
            arguments: args,
            environment: nil,
            onStdoutLine: onProgressLine,
            onStderrLine: onProgressLine
        )
        guard res.isSuccess else {
            throw LadaError.classifyCLIError(command: args, exitStatus: res.exitStatus, stderr: res.stderr, stdout: res.stdout)
        }
    }

    public func tagImage(source: String, target: String) async throws {
        _ = try await runCLI(["image", "tag", source, target], timeoutSeconds: 15)
    }

    public func pushImage(
        reference: String,
        platform: String? = nil,
        scheme: String = "https",
        onProgressLine: @escaping @Sendable (String) -> Void
    ) async throws {
        let exec = try await resolveExecutable()
        var args = ["image", "push", "--progress", "plain"]
        if scheme != "https" && !scheme.isEmpty {
            args.append(contentsOf: ["--scheme", scheme])
        }
        if let platform, !platform.isEmpty {
            args.append(contentsOf: ["--platform", platform])
        }
        args.append(reference)
        let res = try await runner.stream(
            executablePath: exec,
            arguments: args,
            environment: nil,
            onStdoutLine: onProgressLine,
            onStderrLine: onProgressLine
        )
        guard res.isSuccess else {
            throw LadaError.classifyCLIError(command: args, exitStatus: res.exitStatus, stderr: res.stderr, stdout: res.stdout)
        }
    }

    public func deleteImage(reference: String, force: Bool = false) async throws {
        var args = ["image", "delete"]
        if force { args.append("--force") }
        args.append(reference)
        _ = try await runCLI(args, timeoutSeconds: 30)
    }

    public func pruneImages(allUnused: Bool = false) async throws -> String {
        var args = ["image", "prune"]
        if allUnused { args.append("--all") }
        let res = try await runCLI(args, timeoutSeconds: 60)
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func saveImage(reference: String, outputPath: String, platform: String? = nil) async throws {
        var args = ["image", "save", "--output", outputPath]
        if let platform, !platform.isEmpty {
            args.append(contentsOf: ["--platform", platform])
        }
        args.append(reference)
        _ = try await runCLI(args, timeoutSeconds: 180)
    }

    public func loadImage(inputPath: String, force: Bool = false) async throws {
        var args = ["image", "load", "--input", inputPath]
        if force { args.append("--force") }
        _ = try await runCLI(args, timeoutSeconds: 180)
    }

    // MARK: - Builds & Builder

    public func getBuilderStatus() async throws -> BuilderStatusModel {
        let exec = try await resolveExecutable()
        let res = try await runner.execute(
            executablePath: exec,
            arguments: ["builder", "status", "--format", "json"],
            environment: nil,
            stdinData: nil,
            timeoutSeconds: 15
        )
        if res.isSuccess {
            return (try? ContainerOutputParser.parseBuilderStatus(jsonString: res.stdout)) ?? BuilderStatusModel(isRunning: false)
        }
        return BuilderStatusModel(isRunning: false)
    }

    public func startBuilder(cpus: Int = 2, memoryMB: Int = 2048) async throws {
        _ = try await runCLI(["builder", "start", "--cpus", "\(cpus)", "--memory", "\(memoryMB)M"], timeoutSeconds: 120)
    }

    public func stopBuilder() async throws {
        _ = try await runCLI(["builder", "stop"], timeoutSeconds: 30)
    }

    public func deleteBuilder(force: Bool = false) async throws {
        var args = ["builder", "delete"]
        if force { args.append("--force") }
        _ = try await runCLI(args, timeoutSeconds: 30)
    }

    public func buildImage(
        request: ImageBuildRequest,
        onProgressLine: @escaping @Sendable (String) -> Void
    ) async throws -> CommandExecutionResult {
        let exec = try await resolveExecutable()
        let args = request.buildCLIArguments()
        let res = try await runner.stream(
            executablePath: exec,
            arguments: args,
            environment: nil,
            onStdoutLine: onProgressLine,
            onStderrLine: onProgressLine
        )
        guard res.isSuccess else {
            throw LadaError.classifyCLIError(command: args, exitStatus: res.exitStatus, stderr: res.stderr, stdout: res.stdout)
        }
        return res
    }

    // MARK: - Networks

    public func listNetworks() async throws -> [NetworkModel] {
        let res = try await runCLI(["network", "list", "--format", "json"], timeoutSeconds: 15)
        return try ContainerOutputParser.parseNetworks(jsonString: res.stdout)
    }

    public func inspectNetwork(name: String) async throws -> NetworkModel {
        let res = try await runCLI(["network", "inspect", name], timeoutSeconds: 15)
        let parsed = try ContainerOutputParser.parseNetworks(jsonString: res.stdout)
        guard let first = parsed.first else {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Network '\(name)' not found.",
                suggestedRemediation: "Refresh the network list.",
                isRetryable: false
            )
        }
        return first
    }

    public func createNetwork(request: NetworkCreateRequest) async throws {
        guard ValidationUtils.isValidNetworkName(request.name) else {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Invalid network name '\(request.name)'. Use lowercase alphanumeric characters, '.', '_', or '-'.",
                suggestedRemediation: "Update the network name and try again.",
                isRetryable: false
            )
        }
        let v4 = request.ipv4Subnet.trimmingCharacters(in: .whitespaces)
        if !v4.isEmpty && !ValidationUtils.isValidIPv4CIDR(v4) {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Invalid IPv4 subnet CIDR '\(v4)'. Expected format such as `192.168.100.0/24`.",
                suggestedRemediation: "Enter a valid IPv4 CIDR or leave empty for automatic allocation.",
                isRetryable: false
            )
        }
        let v6 = request.ipv6Subnet.trimmingCharacters(in: .whitespaces)
        if !v6.isEmpty && !ValidationUtils.isValidIPv6CIDR(v6) {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Invalid IPv6 subnet CIDR '\(v6)'. Expected format such as `fd00:1234::/64`.",
                suggestedRemediation: "Enter a valid IPv6 CIDR or leave empty for automatic allocation.",
                isRetryable: false
            )
        }
        _ = try await runCLI(request.buildCLIArguments(), timeoutSeconds: 20)
    }

    public func deleteNetwork(name: String) async throws {
        _ = try await runCLI(["network", "delete", name], timeoutSeconds: 20)
    }

    public func pruneNetworks() async throws -> String {
        let res = try await runCLI(["network", "prune"], timeoutSeconds: 30)
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Volumes

    public func listVolumes() async throws -> [VolumeModel] {
        let res = try await runCLI(["volume", "list", "--format", "json"], timeoutSeconds: 15)
        return try ContainerOutputParser.parseVolumes(jsonString: res.stdout)
    }

    public func inspectVolume(name: String) async throws -> VolumeModel {
        let res = try await runCLI(["volume", "inspect", name], timeoutSeconds: 15)
        let parsed = try ContainerOutputParser.parseVolumes(jsonString: res.stdout)
        guard let first = parsed.first else {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Volume '\(name)' not found.",
                suggestedRemediation: "Refresh the volume list.",
                isRetryable: false
            )
        }
        return first
    }

    public func createVolume(request: VolumeCreateRequest) async throws {
        guard ValidationUtils.isValidVolumeName(request.name) else {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Invalid volume name '\(request.name)'. Volume names must start with an alphanumeric character and contain only letters, digits, '_', '.', or '-'.",
                suggestedRemediation: "Update the volume name and try again.",
                isRetryable: false
            )
        }
        _ = try await runCLI(request.buildCLIArguments(), timeoutSeconds: 30)
    }

    public func deleteVolume(name: String) async throws {
        _ = try await runCLI(["volume", "delete", name], timeoutSeconds: 20)
    }

    public func pruneVolumes() async throws -> String {
        let res = try await runCLI(["volume", "prune"], timeoutSeconds: 60)
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Container Machines

    public func listMachines() async throws -> [MachineModel] {
        let res = try await runCLI(["machine", "list", "--format", "json"], timeoutSeconds: 15)
        return try ContainerOutputParser.parseMachines(jsonString: res.stdout)
    }

    public func inspectMachine(id: String) async throws -> MachineModel {
        let res = try await runCLI(["machine", "inspect", id], timeoutSeconds: 15)
        let parsed = try ContainerOutputParser.parseMachines(jsonString: res.stdout)
        guard let first = parsed.first else {
            throw LadaError(
                category: .containerLifecycleFailure,
                explanation: "Container machine '\(id)' not found.",
                suggestedRemediation: "Refresh the Machines list.",
                isRetryable: false
            )
        }
        return first
    }

    public func createMachine(request: MachineCreateRequest) async throws {
        if !request.name.isEmpty && !ValidationUtils.isValidMachineName(request.name) {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Machine name '\(request.name)' must start and end with a lowercase letter or digit and contain only lowercase letters, digits, and hyphens (max 56 characters).",
                suggestedRemediation: "Update the machine name and try again.",
                isRetryable: false
            )
        }
        _ = try await runCLI(request.buildCLIArguments(), timeoutSeconds: 180)
    }

    public func startMachine(id: String) async throws {
        // `container machine run -n <id> true` boots the machine if stopped
        _ = try await runCLI(["machine", "run", "-n", id, "true"], timeoutSeconds: 60)
    }

    public func stopMachine(id: String) async throws {
        _ = try await runCLI(["machine", "stop", id], timeoutSeconds: 30)
    }

    public func deleteMachine(id: String) async throws {
        _ = try await runCLI(["machine", "delete", id], timeoutSeconds: 30)
    }

    public func updateMachineConfig(request: MachineUpdateRequest) async throws {
        _ = try await runCLI(request.buildCLIArguments(), timeoutSeconds: 20)
    }

    public func setDefaultMachine(id: String) async throws {
        _ = try await runCLI(["machine", "set-default", id], timeoutSeconds: 15)
    }

    public func fetchMachineLogs(id: String, bootLogs: Bool = false, tailLines: Int? = 500) async throws -> String {
        var args = ["machine", "logs"]
        if bootLogs { args.append("--boot") }
        if let tailLines {
            args.append(contentsOf: ["-n", "\(tailLines)"])
        }
        args.append(id)
        let res = try await runCLI(args, timeoutSeconds: 20)
        return res.stdout.isEmpty ? res.stderr : res.stdout
    }

    public func runInMachine(id: String, command: [String], asRoot: Bool = false) async throws -> CommandExecutionResult {
        var args = ["machine", "run", "-n", id]
        if asRoot { args.append("--root") }
        args.append("--")
        args.append(contentsOf: command)
        let exec = try await resolveExecutable()
        return try await runner.execute(
            executablePath: exec,
            arguments: args,
            environment: nil,
            stdinData: nil,
            timeoutSeconds: 60
        )
    }

    // MARK: - Registries

    public func listRegistries() async throws -> [RegistryModel] {
        let res = try await runCLI(["registry", "list", "--format", "json"], timeoutSeconds: 15)
        return try ContainerOutputParser.parseRegistries(jsonString: res.stdout)
    }

    public func loginRegistry(server: String, username: String, password: String, scheme: String = "https") async throws {
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty, !trimmedUser.isEmpty, !password.isEmpty else {
            throw LadaError(
                category: .invalidConfiguration,
                explanation: "Registry server, username, and password/token are required.",
                suggestedRemediation: "Provide all required credentials.",
                isRetryable: false
            )
        }
        var args = ["registry", "login", "--username", trimmedUser, "--password-stdin"]
        if scheme != "https" && !scheme.isEmpty {
            args.append(contentsOf: ["--scheme", scheme])
        }
        args.append(trimmedServer)
        let stdinData = (password + "\n").data(using: .utf8)
        _ = try await runCLI(args, stdinData: stdinData, timeoutSeconds: 30)
        try? credentialStore.savePassword(password, for: trimmedServer, account: trimmedUser)
    }

    public func logoutRegistry(server: String) async throws {
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await runCLI(["registry", "logout", trimmedServer], timeoutSeconds: 15)
    }
}
