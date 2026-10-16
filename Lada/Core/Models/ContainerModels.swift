import Foundation

// MARK: - Container Lifecycle State

public enum ContainerState: String, Codable, Sendable, Equatable, CaseIterable {
    case running = "running"
    case stopped = "stopped"
    case stopping = "stopping"
    case created = "created"
    case exited = "exited"
    case unknown = "unknown"

    public init(rawRuntimeState: String) {
        switch rawRuntimeState.lowercased() {
        case "running": self = .running
        case "stopped": self = .stopped
        case "stopping": self = .stopping
        case "created": self = .created
        case "exited": self = .exited
        default: self = .unknown
        }
    }

    public var displayTitle: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .stopping: return "Stopping"
        case .created: return "Created"
        case .exited: return "Exited"
        case .unknown: return "Unknown"
        }
    }

    public var isRunning: Bool {
        self == .running
    }
}

// MARK: - Port & Socket Mappings

public struct PortMapping: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var hostAddress: String
    public var hostPort: UInt16
    public var containerPort: UInt16
    public var proto: String
    public var count: UInt16

    public init(
        id: UUID = UUID(),
        hostAddress: String = "127.0.0.1",
        hostPort: UInt16,
        containerPort: UInt16,
        proto: String = "tcp",
        count: UInt16 = 1
    ) {
        self.id = id
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.proto = proto.lowercased()
        self.count = count
    }

    public static func == (lhs: PortMapping, rhs: PortMapping) -> Bool {
        lhs.hostAddress == rhs.hostAddress &&
        lhs.hostPort == rhs.hostPort &&
        lhs.containerPort == rhs.containerPort &&
        lhs.proto == rhs.proto &&
        lhs.count == rhs.count
    }

    public var cliSpec: String {
        let hostPrefix = hostAddress.isEmpty ? "" : "\(hostAddress):"
        return "\(hostPrefix)\(hostPort):\(containerPort)/\(proto)"
    }
}

public struct SocketMapping: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var hostPath: String
    public var containerPath: String

    public init(id: UUID = UUID(), hostPath: String, containerPath: String) {
        self.id = id
        self.hostPath = hostPath
        self.containerPath = containerPath
    }

    public static func == (lhs: SocketMapping, rhs: SocketMapping) -> Bool {
        lhs.hostPath == rhs.hostPath && lhs.containerPath == rhs.containerPath
    }

    public var cliSpec: String {
        "\(hostPath):\(containerPath)"
    }
}

// MARK: - Mounts & Filesystems

public enum MountKind: String, Codable, Sendable, Equatable, CaseIterable {
    case bind = "bind"
    case volume = "volume"
    case tmpfs = "tmpfs"
    case block = "block"

    public var displayName: String {
        switch self {
        case .bind: return "Bind Mount (virtiofs)"
        case .volume: return "Named Volume (ext4)"
        case .tmpfs: return "Tmpfs (Memory)"
        case .block: return "Block Device"
        }
    }
}

public struct MountAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var kind: MountKind
    public var source: String
    public var destination: String
    public var readOnly: Bool
    public var options: [String]
    public var volumeName: String?

    public init(
        id: UUID = UUID(),
        kind: MountKind = .bind,
        source: String = "",
        destination: String,
        readOnly: Bool = false,
        options: [String] = [],
        volumeName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.destination = destination
        self.readOnly = readOnly
        self.options = options
        self.volumeName = volumeName
    }

    public static func == (lhs: MountAttachment, rhs: MountAttachment) -> Bool {
        lhs.kind == rhs.kind &&
        lhs.source == rhs.source &&
        lhs.destination == rhs.destination &&
        lhs.readOnly == rhs.readOnly &&
        lhs.options == rhs.options &&
        lhs.volumeName == rhs.volumeName
    }

    public var cliMountFlag: String {
        switch kind {
        case .bind:
            var parts = ["type=bind", "source=\(source)", "target=\(destination)"]
            if readOnly { parts.append("readonly") }
            return parts.joined(separator: ",")
        case .volume:
            var parts = ["type=volume"]
            let src = volumeName ?? source
            if !src.isEmpty { parts.append("source=\(src)") }
            parts.append("target=\(destination)")
            if readOnly { parts.append("readonly") }
            return parts.joined(separator: ",")
        case .tmpfs:
            var parts = ["type=tmpfs", "target=\(destination)"]
            if readOnly { parts.append("readonly") }
            for opt in options where opt.hasPrefix("size=") || opt.hasPrefix("mode=") {
                parts.append(opt)
            }
            return parts.joined(separator: ",")
        case .block:
            var parts = ["type=bind", "source=\(source)", "target=\(destination)"]
            if readOnly { parts.append("readonly") }
            return parts.joined(separator: ",")
        }
    }
}

// MARK: - Network Attachment

public struct ContainerNetworkAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(network):\(ipv4Address)" }
    public let network: String
    public let hostname: String
    public let ipv4Address: String
    public let ipv4Gateway: String
    public let ipv6Address: String?
    public let macAddress: String?
    public let mtu: UInt32?

    public init(
        network: String,
        hostname: String,
        ipv4Address: String,
        ipv4Gateway: String,
        ipv6Address: String? = nil,
        macAddress: String? = nil,
        mtu: UInt32? = nil
    ) {
        self.network = network
        self.hostname = hostname
        self.ipv4Address = ipv4Address
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
        self.mtu = mtu
    }
}

// MARK: - Container Configuration & Model

public struct ContainerConfigurationModel: Codable, Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String]
    public var workingDirectory: String
    public var terminal: Bool
    public var user: String
    public var cpus: Int
    public var memoryInBytes: UInt64
    public var shmSizeInBytes: UInt64?
    public var os: String
    public var arch: String
    public var readOnlyRootfs: Bool
    public var useInit: Bool
    public var initImage: String?
    public var rosetta: Bool
    public var virtualization: Bool
    public var sshForwarding: Bool
    public var runtimeHandler: String
    public var capAdd: [String]
    public var capDrop: [String]
    public var maskedPaths: [String]?
    public var readonlyPaths: [String]?
    public var dnsNameservers: [String]
    public var dnsDomain: String?
    public var dnsSearchDomains: [String]
    public var dnsOptions: [String]
    public var labels: [String: String]
    public var sysctls: [String: String]
    public var mounts: [MountAttachment]
    public var publishedPorts: [PortMapping]
    public var publishedSockets: [SocketMapping]
    public var configuredNetworks: [String]

    public init(
        executable: String = "/bin/sh",
        arguments: [String] = [],
        environment: [String] = [],
        workingDirectory: String = "/",
        terminal: Bool = false,
        user: String = "0:0",
        cpus: Int = 4,
        memoryInBytes: UInt64 = 1_073_741_824,
        shmSizeInBytes: UInt64? = nil,
        os: String = "linux",
        arch: String = "arm64",
        readOnlyRootfs: Bool = false,
        useInit: Bool = false,
        initImage: String? = nil,
        rosetta: Bool = false,
        virtualization: Bool = false,
        sshForwarding: Bool = false,
        runtimeHandler: String = "container-runtime-linux",
        capAdd: [String] = [],
        capDrop: [String] = [],
        maskedPaths: [String]? = nil,
        readonlyPaths: [String]? = nil,
        dnsNameservers: [String] = ["1.1.1.1"],
        dnsDomain: String? = nil,
        dnsSearchDomains: [String] = [],
        dnsOptions: [String] = [],
        labels: [String: String] = [:],
        sysctls: [String: String] = [:],
        mounts: [MountAttachment] = [],
        publishedPorts: [PortMapping] = [],
        publishedSockets: [SocketMapping] = [],
        configuredNetworks: [String] = ["default"]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.terminal = terminal
        self.user = user
        self.cpus = cpus
        self.memoryInBytes = memoryInBytes
        self.shmSizeInBytes = shmSizeInBytes
        self.os = os
        self.arch = arch
        self.readOnlyRootfs = readOnlyRootfs
        self.useInit = useInit
        self.initImage = initImage
        self.rosetta = rosetta
        self.virtualization = virtualization
        self.sshForwarding = sshForwarding
        self.runtimeHandler = runtimeHandler
        self.capAdd = capAdd
        self.capDrop = capDrop
        self.maskedPaths = maskedPaths
        self.readonlyPaths = readonlyPaths
        self.dnsNameservers = dnsNameservers
        self.dnsDomain = dnsDomain
        self.dnsSearchDomains = dnsSearchDomains
        self.dnsOptions = dnsOptions
        self.labels = labels
        self.sysctls = sysctls
        self.mounts = mounts
        self.publishedPorts = publishedPorts
        self.publishedSockets = publishedSockets
        self.configuredNetworks = configuredNetworks
    }
}

public struct ContainerModel: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String { id }
    public let imageReference: String
    public let imageDigest: String?
    public let state: ContainerState
    public let rawState: String
    public let creationDate: Date
    public let startedDate: Date?
    public let configuration: ContainerConfigurationModel
    public let networks: [ContainerNetworkAttachment]
    public let rawInspectJSON: String?

    public init(
        id: String,
        imageReference: String,
        imageDigest: String? = nil,
        state: ContainerState,
        rawState: String? = nil,
        creationDate: Date = Date(),
        startedDate: Date? = nil,
        configuration: ContainerConfigurationModel = .init(),
        networks: [ContainerNetworkAttachment] = [],
        rawInspectJSON: String? = nil
    ) {
        self.id = id
        self.imageReference = imageReference
        self.imageDigest = imageDigest
        self.state = state
        self.rawState = rawState ?? state.rawValue
        self.creationDate = creationDate
        self.startedDate = startedDate
        self.configuration = configuration
        self.networks = networks
        self.rawInspectJSON = rawInspectJSON
    }

    public var primaryIPv4: String? {
        guard let first = networks.first?.ipv4Address else { return nil }
        return first.components(separatedBy: "/").first
    }

    public var portsSummary: String {
        guard !configuration.publishedPorts.isEmpty else { return "—" }
        return configuration.publishedPorts.map(\.cliSpec).joined(separator: ", ")
    }

    public var memoryFormatted: String {
        let mib = configuration.memoryInBytes / (1024 * 1024)
        if mib >= 1024 && mib % 1024 == 0 {
            return "\(mib / 1024) GiB"
        }
        return "\(mib) MiB"
    }
}

// MARK: - Container Stats (`container stats --format json --no-stream`)

public struct ContainerStatsModel: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let cpuUsageUsec: UInt64
    public let memoryUsageBytes: UInt64
    public let memoryLimitBytes: UInt64
    public let networkRxBytes: UInt64
    public let networkTxBytes: UInt64
    public let blockReadBytes: UInt64
    public let blockWriteBytes: UInt64
    public let numProcesses: Int

    public init(
        id: String,
        cpuUsageUsec: UInt64 = 0,
        memoryUsageBytes: UInt64 = 0,
        memoryLimitBytes: UInt64 = 1_073_741_824,
        networkRxBytes: UInt64 = 0,
        networkTxBytes: UInt64 = 0,
        blockReadBytes: UInt64 = 0,
        blockWriteBytes: UInt64 = 0,
        numProcesses: Int = 0
    ) {
        self.id = id
        self.cpuUsageUsec = cpuUsageUsec
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.numProcesses = numProcesses
    }

    public var memoryPercentage: Double {
        guard memoryLimitBytes > 0 else { return 0 }
        return min(100.0, (Double(memoryUsageBytes) / Double(memoryLimitBytes)) * 100.0)
    }
}

public struct ContainerPerformanceSample: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let cpuPercent: Double
    public let memoryUsageBytes: UInt64
    public let memoryLimitBytes: UInt64
    public let memoryPercent: Double
    public let networkRxRateBps: Double
    public let networkTxRateBps: Double
    public let totalNetworkRxBytes: UInt64
    public let totalNetworkTxBytes: UInt64
    public let diskReadRateBps: Double
    public let diskWriteRateBps: Double
    public let totalDiskReadBytes: UInt64
    public let totalDiskWriteBytes: UInt64
    public let numProcesses: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        cpuPercent: Double = 0,
        memoryUsageBytes: UInt64 = 0,
        memoryLimitBytes: UInt64 = 1_073_741_824,
        memoryPercent: Double = 0,
        networkRxRateBps: Double = 0,
        networkTxRateBps: Double = 0,
        totalNetworkRxBytes: UInt64 = 0,
        totalNetworkTxBytes: UInt64 = 0,
        diskReadRateBps: Double = 0,
        diskWriteRateBps: Double = 0,
        totalDiskReadBytes: UInt64 = 0,
        totalDiskWriteBytes: UInt64 = 0,
        numProcesses: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.cpuPercent = max(0, min(100, cpuPercent))
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.memoryPercent = max(0, min(100, memoryPercent))
        self.networkRxRateBps = max(0, networkRxRateBps)
        self.networkTxRateBps = max(0, networkTxRateBps)
        self.totalNetworkRxBytes = totalNetworkRxBytes
        self.totalNetworkTxBytes = totalNetworkTxBytes
        self.diskReadRateBps = max(0, diskReadRateBps)
        self.diskWriteRateBps = max(0, diskWriteRateBps)
        self.totalDiskReadBytes = totalDiskReadBytes
        self.totalDiskWriteBytes = totalDiskWriteBytes
        self.numProcesses = numProcesses
    }
}

// MARK: - Create Container Request

public struct KeyValueEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var key: String
    public var value: String
    public var isSecret: Bool

    public init(id: UUID = UUID(), key: String = "", value: String = "", isSecret: Bool = false) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}

public struct ContainerCreateRequest: Codable, Sendable, Equatable {
    public var name: String
    public var imageReference: String
    public var startImmediately: Bool
    public var removeWhenStopped: Bool
    public var entrypointOverride: String
    public var commandArguments: [String]
    public var workingDirectory: String
    public var userSpec: String
    public var uid: String
    public var gid: String
    public var interactive: Bool
    public var allocateTTY: Bool
    public var publishedPorts: [PortMapping]
    public var publishedSockets: [SocketMapping]
    public var networkName: String
    public var macAddress: String
    public var mtu: String
    public var dnsAliases: [String]
    public var disableDNS: Bool
    public var dnsNameservers: [String]
    public var dnsDomain: String
    public var dnsSearchDomains: [String]
    public var dnsOptions: [String]
    public var mounts: [MountAttachment]
    public var environmentVariables: [KeyValueEntry]
    public var envFilePath: String
    public var cpus: Int
    public var memoryMB: Int
    public var shmSize: String
    public var readOnlyRootfs: Bool
    public var useInitProcess: Bool
    public var customInitImage: String
    public var capAdd: [String]
    public var capDrop: [String]
    public var sshAgentForwarding: Bool
    public var exposeVirtualization: Bool
    public var enableRosetta: Bool
    public var customKernelPath: String
    public var kernelArgs: [String]
    public var maskedPaths: [String]
    public var readOnlyPaths: [String]
    public var platform: String
    public var arch: String
    public var os: String
    public var labels: [KeyValueEntry]
    public var ulimits: [String]
    public var scheme: String
    /// Unsupported fields explicitly tracked so we never silently ignore them
    public var requestedUnsupportedRestartPolicy: String?
    /// Optional Dockerfile / Containerfile source for drag-and-drop or editor deployment
    public var dockerfileContent: String?
    public var dockerfileSourcePath: String?
    public var dockerfileContextDirectory: String?
    public var buildFromDockerfileBeforeRun: Bool
    public var dockerfileBaseImage: String?

    public var hasAttachedDockerfile: Bool {
        if let content = dockerfileContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let path = dockerfileSourcePath, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    public init(
        name: String = "",
        imageReference: String = "",
        startImmediately: Bool = true,
        removeWhenStopped: Bool = false,
        entrypointOverride: String = "",
        commandArguments: [String] = [],
        workingDirectory: String = "",
        userSpec: String = "",
        uid: String = "",
        gid: String = "",
        interactive: Bool = false,
        allocateTTY: Bool = false,
        publishedPorts: [PortMapping] = [],
        publishedSockets: [SocketMapping] = [],
        networkName: String = "default",
        macAddress: String = "",
        mtu: String = "",
        dnsAliases: [String] = [],
        disableDNS: Bool = false,
        dnsNameservers: [String] = [],
        dnsDomain: String = "",
        dnsSearchDomains: [String] = [],
        dnsOptions: [String] = [],
        mounts: [MountAttachment] = [],
        environmentVariables: [KeyValueEntry] = [],
        envFilePath: String = "",
        cpus: Int = 4,
        memoryMB: Int = 1024,
        shmSize: String = "",
        readOnlyRootfs: Bool = false,
        useInitProcess: Bool = false,
        customInitImage: String = "",
        capAdd: [String] = [],
        capDrop: [String] = [],
        sshAgentForwarding: Bool = false,
        exposeVirtualization: Bool = false,
        enableRosetta: Bool = false,
        customKernelPath: String = "",
        kernelArgs: [String] = [],
        maskedPaths: [String] = [],
        readOnlyPaths: [String] = [],
        platform: String = "",
        arch: String = "",
        os: String = "",
        labels: [KeyValueEntry] = [],
        ulimits: [String] = [],
        scheme: String = "https",
        requestedUnsupportedRestartPolicy: String? = nil,
        dockerfileContent: String? = nil,
        dockerfileSourcePath: String? = nil,
        dockerfileContextDirectory: String? = nil,
        buildFromDockerfileBeforeRun: Bool = false,
        dockerfileBaseImage: String? = nil
    ) {
        self.name = name
        self.imageReference = imageReference
        self.startImmediately = startImmediately
        self.removeWhenStopped = removeWhenStopped
        self.entrypointOverride = entrypointOverride
        self.commandArguments = commandArguments
        self.workingDirectory = workingDirectory
        self.userSpec = userSpec
        self.uid = uid
        self.gid = gid
        self.interactive = interactive
        self.allocateTTY = allocateTTY
        self.publishedPorts = publishedPorts
        self.publishedSockets = publishedSockets
        self.networkName = networkName
        self.macAddress = macAddress
        self.mtu = mtu
        self.dnsAliases = dnsAliases
        self.disableDNS = disableDNS
        self.dnsNameservers = dnsNameservers
        self.dnsDomain = dnsDomain
        self.dnsSearchDomains = dnsSearchDomains
        self.dnsOptions = dnsOptions
        self.mounts = mounts
        self.environmentVariables = environmentVariables
        self.envFilePath = envFilePath
        self.cpus = cpus
        self.memoryMB = memoryMB
        self.shmSize = shmSize
        self.readOnlyRootfs = readOnlyRootfs
        self.useInitProcess = useInitProcess
        self.customInitImage = customInitImage
        self.capAdd = capAdd
        self.capDrop = capDrop
        self.sshAgentForwarding = sshAgentForwarding
        self.exposeVirtualization = exposeVirtualization
        self.enableRosetta = enableRosetta
        self.customKernelPath = customKernelPath
        self.kernelArgs = kernelArgs
        self.maskedPaths = maskedPaths
        self.readOnlyPaths = readOnlyPaths
        self.platform = platform
        self.arch = arch
        self.os = os
        self.labels = labels
        self.ulimits = ulimits
        self.scheme = scheme
        self.requestedUnsupportedRestartPolicy = requestedUnsupportedRestartPolicy
        self.dockerfileContent = dockerfileContent
        self.dockerfileSourcePath = dockerfileSourcePath
        self.dockerfileContextDirectory = dockerfileContextDirectory
        self.buildFromDockerfileBeforeRun = buildFromDockerfileBeforeRun
        self.dockerfileBaseImage = dockerfileBaseImage
    }

    public static func duplicating(_ container: ContainerModel) -> ContainerCreateRequest {
        let cfg = container.configuration
        let envEntries = cfg.environment.map { raw -> KeyValueEntry in
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts.first ?? raw
            let val = parts.count > 1 ? parts[1] : ""
            return KeyValueEntry(
                key: key,
                value: val,
                isSecret: SecretRedactor.isSensitiveKey(key)
            )
        }
        let labelEntries = cfg.labels.map { KeyValueEntry(key: $0.key, value: $0.value) }
        return ContainerCreateRequest(
            name: "\(container.id)-copy",
            imageReference: container.imageReference,
            startImmediately: true,
            removeWhenStopped: false,
            entrypointOverride: cfg.executable,
            commandArguments: cfg.arguments,
            workingDirectory: cfg.workingDirectory == "/" ? "" : cfg.workingDirectory,
            userSpec: cfg.user == "0:0" ? "" : cfg.user,
            interactive: cfg.terminal,
            allocateTTY: cfg.terminal,
            publishedPorts: cfg.publishedPorts,
            publishedSockets: cfg.publishedSockets,
            networkName: cfg.configuredNetworks.first ?? "default",
            dnsNameservers: cfg.dnsNameservers == ["1.1.1.1"] ? [] : cfg.dnsNameservers,
            dnsDomain: cfg.dnsDomain ?? "",
            dnsSearchDomains: cfg.dnsSearchDomains,
            dnsOptions: cfg.dnsOptions,
            mounts: cfg.mounts,
            environmentVariables: envEntries,
            cpus: cfg.cpus,
            memoryMB: max(64, Int(cfg.memoryInBytes / (1024 * 1024))),
            shmSize: cfg.shmSizeInBytes.map { "\($0 / (1024 * 1024))M" } ?? "",
            readOnlyRootfs: cfg.readOnlyRootfs,
            useInitProcess: cfg.useInit,
            customInitImage: cfg.initImage ?? "",
            capAdd: cfg.capAdd,
            capDrop: cfg.capDrop,
            sshAgentForwarding: cfg.sshForwarding,
            exposeVirtualization: cfg.virtualization,
            enableRosetta: cfg.rosetta,
            maskedPaths: cfg.maskedPaths ?? [],
            readOnlyPaths: cfg.readonlyPaths ?? [],
            arch: cfg.arch,
            os: cfg.os,
            labels: labelEntries
        )
    }

    /// Generates the exact `container` CLI argument array (`run -d` or `create`)
    public func buildCLIArguments() -> [String] {
        var args: [String] = []
        if startImmediately {
            args.append("run")
            args.append("-d")
        } else {
            args.append("create")
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            args.append(contentsOf: ["--name", trimmedName])
        }
        if removeWhenStopped {
            args.append("--rm")
        }
        let lowerImage = imageReference.lowercased()
        let isShellBaseImage = (
            lowerImage.hasPrefix("alpine") ||
            lowerImage.hasPrefix("ubuntu") ||
            lowerImage.hasPrefix("debian") ||
            lowerImage.hasPrefix("busybox") ||
            lowerImage.hasPrefix("fedora") ||
            lowerImage.hasPrefix("golang") ||
            lowerImage.hasPrefix("rust") ||
            lowerImage.hasPrefix("swift")
        ) && commandArguments.isEmpty && entrypointOverride.trimmingCharacters(in: .whitespaces).isEmpty

        if interactive || (startImmediately && isShellBaseImage) {
            args.append("-i")
        }
        if allocateTTY || (startImmediately && isShellBaseImage) {
            args.append("-t")
        }
        if !workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--workdir", workingDirectory.trimmingCharacters(in: .whitespaces)])
        }
        if !userSpec.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--user", userSpec.trimmingCharacters(in: .whitespaces)])
        }
        if !uid.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--uid", uid.trimmingCharacters(in: .whitespaces)])
        }
        if !gid.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--gid", gid.trimmingCharacters(in: .whitespaces)])
        }
        if !entrypointOverride.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--entrypoint", entrypointOverride.trimmingCharacters(in: .whitespaces)])
        }

        // Resources
        args.append(contentsOf: ["--cpus", "\(cpus)"])
        args.append(contentsOf: ["--memory", "\(memoryMB)M"])
        if !shmSize.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--shm-size", shmSize.trimmingCharacters(in: .whitespaces)])
        }

        // Networking
        let net = networkName.trimmingCharacters(in: .whitespaces)
        if !net.isEmpty {
            var netSpec = net
            if !macAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                netSpec += ",mac=\(macAddress.trimmingCharacters(in: .whitespaces))"
            }
            if !mtu.trimmingCharacters(in: .whitespaces).isEmpty {
                netSpec += ",mtu=\(mtu.trimmingCharacters(in: .whitespaces))"
            }
            for alias in dnsAliases where !alias.trimmingCharacters(in: .whitespaces).isEmpty {
                netSpec += ",alias=\(alias.trimmingCharacters(in: .whitespaces))"
            }
            if netSpec != "default" {
                args.append(contentsOf: ["--network", netSpec])
            }
        }

        for port in publishedPorts {
            args.append(contentsOf: ["-p", port.cliSpec])
        }
        for sock in publishedSockets {
            args.append(contentsOf: ["--publish-socket", sock.cliSpec])
        }

        if disableDNS {
            args.append("--no-dns")
        } else {
            for ns in dnsNameservers where !ns.trimmingCharacters(in: .whitespaces).isEmpty {
                args.append(contentsOf: ["--dns", ns.trimmingCharacters(in: .whitespaces)])
            }
            if !dnsDomain.trimmingCharacters(in: .whitespaces).isEmpty {
                args.append(contentsOf: ["--dns-domain", dnsDomain.trimmingCharacters(in: .whitespaces)])
            }
            for search in dnsSearchDomains where !search.trimmingCharacters(in: .whitespaces).isEmpty {
                args.append(contentsOf: ["--dns-search", search.trimmingCharacters(in: .whitespaces)])
            }
            for opt in dnsOptions where !opt.trimmingCharacters(in: .whitespaces).isEmpty {
                args.append(contentsOf: ["--dns-option", opt.trimmingCharacters(in: .whitespaces)])
            }
        }

        // Storage mounts
        for mount in mounts {
            args.append(contentsOf: ["--mount", mount.cliMountFlag])
        }

        // Environment
        if !envFilePath.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--env-file", envFilePath.trimmingCharacters(in: .whitespaces)])
        }
        var hasPGDataSubdir = false
        var hasPostgresPassword = false
        var hasMySQLAuth = false
        for env in environmentVariables {
            let key = env.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if key == "PGDATA" {
                hasPGDataSubdir = true
                // If PGDATA points directly to the EXT4 volume mount point, redirect to /pgdata subdirectory to avoid lost+found errors
                let val = env.value == "/var/lib/postgresql/data" ? "/var/lib/postgresql/data/pgdata" : env.value
                args.append(contentsOf: ["-e", "\(key)=\(val)"])
                continue
            }
            if key == "POSTGRES_PASSWORD" || key == "POSTGRES_HOST_AUTH_METHOD" {
                hasPostgresPassword = true
            }
            if key == "MYSQL_ROOT_PASSWORD" || key == "MYSQL_ALLOW_EMPTY_PASSWORD" || key == "MYSQL_RANDOM_ROOT_PASSWORD" || key == "MARIADB_ROOT_PASSWORD" {
                hasMySQLAuth = true
            }
            if env.value.isEmpty {
                args.append(contentsOf: ["-e", key])
            } else {
                args.append(contentsOf: ["-e", "\(key)=\(env.value)"])
            }
        }
        if lowerImage.contains("postgres") {
            if !hasPGDataSubdir {
                args.append(contentsOf: ["-e", "PGDATA=/var/lib/postgresql/data/pgdata"])
            }
            if !hasPostgresPassword {
                args.append(contentsOf: ["-e", "POSTGRES_PASSWORD=postgres"])
            }
        }
        if lowerImage.contains("mysql") || lowerImage.contains("mariadb") {
            if !hasMySQLAuth {
                args.append(contentsOf: ["-e", "MYSQL_ROOT_PASSWORD=rootpassword"])
            }
        }

        // Security & execution
        if readOnlyRootfs {
            args.append("--read-only")
        }
        if useInitProcess {
            args.append("--init")
        }
        if !customInitImage.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--init-image", customInitImage.trimmingCharacters(in: .whitespaces)])
        }
        for cap in capAdd where !cap.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--cap-add", cap.trimmingCharacters(in: .whitespaces)])
        }
        for cap in capDrop where !cap.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--cap-drop", cap.trimmingCharacters(in: .whitespaces)])
        }
        if sshAgentForwarding {
            args.append("--ssh")
        }
        if exposeVirtualization {
            args.append("--virtualization")
        }
        if enableRosetta {
            args.append("--rosetta")
        }
        if !customKernelPath.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--kernel", customKernelPath.trimmingCharacters(in: .whitespaces)])
        }
        for karg in kernelArgs where !karg.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--kernel-arg", karg.trimmingCharacters(in: .whitespaces)])
        }
        for mp in maskedPaths where !mp.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--masked-path", mp.trimmingCharacters(in: .whitespaces)])
        }
        for rop in readOnlyPaths where !rop.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--read-only-path", rop.trimmingCharacters(in: .whitespaces)])
        }

        // Platform & labels
        if !platform.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--platform", platform.trimmingCharacters(in: .whitespaces)])
        } else {
            if !os.trimmingCharacters(in: .whitespaces).isEmpty && os != "linux" {
                args.append(contentsOf: ["--os", os.trimmingCharacters(in: .whitespaces)])
            }
            if !arch.trimmingCharacters(in: .whitespaces).isEmpty && arch != "arm64" {
                args.append(contentsOf: ["--arch", arch.trimmingCharacters(in: .whitespaces)])
            }
        }
        for label in labels {
            let k = label.key.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { continue }
            args.append(contentsOf: ["-l", "\(k)=\(label.value)"])
        }
        for ulimit in ulimits where !ulimit.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--ulimit", ulimit.trimmingCharacters(in: .whitespaces)])
        }
        if scheme != "https" && !scheme.isEmpty {
            args.append(contentsOf: ["--scheme", scheme])
        }

        args.append(imageReference.trimmingCharacters(in: .whitespaces))
        var finalCommandArgs = commandArguments.filter { !$0.isEmpty }
        if (lowerImage.contains("mysql") || lowerImage.contains("mariadb")) &&
            mounts.contains(where: { $0.destination == "/var/lib/mysql" }) &&
            !finalCommandArgs.contains(where: { $0.hasPrefix("--datadir") }) {
            finalCommandArgs.append("--datadir=/var/lib/mysql/data")
        }
        for cmdArg in finalCommandArgs {
            args.append(cmdArg)
        }
        return args
    }
}
