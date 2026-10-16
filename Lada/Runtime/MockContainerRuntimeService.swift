import Foundation

/// Stateful mock implementation of `ContainerRuntimeService` for automated unit, integration, and UI tests.
public final class MockContainerRuntimeService: ContainerRuntimeService, @unchecked Sendable {
    private let lock = NSLock()

    public var simulatedHost: HostEnvironmentInfo
    public var simulatedInstallation: RuntimeInstallation
    public var simulatedServiceState: RuntimeServiceState
    public var simulatedContainers: [ContainerModel]
    public var simulatedImages: [ImageModel]
    public var simulatedNetworks: [NetworkModel]
    public var simulatedVolumes: [VolumeModel]
    public var simulatedMachines: [MachineModel]
    public var simulatedRegistries: [RegistryModel]
    public var simulatedBuilderStatus: BuilderStatusModel
    public var simulatedProperties: SystemProperties
    public var simulatedDNSDomains: [String]
    public var recordedOperations: [String] = []
    public var forcedError: LadaError?

    public init(
        isInstalled: Bool = true,
        serviceState: RuntimeServiceState = .running
    ) {
        self.simulatedHost = HostEnvironmentInfo(
            cpuArchitecture: "arm64",
            cpuBrandString: "Apple M5 Pro",
            isAppleSilicon: true,
            supportsNestedVirtualizationChip: true,
            macOSMajorVersion: 27,
            macOSMinorVersion: 0,
            macOSPatchVersion: 0,
            macOSVersionString: "Version 27.0 (Build 26A428)",
            macOSBuildString: "26A428",
            physicalMemoryBytes: 68_719_476_736,
            processorCount: 14,
            availableDiskSpaceBytes: 250_000_000_000,
            hypervisorFrameworkAvailable: true
        )
        self.simulatedInstallation = RuntimeInstallation(
            isInstalled: isInstalled,
            executablePath: isInstalled ? "/usr/local/bin/container" : nil,
            installRootPath: isInstalled ? "/usr/local" : nil,
            appRootPath: ("~/Library/Application Support/com.apple.container" as NSString).expandingTildeInPath,
            cliVersion: isInstalled ? SemanticVersion(major: 1, minor: 5, patch: 0) : nil,
            rawVersionString: isInstalled ? "1.5.0" : nil,
            buildType: "release",
            commitHash: "150a9c3",
            helperPluginsPresent: isInstalled,
            defaultKernelInstalled: isInstalled,
            kernelBinaryPath: isInstalled ? "opt/kata/share/kata-containers/vmlinux-6.18.35-197" : nil
        )
        self.simulatedServiceState = serviceState

        let now = Date()
        self.simulatedContainers = [
            ContainerModel(
                id: "nginx-ingress",
                imageReference: "docker.io/library/nginx:1.27-alpine",
                imageDigest: "sha256:91f1a32a5b6900112233445566778899aabbccddeeff",
                state: .running,
                rawState: "running",
                creationDate: now.addingTimeInterval(-7200),
                startedDate: now.addingTimeInterval(-3600),
                configuration: ContainerConfigurationModel(
                    executable: "/docker-entrypoint.sh",
                    arguments: ["nginx", "-g", "daemon off;"],
                    environment: ["NGINX_HOST=localhost", "NGINX_PORT=80", "API_TOKEN=secret-prod-token-99"],
                    workingDirectory: "/usr/share/nginx/html",
                    terminal: false,
                    user: "0:0",
                    cpus: 2,
                    memoryInBytes: 1_073_741_824,
                    os: "linux",
                    arch: "arm64",
                    readOnlyRootfs: false,
                    useInit: true,
                    labels: ["com.example.tier": "edge"],
                    mounts: [
                        MountAttachment(kind: .volume, source: "nginx-cache", destination: "/var/cache/nginx", readOnly: false, volumeName: "nginx-cache")
                    ],
                    publishedPorts: [
                        PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")
                    ],
                    configuredNetworks: ["default"]
                ),
                networks: [
                    ContainerNetworkAttachment(
                        network: "default",
                        hostname: "nginx-ingress.test.",
                        ipv4Address: "192.168.64.2/24",
                        ipv4Gateway: "192.168.64.1",
                        macAddress: "f2:42:ac:11:00:02"
                    )
                ]
            ),
            ContainerModel(
                id: "postgres-dev",
                imageReference: "docker.io/library/postgres:17-alpine",
                imageDigest: "sha256:44e8b77123456789abcdef0123456789abcdef",
                state: .stopped,
                rawState: "stopped",
                creationDate: now.addingTimeInterval(-86400),
                startedDate: nil,
                configuration: ContainerConfigurationModel(
                    executable: "docker-entrypoint.sh",
                    arguments: ["postgres"],
                    environment: ["POSTGRES_DB=lada", "POSTGRES_USER=postgres", "POSTGRES_PASSWORD=devpass"],
                    workingDirectory: "/",
                    terminal: false,
                    user: "70:70",
                    cpus: 4,
                    memoryInBytes: 2_147_483_648,
                    os: "linux",
                    arch: "arm64",
                    mounts: [
                        MountAttachment(kind: .volume, source: "pgdata", destination: "/var/lib/postgresql/data", readOnly: false, volumeName: "pgdata")
                    ],
                    publishedPorts: [
                        PortMapping(hostAddress: "127.0.0.1", hostPort: 5432, containerPort: 5432, proto: "tcp")
                    ],
                    configuredNetworks: ["default"]
                ),
                networks: []
            )
        ]

        self.simulatedImages = [
            ImageModel(
                fullReference: "docker.io/library/nginx:1.27-alpine",
                digest: "sha256:91f1a32a5b6900112233445566778899aabbccddeeff00112233445566778899",
                creationDate: now.addingTimeInterval(-172800),
                variants: [
                    ImageVariantModel(
                        os: "linux",
                        architecture: "arm64",
                        digest: "sha256:91f1a32a5b6900112233445566778899aabbccddeeff00112233445566778899",
                        sizeBytes: 48_234_496,
                        created: "2026-09-15T10:00:00Z",
                        entrypoint: ["/docker-entrypoint.sh"],
                        cmd: ["nginx", "-g", "daemon off;"],
                        env: ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "NGINX_VERSION=1.27.2"],
                        workingDir: "/",
                        exposedPorts: ["80/tcp"],
                        layerDiffIDs: [
                            "sha256:a1b2c3d4e5f60123456789abcdef",
                            "sha256:f6e5d4c3b2a10123456789abcdef"
                        ],
                        history: [
                            ImageHistoryLayer(created: "2026-09-15T09:58:00Z", createdBy: "ADD alpine-minirootfs-3.20.3-aarch64.tar.gz /", emptyLayer: false),
                            ImageHistoryLayer(created: "2026-09-15T10:00:00Z", createdBy: "CMD [\"nginx\" \"-g\" \"daemon off;\"]", emptyLayer: true)
                        ]
                    )
                ]
            ),
            ImageModel(
                fullReference: "docker.io/library/postgres:17-alpine",
                digest: "sha256:44e8b77123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                creationDate: now.addingTimeInterval(-259200),
                variants: [
                    ImageVariantModel(
                        os: "linux",
                        architecture: "arm64",
                        digest: "sha256:44e8b77123456789abcdef0123456789abcdef0123456789abcdef0123456789",
                        sizeBytes: 264_241_152,
                        created: "2026-09-10T14:20:00Z",
                        entrypoint: ["docker-entrypoint.sh"],
                        cmd: ["postgres"],
                        exposedPorts: ["5432/tcp"]
                    )
                ]
            ),
            ImageModel(
                fullReference: "docker.io/library/alpine:3.22",
                digest: "sha256:77c1d2e3f4a5b6c7d8e9f00112233445566778899aabbccddeeff00112233445",
                creationDate: now.addingTimeInterval(-400000),
                variants: [
                    ImageVariantModel(
                        os: "linux",
                        architecture: "arm64",
                        digest: "sha256:77c1d2e3f4a5b6c7d8e9f00112233445566778899aabbccddeeff00112233445",
                        sizeBytes: 8_388_608,
                        created: "2026-08-20T08:00:00Z",
                        cmd: ["/bin/sh"]
                    )
                ]
            )
        ]

        self.simulatedNetworks = [
            NetworkModel(
                id: "default",
                mode: "nat",
                plugin: "container-network-vmnet",
                ipv4Subnet: "192.168.64.0/24",
                ipv4Gateway: "192.168.64.1",
                creationDate: now.addingTimeInterval(-604800),
                labels: ["com.apple.container.resource.builtin": "true"],
                isBuiltin: true
            ),
            NetworkModel(
                id: "backend-net",
                mode: "nat",
                plugin: "container-network-vmnet",
                ipv4Subnet: "192.168.65.0/24",
                ipv4Gateway: "192.168.65.1",
                ipv6Subnet: "fd00:1234::/64",
                creationDate: now.addingTimeInterval(-86400),
                isBuiltin: false
            )
        ]

        self.simulatedVolumes = [
            VolumeModel(
                id: "pgdata",
                driver: "local",
                format: "ext4",
                sourcePath: "~/Library/Application Support/com.apple.container/volumes/pgdata/volume.img",
                creationDate: now.addingTimeInterval(-86400),
                sizeInBytes: 10_737_418_240,
                options: ["journal": "ordered", "size": "10g"]
            ),
            VolumeModel(
                id: "nginx-cache",
                driver: "local",
                format: "ext4",
                sourcePath: "~/Library/Application Support/com.apple.container/volumes/nginx-cache/volume.img",
                creationDate: now.addingTimeInterval(-7200),
                sizeInBytes: 1_073_741_824,
                options: ["journal": "writeback:64m"]
            )
        ]

        self.simulatedMachines = [
            MachineModel(
                id: "dev",
                status: .running,
                isDefault: true,
                ipAddress: "192.168.64.10",
                cpus: 4,
                memoryBytes: 8_589_934_592,
                diskSizeBytes: 68_719_476_736,
                createdDate: now.addingTimeInterval(-172800),
                startedDate: now.addingTimeInterval(-3600),
                imageReference: "alpine:3.22",
                homeMount: .rw,
                virtualizationEnabled: false,
                username: NSUserName()
            )
        ]

        self.simulatedRegistries = [
            RegistryModel(
                hostname: "ghcr.io",
                username: "developer",
                isAuthenticated: true,
                creationDate: now.addingTimeInterval(-604800),
                modificationDate: now.addingTimeInterval(-86400)
            )
        ]

        self.simulatedBuilderStatus = BuilderStatusModel(
            isRunning: true,
            id: "buildkit",
            imageReference: "ghcr.io/apple/container-builder-shim/builder:0.13.1",
            state: "running",
            ipAddress: "192.168.64.5",
            cpus: 2,
            memoryBytes: 2_147_483_648
        )

        self.simulatedProperties = SystemProperties(
            build: .init(cpus: 2, memory: "2048mb", rosetta: true, image: "ghcr.io/apple/container-builder-shim/builder:0.13.1"),
            container: .init(cpus: 4, memory: "1gb"),
            dns: .init(domain: "test"),
            kernel: .init(binaryPath: "opt/kata/share/kata-containers/vmlinux-6.18.35-197"),
            network: .init(),
            registry: .init(domain: "docker.io"),
            vminit: .init(image: "ghcr.io/apple/containerization/vminit:0.34.0")
        )
        self.simulatedDNSDomains = ["test"]
    }

    private func record(_ op: String) throws {
        try lock.withLock {
            if let err = forcedError {
                throw err
            }
            recordedOperations.append(op)
        }
    }

    // MARK: - Discovery & System

    public func detectHostEnvironment() -> HostEnvironmentInfo {
        lock.withLock { simulatedHost }
    }

    public func discoverRuntime(customExecutablePath: String? = nil) async throws -> RuntimeInstallation {
        try record("discoverRuntime")
        return lock.withLock { simulatedInstallation }
    }

    public func getCapabilities(installation: RuntimeInstallation, host: HostEnvironmentInfo) -> RuntimeCapabilities {
        RuntimeCapabilities(detectedVersion: installation.cliVersion, hostEnvironment: host)
    }

    public func getSystemStatus() async throws -> RuntimeSystemStatus {
        try record("getSystemStatus")
        return lock.withLock {
            let running = simulatedContainers.filter { $0.state == .running }.count
            return RuntimeSystemStatus(
                state: simulatedServiceState,
                clientVersion: RuntimeComponentVersion(appName: "container", version: "1.5.0", buildType: "release", commit: "150a9c3"),
                serverVersion: simulatedServiceState == .running
                    ? RuntimeComponentVersion(appName: "container-apiserver", version: "container-apiserver version 1.5.0 (build: release, commit: 150a9c3)", buildType: "release", commit: "150a9c3")
                    : nil,
                appRoot: simulatedInstallation.appRootPath,
                installRoot: simulatedInstallation.installRootPath,
                containersTotal: simulatedContainers.count,
                containersRunning: running,
                imagesTotal: simulatedImages.count,
                statusMessage: simulatedServiceState.rawValue
            )
        }
    }

    public func getSystemVersions() async throws -> [RuntimeComponentVersion] {
        try record("getSystemVersions")
        return [
            RuntimeComponentVersion(appName: "container", version: "1.5.0", buildType: "release", commit: "150a9c3"),
            RuntimeComponentVersion(appName: "container-apiserver", version: "1.5.0", buildType: "release", commit: "150a9c3")
        ]
    }

    public func getSystemDiskUsage() async throws -> DiskUsageSummary {
        try record("getSystemDiskUsage")
        return lock.withLock {
            let imgBytes = UInt64(simulatedImages.reduce(0) { $0 + max(0, $1.totalSizeBytes) })
            return DiskUsageSummary(
                images: ResourceDiskUsage(total: simulatedImages.count, active: 1, sizeInBytes: imgBytes, reclaimable: imgBytes / 3),
                containers: ResourceDiskUsage(total: simulatedContainers.count, active: simulatedContainers.filter { $0.state == .running }.count, sizeInBytes: 245_000_000, reclaimable: 64_000_000),
                volumes: ResourceDiskUsage(total: simulatedVolumes.count, active: simulatedVolumes.count, sizeInBytes: 512_000_000, reclaimable: 0)
            )
        }
    }

    public func getSystemProperties() async throws -> SystemProperties {
        try record("getSystemProperties")
        return lock.withLock { simulatedProperties }
    }

    public func startSystemService(enableKernelInstall: Bool) async throws {
        try record("startSystemService")
        lock.withLock { simulatedServiceState = .running }
    }

    public func stopSystemService() async throws {
        try record("stopSystemService")
        lock.withLock { simulatedServiceState = .stopped }
    }

    public func installRecommendedKernel() async throws {
        try record("installRecommendedKernel")
    }

    public func fetchSystemLogs(lastPeriod: String) async throws -> String {
        try record("fetchSystemLogs:\(lastPeriod)")
        return """
        2026-10-16 10:00:01.102+0200 Info container-apiserver: [com.apple.container:APIServer] container-apiserver v1.5.0 initialized
        2026-10-16 10:00:02.410+0200 Info container-network-vmnet: [com.apple.container:NetworkVmnetHelper] allocated subnet 192.168.64.0/24 [id=default]
        2026-10-16 10:01:12.008+0200 Info container-runtime-linux: [com.apple.container:RuntimeLinuxHelper] started container [uuid=nginx-ingress]
        """
    }

    public func listDNSDomains() async throws -> [String] {
        try record("listDNSDomains")
        return lock.withLock { simulatedDNSDomains }
    }

    // MARK: - Containers

    public func listContainers(includeStopped: Bool) async throws -> [ContainerModel] {
        try record("listContainers")
        return lock.withLock {
            if includeStopped {
                return simulatedContainers
            }
            return simulatedContainers.filter { $0.state == .running }
        }
    }

    public func inspectContainer(id: String) async throws -> ContainerModel {
        try record("inspectContainer:\(id)")
        return try lock.withLock {
            guard let found = simulatedContainers.first(where: { $0.id == id }) else {
                throw LadaError(category: .containerLifecycleFailure, explanation: "Container '\(id)' not found.", suggestedRemediation: "Refresh container list.", isRetryable: false)
            }
            return found
        }
    }

    public func getContainerStats(ids: [String]) async throws -> [ContainerStatsModel] {
        try record("getContainerStats")
        let running = lock.withLock {
            simulatedContainers.filter { c in
                c.state == .running && (ids.isEmpty || ids.contains(c.id))
            }
        }
        let nowSec = Date().timeIntervalSinceReferenceDate
        return running.map { c in
            let uptime = max(1.0, Date().timeIntervalSince(c.startedDate ?? Date().addingTimeInterval(-60)))
            let wave = (sin(nowSec * 0.7) + 1.0) * 0.5 // 0.0 ... 1.0
            let baseMem = UInt64(Double(c.configuration.memoryInBytes) * (0.14 + wave * 0.08))
            let cpuUsec = UInt64(uptime * 180_000) + UInt64(wave * 95_000)
            let netRx = UInt64(uptime * 42_000) + UInt64(wave * 18_000)
            let netTx = UInt64(uptime * 26_000) + UInt64(wave * 12_000)
            let diskRead = UInt64(uptime * 84_000) + UInt64(wave * 32_000)
            let diskWrite = UInt64(uptime * 38_000) + UInt64(wave * 16_000)
            return ContainerStatsModel(
                id: c.id,
                cpuUsageUsec: cpuUsec,
                memoryUsageBytes: min(c.configuration.memoryInBytes, max(33_554_432, baseMem)),
                memoryLimitBytes: c.configuration.memoryInBytes,
                networkRxBytes: netRx,
                networkTxBytes: netTx,
                blockReadBytes: diskRead,
                blockWriteBytes: diskWrite,
                numProcesses: 4
            )
        }
    }

    public func createOrRunContainer(request: ContainerCreateRequest) async throws -> String {
        let issues = ValidationUtils.validateContainerCreateRequest(request)
        if let first = issues.first {
            throw LadaError(category: .invalidConfiguration, explanation: first, suggestedRemediation: "Fix configuration errors.", isRetryable: false)
        }
        let newID = request.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(UUID().uuidString.prefix(12)).lowercased()
            : request.name.trimmingCharacters(in: .whitespaces)
        try record("createOrRunContainer:\(newID)")

        let model = ContainerModel(
            id: newID,
            imageReference: request.imageReference,
            state: request.startImmediately ? .running : .stopped,
            rawState: request.startImmediately ? "running" : "stopped",
            creationDate: Date(),
            startedDate: request.startImmediately ? Date() : nil,
            configuration: ContainerConfigurationModel(
                executable: request.entrypointOverride.isEmpty ? "/bin/sh" : request.entrypointOverride,
                arguments: request.commandArguments,
                environment: request.environmentVariables.map { "\($0.key)=\($0.value)" },
                workingDirectory: request.workingDirectory.isEmpty ? "/" : request.workingDirectory,
                terminal: request.allocateTTY,
                user: request.userSpec.isEmpty ? "0:0" : request.userSpec,
                cpus: request.cpus,
                memoryInBytes: UInt64(request.memoryMB) * 1024 * 1024,
                readOnlyRootfs: request.readOnlyRootfs,
                useInit: request.useInitProcess,
                rosetta: request.enableRosetta,
                virtualization: request.exposeVirtualization,
                sshForwarding: request.sshAgentForwarding,
                capAdd: request.capAdd,
                capDrop: request.capDrop,
                mounts: request.mounts,
                publishedPorts: request.publishedPorts,
                publishedSockets: request.publishedSockets,
                configuredNetworks: [request.networkName]
            ),
            networks: request.startImmediately ? [
                ContainerNetworkAttachment(
                    network: request.networkName,
                    hostname: "\(newID).test.",
                    ipv4Address: "192.168.64.15/24",
                    ipv4Gateway: "192.168.64.1"
                )
            ] : []
        )
        lock.withLock { simulatedContainers.insert(model, at: 0) }
        return newID
    }

    public func startContainer(id: String) async throws {
        try record("startContainer:\(id)")
        lock.withLock {
            guard let idx = simulatedContainers.firstIndex(where: { $0.id == id }) else { return }
            let old = simulatedContainers[idx]
            simulatedContainers[idx] = ContainerModel(
                id: old.id,
                imageReference: old.imageReference,
                imageDigest: old.imageDigest,
                state: .running,
                rawState: "running",
                creationDate: old.creationDate,
                startedDate: Date(),
                configuration: old.configuration,
                networks: old.networks.isEmpty ? [
                    ContainerNetworkAttachment(network: "default", hostname: "\(old.id).test.", ipv4Address: "192.168.64.20/24", ipv4Gateway: "192.168.64.1")
                ] : old.networks
            )
        }
    }

    public func stopContainer(id: String, timeoutSeconds: Int) async throws {
        try record("stopContainer:\(id)")
        lock.withLock {
            guard let idx = simulatedContainers.firstIndex(where: { $0.id == id }) else { return }
            let old = simulatedContainers[idx]
            simulatedContainers[idx] = ContainerModel(
                id: old.id,
                imageReference: old.imageReference,
                imageDigest: old.imageDigest,
                state: .stopped,
                rawState: "stopped",
                creationDate: old.creationDate,
                startedDate: nil,
                configuration: old.configuration,
                networks: []
            )
        }
    }

    public func restartContainer(id: String) async throws {
        try record("restartContainer:\(id)")
        try await stopContainer(id: id, timeoutSeconds: 5)
        try await startContainer(id: id)
    }

    public func killContainer(id: String, signal: String) async throws {
        try record("killContainer:\(id):\(signal)")
        try await stopContainer(id: id, timeoutSeconds: 0)
    }

    public func deleteContainer(id: String, force: Bool) async throws {
        try record("deleteContainer:\(id):force=\(force)")
        try lock.withLock {
            guard let idx = simulatedContainers.firstIndex(where: { $0.id == id }) else { return }
            if simulatedContainers[idx].state == .running && !force {
                throw LadaError(
                    category: .containerLifecycleFailure,
                    explanation: "Container '\(id)' is currently running. Stop it first or use Force Delete.",
                    suggestedRemediation: "Stop the container or confirm force deletion.",
                    isRetryable: false
                )
            }
            simulatedContainers.remove(at: idx)
        }
    }

    public func cleanContainer(id: String) async throws {
        try record("cleanContainer:\(id)")
    }

    public func pruneContainers() async throws -> String {
        try record("pruneContainers")
        let removed = lock.withLock { () -> Int in
            let before = simulatedContainers.count
            simulatedContainers.removeAll { $0.state != .running }
            return before - simulatedContainers.count
        }
        return "Removed \(removed) stopped container(s)."
    }

    public func exportContainer(id: String, outputPath: String) async throws {
        try record("exportContainer:\(id)->\(outputPath)")
    }

    public func fetchContainerLogs(id: String, bootLogs: Bool, tailLines: Int?) async throws -> String {
        try record("fetchContainerLogs:\(id):boot=\(bootLogs)")
        if bootLogs {
            return """
            [    0.098284] random: crng init done
            [    0.101051] virtio_blk virtio2: [vda] 1073741824 512-byte logical blocks (550 GB/512 GiB)
            [    0.127525] VFS: Mounted root (ext4 filesystem) readonly on device 254:0.
            [    0.143252] Run /sbin/vminitd as init process
            2026-10-16T08:00:01Z info vminitd : [vminitd] vminitd booting...
            2026-10-16T08:00:01Z info vminitd : [vminitd] starting process supervisor for \(id)
            """
        }
        return """
        2026-10-16T08:00:02Z [notice] 1#1: using the "epoll" event method
        2026-10-16T08:00:02Z [notice] 1#1: nginx/1.27.2
        2026-10-16T08:00:02Z [notice] 1#1: start worker processes
        192.168.64.1 - - [16/Oct/2026:08:05:12 +0000] "GET /healthz HTTP/1.1" 200 15 "-" "curl/8.7.1"
        """
    }

    public func execCommand(containerID: String, command: [String], user: String?, workdir: String?, env: [String]) async throws -> CommandExecutionResult {
        try record("execCommand:\(containerID):\(command.joined(separator: " "))")
        return CommandExecutionResult(
            executablePath: "/usr/local/bin/container",
            redactedCommand: "container exec \(containerID) \(command.joined(separator: " "))",
            exitStatus: 0,
            stdout: "Linux \(containerID) 6.18.35-kata #1 SMP PREEMPT_DYNAMIC aarch64 Linux\n",
            stderr: "",
            durationMs: 18
        )
    }

    // MARK: - Images

    public func listImages() async throws -> [ImageModel] {
        try record("listImages")
        return lock.withLock { simulatedImages }
    }

    public func inspectImage(reference: String) async throws -> ImageModel {
        try record("inspectImage:\(reference)")
        return try lock.withLock {
            guard let found = simulatedImages.first(where: { $0.fullReference == reference || $0.id == reference }) else {
                throw LadaError(category: .missingImage, explanation: "Image '\(reference)' not found.", suggestedRemediation: "Pull the image first.", isRetryable: false)
            }
            return found
        }
    }

    public func pullImage(request: ImagePullRequest, onProgressLine: @escaping @Sendable (String) -> Void) async throws {
        try record("pullImage:\(request.reference)")
        onProgressLine("Resolving manifest for \(request.reference)…")
        onProgressLine("Downloading layer sha256:4f4fb700ef54 (100%)…")
        onProgressLine("Unpacking OCI image \(request.reference)…")
        let newImg = ImageModel(
            fullReference: request.reference,
            digest: "sha256:" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            creationDate: Date(),
            variants: [
                ImageVariantModel(
                    os: "linux",
                    architecture: "arm64",
                    digest: "sha256:1234567890abcdef",
                    sizeBytes: 32_505_856,
                    created: ISO8601DateFormatter().string(from: Date())
                )
            ]
        )
        lock.withLock {
            simulatedImages.removeAll { $0.fullReference == request.reference }
            simulatedImages.insert(newImg, at: 0)
        }
    }

    public func tagImage(source: String, target: String) async throws {
        try record("tagImage:\(source)->\(target)")
        lock.withLock {
            guard let existing = simulatedImages.first(where: { $0.fullReference == source }) else { return }
            let tagged = ImageModel(
                fullReference: target,
                digest: existing.digest,
                mediaType: existing.mediaType,
                creationDate: existing.creationDate,
                variants: existing.variants,
                annotations: existing.annotations
            )
            simulatedImages.insert(tagged, at: 0)
        }
    }

    public func pushImage(reference: String, platform: String?, scheme: String, onProgressLine: @escaping @Sendable (String) -> Void) async throws {
        try record("pushImage:\(reference)")
        onProgressLine("Pushing manifest for \(reference)…")
    }

    public func deleteImage(reference: String, force: Bool) async throws {
        try record("deleteImage:\(reference)")
        lock.withLock {
            simulatedImages.removeAll { $0.fullReference == reference || $0.id == reference }
        }
    }

    public func pruneImages(allUnused: Bool) async throws -> String {
        try record("pruneImages:all=\(allUnused)")
        return "Reclaimed 0 B"
    }

    public func saveImage(reference: String, outputPath: String, platform: String?) async throws {
        try record("saveImage:\(reference)->\(outputPath)")
    }

    public func loadImage(inputPath: String, force: Bool) async throws {
        try record("loadImage:\(inputPath)")
    }

    // MARK: - Builds & Builder

    public func getBuilderStatus() async throws -> BuilderStatusModel {
        try record("getBuilderStatus")
        return lock.withLock { simulatedBuilderStatus }
    }

    public func startBuilder(cpus: Int, memoryMB: Int) async throws {
        try record("startBuilder:\(cpus)cpus:\(memoryMB)MB")
        lock.withLock {
            simulatedBuilderStatus = BuilderStatusModel(
                isRunning: true,
                id: "buildkit",
                imageReference: "ghcr.io/apple/container-builder-shim/builder:0.13.1",
                state: "running",
                ipAddress: "192.168.64.5",
                cpus: cpus,
                memoryBytes: UInt64(memoryMB) * 1024 * 1024
            )
        }
    }

    public func stopBuilder() async throws {
        try record("stopBuilder")
        lock.withLock {
            simulatedBuilderStatus = BuilderStatusModel(isRunning: false, cpus: simulatedBuilderStatus.cpus, memoryBytes: simulatedBuilderStatus.memoryBytes)
        }
    }

    public func deleteBuilder(force: Bool) async throws {
        try record("deleteBuilder:force=\(force)")
        lock.withLock {
            simulatedBuilderStatus = BuilderStatusModel(isRunning: false)
        }
    }

    public func buildImage(request: ImageBuildRequest, onProgressLine: @escaping @Sendable (String) -> Void) async throws -> CommandExecutionResult {
        try record("buildImage:\(request.tags.joined(separator: ","))")
        onProgressLine("#1 [internal] load build definition from Dockerfile")
        onProgressLine("#2 [1/2] FROM docker.io/library/alpine:3.22")
        onProgressLine("#3 exporting to oci image format")
        for tag in request.tags where !tag.isEmpty {
            let builtImage = ImageModel(
                fullReference: tag,
                digest: "sha256:" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                creationDate: Date(),
                variants: [
                    ImageVariantModel(os: "linux", architecture: "arm64", digest: "sha256:built", sizeBytes: 18_874_368)
                ]
            )
            lock.withLock { simulatedImages.insert(builtImage, at: 0) }
        }
        return CommandExecutionResult(
            executablePath: "/usr/local/bin/container",
            redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: request.buildCLIArguments()),
            exitStatus: 0,
            stdout: "Successfully built \(request.tags.joined(separator: ", "))",
            stderr: "",
            durationMs: 420
        )
    }

    // MARK: - Networks

    public func listNetworks() async throws -> [NetworkModel] {
        try record("listNetworks")
        return lock.withLock { simulatedNetworks }
    }

    public func inspectNetwork(name: String) async throws -> NetworkModel {
        try record("inspectNetwork:\(name)")
        return try lock.withLock {
            guard let found = simulatedNetworks.first(where: { $0.id == name }) else {
                throw LadaError(category: .invalidConfiguration, explanation: "Network '\(name)' not found.", suggestedRemediation: "Refresh networks.", isRetryable: false)
            }
            return found
        }
    }

    public func createNetwork(request: NetworkCreateRequest) async throws {
        guard ValidationUtils.isValidNetworkName(request.name) else {
            throw LadaError(category: .invalidConfiguration, explanation: "Invalid network name '\(request.name)'.", suggestedRemediation: "Use lowercase letters, digits, '.', '_', or '-'.", isRetryable: false)
        }
        try record("createNetwork:\(request.name)")
        let net = NetworkModel(
            id: request.name,
            mode: request.isInternal ? "internal" : "nat",
            plugin: request.plugin,
            ipv4Subnet: request.ipv4Subnet.isEmpty ? "192.168.70.0/24" : request.ipv4Subnet,
            ipv4Gateway: "192.168.70.1",
            ipv6Subnet: request.ipv6Subnet.isEmpty ? nil : request.ipv6Subnet,
            creationDate: Date(),
            isBuiltin: false
        )
        lock.withLock { simulatedNetworks.append(net) }
    }

    public func deleteNetwork(name: String) async throws {
        try record("deleteNetwork:\(name)")
        try lock.withLock {
            if name == "default" {
                throw LadaError(category: .invalidConfiguration, explanation: "The built-in 'default' network cannot be deleted.", suggestedRemediation: "Only user-defined networks can be deleted.", isRetryable: false)
            }
            simulatedNetworks.removeAll { $0.id == name }
        }
    }

    public func pruneNetworks() async throws -> String {
        try record("pruneNetworks")
        return "Pruned unused networks."
    }

    // MARK: - Volumes

    public func listVolumes() async throws -> [VolumeModel] {
        try record("listVolumes")
        return lock.withLock { simulatedVolumes }
    }

    public func inspectVolume(name: String) async throws -> VolumeModel {
        try record("inspectVolume:\(name)")
        return try lock.withLock {
            guard let found = simulatedVolumes.first(where: { $0.id == name }) else {
                throw LadaError(category: .invalidConfiguration, explanation: "Volume '\(name)' not found.", suggestedRemediation: "Refresh volumes.", isRetryable: false)
            }
            return found
        }
    }

    public func createVolume(request: VolumeCreateRequest) async throws {
        guard ValidationUtils.isValidVolumeName(request.name) else {
            throw LadaError(category: .invalidConfiguration, explanation: "Invalid volume name '\(request.name)'.", suggestedRemediation: "Use letters, digits, '.', '_', or '-'.", isRetryable: false)
        }
        try record("createVolume:\(request.name)")
        let vol = VolumeModel(
            id: request.name,
            driver: "local",
            format: "ext4",
            sourcePath: "~/Library/Application Support/com.apple.container/volumes/\(request.name)/volume.img",
            creationDate: Date(),
            sizeInBytes: 10_737_418_240,
            options: ["journal": request.journalMode.rawValue]
        )
        lock.withLock { simulatedVolumes.append(vol) }
    }

    public func deleteVolume(name: String) async throws {
        try record("deleteVolume:\(name)")
        lock.withLock { simulatedVolumes.removeAll { $0.id == name } }
    }

    public func pruneVolumes() async throws -> String {
        try record("pruneVolumes")
        return "Pruned unused volumes."
    }

    // MARK: - Machines

    public func listMachines() async throws -> [MachineModel] {
        try record("listMachines")
        return lock.withLock { simulatedMachines }
    }

    public func inspectMachine(id: String) async throws -> MachineModel {
        try record("inspectMachine:\(id)")
        return try lock.withLock {
            guard let found = simulatedMachines.first(where: { $0.id == id }) else {
                throw LadaError(category: .containerLifecycleFailure, explanation: "Machine '\(id)' not found.", suggestedRemediation: "Refresh machines.", isRetryable: false)
            }
            return found
        }
    }

    public func createMachine(request: MachineCreateRequest) async throws {
        let name = request.name.isEmpty ? "machine-\(simulatedMachines.count + 1)" : request.name
        guard ValidationUtils.isValidMachineName(name) else {
            throw LadaError(category: .invalidConfiguration, explanation: "Invalid machine name '\(name)'.", suggestedRemediation: "Use lowercase letters, digits, and hyphens.", isRetryable: false)
        }
        try record("createMachine:\(name)")
        lock.withLock {
            let machine = MachineModel(
                id: name,
                status: request.bootImmediately ? .running : .stopped,
                isDefault: request.setDefault || simulatedMachines.isEmpty,
                ipAddress: request.bootImmediately ? "192.168.64.25" : nil,
                cpus: request.cpus,
                memoryBytes: UInt64(request.memoryGB) * 1024 * 1024 * 1024,
                createdDate: Date(),
                startedDate: request.bootImmediately ? Date() : nil,
                imageReference: request.imageReference,
                homeMount: request.homeMount,
                virtualizationEnabled: request.enableVirtualization,
                kernelPath: request.customKernelPath.isEmpty ? nil : request.customKernelPath,
                username: NSUserName()
            )
            if request.setDefault {
                simulatedMachines = simulatedMachines.map {
                    MachineModel(id: $0.id, status: $0.status, isDefault: false, ipAddress: $0.ipAddress, cpus: $0.cpus, memoryBytes: $0.memoryBytes, diskSizeBytes: $0.diskSizeBytes, createdDate: $0.createdDate, startedDate: $0.startedDate, imageReference: $0.imageReference, homeMount: $0.homeMount, virtualizationEnabled: $0.virtualizationEnabled, kernelPath: $0.kernelPath, username: $0.username)
                }
            }
            simulatedMachines.append(machine)
        }
    }

    public func startMachine(id: String) async throws {
        try record("startMachine:\(id)")
        lock.withLock {
            guard let idx = simulatedMachines.firstIndex(where: { $0.id == id }) else { return }
            let m = simulatedMachines[idx]
            simulatedMachines[idx] = MachineModel(
                id: m.id, status: .running, isDefault: m.isDefault, ipAddress: "192.168.64.10", cpus: m.cpus, memoryBytes: m.memoryBytes, diskSizeBytes: m.diskSizeBytes, createdDate: m.createdDate, startedDate: Date(), imageReference: m.imageReference, homeMount: m.homeMount, virtualizationEnabled: m.virtualizationEnabled, kernelPath: m.kernelPath, username: m.username
            )
        }
    }

    public func stopMachine(id: String) async throws {
        try record("stopMachine:\(id)")
        lock.withLock {
            guard let idx = simulatedMachines.firstIndex(where: { $0.id == id }) else { return }
            let m = simulatedMachines[idx]
            simulatedMachines[idx] = MachineModel(
                id: m.id, status: .stopped, isDefault: m.isDefault, ipAddress: nil, cpus: m.cpus, memoryBytes: m.memoryBytes, diskSizeBytes: m.diskSizeBytes, createdDate: m.createdDate, startedDate: nil, imageReference: m.imageReference, homeMount: m.homeMount, virtualizationEnabled: m.virtualizationEnabled, kernelPath: m.kernelPath, username: m.username
            )
        }
    }

    public func deleteMachine(id: String) async throws {
        try record("deleteMachine:\(id)")
        lock.withLock { simulatedMachines.removeAll { $0.id == id } }
    }

    public func updateMachineConfig(request: MachineUpdateRequest) async throws {
        try record("updateMachineConfig:\(request.name)")
        lock.withLock {
            guard let idx = simulatedMachines.firstIndex(where: { $0.id == request.name }) else { return }
            let m = simulatedMachines[idx]
            simulatedMachines[idx] = MachineModel(
                id: m.id,
                status: m.status,
                isDefault: m.isDefault,
                ipAddress: m.ipAddress,
                cpus: request.cpus,
                memoryBytes: UInt64(request.memoryGB) * 1024 * 1024 * 1024,
                diskSizeBytes: m.diskSizeBytes,
                createdDate: m.createdDate,
                startedDate: m.startedDate,
                imageReference: m.imageReference,
                homeMount: request.homeMount,
                virtualizationEnabled: request.enableVirtualization,
                kernelPath: request.customKernelPath.isEmpty ? nil : request.customKernelPath,
                username: m.username
            )
        }
    }

    public func setDefaultMachine(id: String) async throws {
        try record("setDefaultMachine:\(id)")
        lock.withLock {
            simulatedMachines = simulatedMachines.map {
                MachineModel(id: $0.id, status: $0.status, isDefault: $0.id == id, ipAddress: $0.ipAddress, cpus: $0.cpus, memoryBytes: $0.memoryBytes, diskSizeBytes: $0.diskSizeBytes, createdDate: $0.createdDate, startedDate: $0.startedDate, imageReference: $0.imageReference, homeMount: $0.homeMount, virtualizationEnabled: $0.virtualizationEnabled, kernelPath: $0.kernelPath, username: $0.username)
            }
        }
    }

    public func fetchMachineLogs(id: String, bootLogs: Bool, tailLines: Int?) async throws -> String {
        try record("fetchMachineLogs:\(id):boot=\(bootLogs)")
        return "[0.120000] container-machine \(id) systemd[1]: Reached target Multi-User System."
    }

    public func runInMachine(id: String, command: [String], asRoot: Bool) async throws -> CommandExecutionResult {
        try record("runInMachine:\(id):\(command.joined(separator: " "))")
        return CommandExecutionResult(
            executablePath: "/usr/local/bin/container",
            redactedCommand: "container machine run -n \(id) -- \(command.joined(separator: " "))",
            exitStatus: 0,
            stdout: "Linux \(id).machine 6.18.35 aarch64\n",
            stderr: "",
            durationMs: 15
        )
    }

    // MARK: - Registries

    public func listRegistries() async throws -> [RegistryModel] {
        try record("listRegistries")
        return lock.withLock { simulatedRegistries }
    }

    public func loginRegistry(server: String, username: String, password: String, scheme: String) async throws {
        try record("loginRegistry:\(server):\(username)")
        let model = RegistryModel(hostname: server, username: username, isAuthenticated: true, scheme: scheme)
        lock.withLock {
            simulatedRegistries.removeAll { $0.hostname == server }
            simulatedRegistries.insert(model, at: 0)
        }
    }

    public func logoutRegistry(server: String) async throws {
        try record("logoutRegistry:\(server)")
        lock.withLock {
            simulatedRegistries.removeAll { $0.hostname == server }
        }
    }
}
