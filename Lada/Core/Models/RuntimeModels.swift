import Foundation

// MARK: - Semantic Version

public struct SemanticVersion: Comparable, Codable, Sendable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Extract version token such as "1.5.0" or "v1.5.0" or "container version 1.5.0 ..."
        let pattern = #"v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let majorRange = Range(match.range(at: 1), in: trimmed),
              let minorRange = Range(match.range(at: 2), in: trimmed),
              let patchRange = Range(match.range(at: 3), in: trimmed),
              let major = Int(trimmed[majorRange]),
              let minor = Int(trimmed[minorRange]),
              let patch = Int(trimmed[patchRange]) else {
            return nil
        }
        var pre: String? = nil
        if match.range(at: 4).location != NSNotFound,
           let preRange = Range(match.range(at: 4), in: trimmed) {
            pre = String(trimmed[preRange])
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = pre
    }

    public var description: String {
        if let prerelease, !prerelease.isEmpty {
            return "\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (.some, .none): return true
        case (.none, .some): return false
        case (.some(let l), .some(let r)): return l < r
        case (.none, .none): return false
        }
    }
}

// MARK: - Runtime Installation & Host Environment

public struct HostEnvironmentInfo: Codable, Sendable, Equatable {
    public let cpuArchitecture: String
    public let cpuBrandString: String
    public let isAppleSilicon: Bool
    public let supportsNestedVirtualizationChip: Bool
    public let macOSMajorVersion: Int
    public let macOSMinorVersion: Int
    public let macOSPatchVersion: Int
    public let macOSVersionString: String
    public let macOSBuildString: String
    public let physicalMemoryBytes: UInt64
    public let processorCount: Int
    public let availableDiskSpaceBytes: UInt64
    public let hypervisorFrameworkAvailable: Bool

    public init(
        cpuArchitecture: String,
        cpuBrandString: String,
        isAppleSilicon: Bool,
        supportsNestedVirtualizationChip: Bool,
        macOSMajorVersion: Int,
        macOSMinorVersion: Int,
        macOSPatchVersion: Int,
        macOSVersionString: String,
        macOSBuildString: String,
        physicalMemoryBytes: UInt64,
        processorCount: Int,
        availableDiskSpaceBytes: UInt64,
        hypervisorFrameworkAvailable: Bool
    ) {
        self.cpuArchitecture = cpuArchitecture
        self.cpuBrandString = cpuBrandString
        self.isAppleSilicon = isAppleSilicon
        self.supportsNestedVirtualizationChip = supportsNestedVirtualizationChip
        self.macOSMajorVersion = macOSMajorVersion
        self.macOSMinorVersion = macOSMinorVersion
        self.macOSPatchVersion = macOSPatchVersion
        self.macOSVersionString = macOSVersionString
        self.macOSBuildString = macOSBuildString
        self.physicalMemoryBytes = physicalMemoryBytes
        self.processorCount = processorCount
        self.availableDiskSpaceBytes = availableDiskSpaceBytes
        self.hypervisorFrameworkAvailable = hypervisorFrameworkAvailable
    }

    public var isSupportedMacOS: Bool {
        macOSMajorVersion >= 26
    }
}

public struct RuntimeInstallation: Codable, Sendable, Equatable {
    public let isInstalled: Bool
    public let executablePath: String?
    public let installRootPath: String?
    public let appRootPath: String?
    public let cliVersion: SemanticVersion?
    public let rawVersionString: String?
    public let buildType: String?
    public let commitHash: String?
    public let helperPluginsPresent: Bool
    public let defaultKernelInstalled: Bool
    public let kernelBinaryPath: String?
    public let configFilePath: String

    public init(
        isInstalled: Bool,
        executablePath: String?,
        installRootPath: String? = nil,
        appRootPath: String? = nil,
        cliVersion: SemanticVersion? = nil,
        rawVersionString: String? = nil,
        buildType: String? = nil,
        commitHash: String? = nil,
        helperPluginsPresent: Bool = false,
        defaultKernelInstalled: Bool = false,
        kernelBinaryPath: String? = nil,
        configFilePath: String = ("~/.config/container/config.toml" as NSString).expandingTildeInPath
    ) {
        self.isInstalled = isInstalled
        self.executablePath = executablePath
        self.installRootPath = installRootPath
        self.appRootPath = appRootPath
        self.cliVersion = cliVersion
        self.rawVersionString = rawVersionString
        self.buildType = buildType
        self.commitHash = commitHash
        self.helperPluginsPresent = helperPluginsPresent
        self.defaultKernelInstalled = defaultKernelInstalled
        self.kernelBinaryPath = kernelBinaryPath
        self.configFilePath = configFilePath
    }
}

// MARK: - Runtime System Status

public enum RuntimeServiceState: String, Codable, Sendable, Equatable {
    case running = "running"
    case stopped = "not running"
    case unregistered = "unregistered"
    case missingCLI = "missing_cli"
    case error = "error"
    case starting = "starting"
    case stopping = "stopping"

    public var displayTitle: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .unregistered: return "Not Initialized"
        case .missingCLI: return "CLI Missing"
        case .error: return "Degraded / Error"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        }
    }

    public var isHealthy: Bool {
        self == .running
    }
}

public struct RuntimeComponentVersion: Codable, Sendable, Equatable, Identifiable {
    public var id: String { appName }
    public let appName: String
    public let version: String
    public let buildType: String
    public let commit: String

    public init(appName: String, version: String, buildType: String, commit: String) {
        self.appName = appName
        self.version = version
        self.buildType = buildType
        self.commit = commit
    }
}

public struct RuntimeSystemStatus: Codable, Sendable, Equatable {
    public let state: RuntimeServiceState
    public let clientVersion: RuntimeComponentVersion?
    public let serverVersion: RuntimeComponentVersion?
    public let appRoot: String?
    public let installRoot: String?
    public let logRoot: String?
    public let containersTotal: Int
    public let containersRunning: Int
    public let imagesTotal: Int?
    public let statusMessage: String?
    public let checkedAt: Date

    public init(
        state: RuntimeServiceState,
        clientVersion: RuntimeComponentVersion? = nil,
        serverVersion: RuntimeComponentVersion? = nil,
        appRoot: String? = nil,
        installRoot: String? = nil,
        logRoot: String? = nil,
        containersTotal: Int = 0,
        containersRunning: Int = 0,
        imagesTotal: Int? = nil,
        statusMessage: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.state = state
        self.clientVersion = clientVersion
        self.serverVersion = serverVersion
        self.appRoot = appRoot
        self.installRoot = installRoot
        self.logRoot = logRoot
        self.containersTotal = containersTotal
        self.containersRunning = containersRunning
        self.imagesTotal = imagesTotal
        self.statusMessage = statusMessage
        self.checkedAt = checkedAt
    }
}

// MARK: - Disk Usage (`container system df`)

public struct ResourceDiskUsage: Codable, Sendable, Equatable {
    public let total: Int
    public let active: Int
    public let sizeInBytes: UInt64
    public let reclaimable: UInt64

    public init(total: Int = 0, active: Int = 0, sizeInBytes: UInt64 = 0, reclaimable: UInt64 = 0) {
        self.total = total
        self.active = active
        self.sizeInBytes = sizeInBytes
        self.reclaimable = reclaimable
    }
}

public struct DiskUsageSummary: Codable, Sendable, Equatable {
    public let images: ResourceDiskUsage
    public let containers: ResourceDiskUsage
    public let volumes: ResourceDiskUsage

    public init(
        images: ResourceDiskUsage = .init(),
        containers: ResourceDiskUsage = .init(),
        volumes: ResourceDiskUsage = .init()
    ) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
    }

    public var totalBytes: UInt64 {
        images.sizeInBytes + containers.sizeInBytes + volumes.sizeInBytes
    }

    public var totalReclaimableBytes: UInt64 {
        images.reclaimable + containers.reclaimable + volumes.reclaimable
    }
}

// MARK: - System Properties (`container system property list --format json`)

public struct SystemProperties: Codable, Sendable, Equatable {
    public struct BuildSettings: Codable, Sendable, Equatable {
        public var cpus: Int
        public var memory: String
        public var rosetta: Bool
        public var image: String

        public init(cpus: Int = 2, memory: String = "2048mb", rosetta: Bool = true, image: String = "ghcr.io/apple/container-builder-shim/builder:0.13.1") {
            self.cpus = cpus
            self.memory = memory
            self.rosetta = rosetta
            self.image = image
        }
    }

    public struct ContainerDefaults: Codable, Sendable, Equatable {
        public var cpus: Int
        public var memory: String

        public init(cpus: Int = 4, memory: String = "1gb") {
            self.cpus = cpus
            self.memory = memory
        }
    }

    public struct DNSSettings: Codable, Sendable, Equatable {
        public var domain: String?
        public init(domain: String? = nil) { self.domain = domain }
    }

    public struct KernelSettings: Codable, Sendable, Equatable {
        public var binaryPath: String?
        public var url: String?
        public var digest: String?

        public init(binaryPath: String? = nil, url: String? = nil, digest: String? = nil) {
            self.binaryPath = binaryPath
            self.url = url
            self.digest = digest
        }
    }

    public struct NetworkSettings: Codable, Sendable, Equatable {
        public var subnet: String?
        public var subnetv6: String?

        public init(subnet: String? = nil, subnetv6: String? = nil) {
            self.subnet = subnet
            self.subnetv6 = subnetv6
        }
    }

    public struct RegistrySettings: Codable, Sendable, Equatable {
        public var domain: String
        public init(domain: String = "docker.io") { self.domain = domain }
    }

    public struct VMInitSettings: Codable, Sendable, Equatable {
        public var image: String
        public init(image: String = "ghcr.io/apple/containerization/vminit:0.34.0") { self.image = image }
    }

    public var build: BuildSettings
    public var container: ContainerDefaults
    public var dns: DNSSettings
    public var kernel: KernelSettings
    public var network: NetworkSettings
    public var registry: RegistrySettings
    public var vminit: VMInitSettings

    public init(
        build: BuildSettings = .init(),
        container: ContainerDefaults = .init(),
        dns: DNSSettings = .init(),
        kernel: KernelSettings = .init(),
        network: NetworkSettings = .init(),
        registry: RegistrySettings = .init(),
        vminit: VMInitSettings = .init()
    ) {
        self.build = build
        self.container = container
        self.dns = dns
        self.kernel = kernel
        self.network = network
        self.registry = registry
        self.vminit = vminit
    }
}

// MARK: - Prerequisite Models

public enum PrerequisiteStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case checking = "Checking"
    case ready = "Ready"
    case missing = "Missing"
    case incompatible = "Incompatible"
    case needsAttention = "NeedsAttention"
    case failed = "Failed"

    public var displayLabel: String {
        switch self {
        case .checking: return "Checking"
        case .ready: return "Ready"
        case .missing: return "Missing"
        case .incompatible: return "Incompatible"
        case .needsAttention: return "Needs Attention"
        case .failed: return "Failed"
        }
    }
}

public enum PrerequisiteActionType: String, Codable, Sendable, Equatable {
    case none
    case installCLI
    case startSystemService
    case installDefaultKernel
    case openReleasePage
    case recheck
}

public struct PrerequisiteItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public var detectedStatusText: String
    public let isRequired: Bool
    public let explanation: String
    public var recommendedRemediation: String
    public var status: PrerequisiteStatus
    public var actionTitle: String?
    public var actionType: PrerequisiteActionType
    public var verificationDetail: String?

    public init(
        id: String,
        name: String,
        detectedStatusText: String,
        isRequired: Bool,
        explanation: String,
        recommendedRemediation: String,
        status: PrerequisiteStatus,
        actionTitle: String? = nil,
        actionType: PrerequisiteActionType = .none,
        verificationDetail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detectedStatusText = detectedStatusText
        self.isRequired = isRequired
        self.explanation = explanation
        self.recommendedRemediation = recommendedRemediation
        self.status = status
        self.actionTitle = actionTitle
        self.actionType = actionType
        self.verificationDetail = verificationDetail
    }
}

// MARK: - Official Release Metadata

public struct ReleaseAssetInfo: Codable, Sendable, Equatable {
    public let tagName: String
    public let releaseName: String
    public let publishedAt: String
    public let assetName: String
    public let downloadURL: URL
    public let sizeBytes: Int64
    public let sha256Digest: String?
    public let releasePageURL: URL
    public let publisher: String

    public init(
        tagName: String,
        releaseName: String,
        publishedAt: String,
        assetName: String,
        downloadURL: URL,
        sizeBytes: Int64,
        sha256Digest: String?,
        releasePageURL: URL,
        publisher: String = "Apple Inc. (github.com/apple/container)"
    ) {
        self.tagName = tagName
        self.releaseName = releaseName
        self.publishedAt = publishedAt
        self.assetName = assetName
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.sha256Digest = sha256Digest
        self.releasePageURL = releasePageURL
        self.publisher = publisher
    }
}
