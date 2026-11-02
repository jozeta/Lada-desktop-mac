import Foundation

public protocol ContainerRuntimeService: Sendable {
    // Discovery & System
    func detectHostEnvironment() -> HostEnvironmentInfo
    func discoverRuntime(customExecutablePath: String?) async throws -> RuntimeInstallation
    func getCapabilities(installation: RuntimeInstallation, host: HostEnvironmentInfo) -> RuntimeCapabilities
    func getSystemStatus() async throws -> RuntimeSystemStatus
    func getSystemVersions() async throws -> [RuntimeComponentVersion]
    func getSystemDiskUsage() async throws -> DiskUsageSummary
    func getSystemProperties() async throws -> SystemProperties
    func startSystemService(enableKernelInstall: Bool) async throws
    func stopSystemService() async throws
    func installRecommendedKernel() async throws
    func fetchSystemLogs(lastPeriod: String) async throws -> String
    func listDNSDomains() async throws -> [String]

    // Containers
    func listContainers(includeStopped: Bool) async throws -> [ContainerModel]
    func inspectContainer(id: String) async throws -> ContainerModel
    func getContainerStats(ids: [String]) async throws -> [ContainerStatsModel]
    func createOrRunContainer(request: ContainerCreateRequest) async throws -> String
    func startContainer(id: String) async throws
    func stopContainer(id: String, timeoutSeconds: Int) async throws
    func restartContainer(id: String) async throws
    func killContainer(id: String, signal: String) async throws
    func deleteContainer(id: String, force: Bool) async throws
    func cleanContainer(id: String) async throws
    func pruneContainers() async throws -> String
    func exportContainer(id: String, outputPath: String) async throws
    func fetchContainerLogs(id: String, bootLogs: Bool, tailLines: Int?) async throws -> String
    func execCommand(containerID: String, command: [String], user: String?, workdir: String?, env: [String]) async throws -> CommandExecutionResult
    /// `container copy <id>:<containerPath> <hostPath>` — copies a file or folder out of a container.
    func copyFromContainer(id: String, containerPath: String, toHostPath hostPath: String) async throws
    /// `container copy <hostPath> <id>:<containerPath>` — copies a file or folder into a container.
    /// Missing parent folders in the container are created; the copy is owned by root with mode 0644.
    func copyToContainer(id: String, fromHostPath hostPath: String, containerPath: String) async throws

    // Images
    func listImages() async throws -> [ImageModel]
    func inspectImage(reference: String) async throws -> ImageModel
    func pullImage(request: ImagePullRequest, onProgressLine: @escaping @Sendable (String) -> Void) async throws
    func tagImage(source: String, target: String) async throws
    func pushImage(reference: String, platform: String?, scheme: String, onProgressLine: @escaping @Sendable (String) -> Void) async throws
    func deleteImage(reference: String, force: Bool) async throws
    func pruneImages(allUnused: Bool) async throws -> String
    func saveImage(reference: String, outputPath: String, platform: String?) async throws
    func loadImage(inputPath: String, force: Bool) async throws

    // Builds & Builder
    func getBuilderStatus() async throws -> BuilderStatusModel
    func startBuilder(cpus: Int, memoryMB: Int) async throws
    func stopBuilder() async throws
    func deleteBuilder(force: Bool) async throws
    func buildImage(request: ImageBuildRequest, onProgressLine: @escaping @Sendable (String) -> Void) async throws -> CommandExecutionResult

    // Networks
    func listNetworks() async throws -> [NetworkModel]
    func inspectNetwork(name: String) async throws -> NetworkModel
    func createNetwork(request: NetworkCreateRequest) async throws
    func deleteNetwork(name: String) async throws
    func pruneNetworks() async throws -> String

    // Volumes
    func listVolumes() async throws -> [VolumeModel]
    func inspectVolume(name: String) async throws -> VolumeModel
    func createVolume(request: VolumeCreateRequest) async throws
    func deleteVolume(name: String) async throws
    func pruneVolumes() async throws -> String

    // Container Machines
    func listMachines() async throws -> [MachineModel]
    func inspectMachine(id: String) async throws -> MachineModel
    func createMachine(request: MachineCreateRequest) async throws
    func startMachine(id: String) async throws
    func stopMachine(id: String) async throws
    func deleteMachine(id: String) async throws
    func updateMachineConfig(request: MachineUpdateRequest) async throws
    func setDefaultMachine(id: String) async throws
    func fetchMachineLogs(id: String, bootLogs: Bool, tailLines: Int?) async throws -> String
    func runInMachine(id: String, command: [String], asRoot: Bool) async throws -> CommandExecutionResult

    // Registries
    func listRegistries() async throws -> [RegistryModel]
    func loginRegistry(server: String, username: String, password: String, scheme: String) async throws
    func logoutRegistry(server: String) async throws
}
