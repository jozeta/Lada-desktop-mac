import Foundation

// MARK: - Network Models (`container network`)

public struct NetworkModel: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String { id }
    public let mode: String
    public let plugin: String
    public let ipv4Subnet: String
    public let ipv4Gateway: String
    public let ipv6Subnet: String?
    public let creationDate: Date
    public let labels: [String: String]
    public let options: [String: String]
    public let isBuiltin: Bool
    public let rawInspectJSON: String?

    public init(
        id: String,
        mode: String = "nat",
        plugin: String = "container-network-vmnet",
        ipv4Subnet: String,
        ipv4Gateway: String = "",
        ipv6Subnet: String? = nil,
        creationDate: Date = Date(),
        labels: [String: String] = [:],
        options: [String: String] = [:],
        isBuiltin: Bool? = nil,
        rawInspectJSON: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.plugin = plugin
        self.ipv4Subnet = ipv4Subnet
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Subnet = ipv6Subnet
        self.creationDate = creationDate
        self.labels = labels
        self.options = options
        self.isBuiltin = isBuiltin ?? (id == "default" || labels["com.apple.container.resource.builtin"] == "true")
        self.rawInspectJSON = rawInspectJSON
    }
}

public struct NetworkCreateRequest: Codable, Sendable, Equatable {
    public var name: String
    public var ipv4Subnet: String
    public var ipv6Subnet: String
    public var isInternal: Bool
    public var plugin: String
    public var labels: [KeyValueEntry]
    public var options: [KeyValueEntry]

    public init(
        name: String = "",
        ipv4Subnet: String = "",
        ipv6Subnet: String = "",
        isInternal: Bool = false,
        plugin: String = "container-network-vmnet",
        labels: [KeyValueEntry] = [],
        options: [KeyValueEntry] = []
    ) {
        self.name = name
        self.ipv4Subnet = ipv4Subnet
        self.ipv6Subnet = ipv6Subnet
        self.isInternal = isInternal
        self.plugin = plugin
        self.labels = labels
        self.options = options
    }

    public func buildCLIArguments() -> [String] {
        var args = ["network", "create"]
        if isInternal {
            args.append("--internal")
        }
        let v4 = ipv4Subnet.trimmingCharacters(in: .whitespaces)
        if !v4.isEmpty {
            args.append(contentsOf: ["--subnet", v4])
        }
        let v6 = ipv6Subnet.trimmingCharacters(in: .whitespaces)
        if !v6.isEmpty {
            args.append(contentsOf: ["--subnet-v6", v6])
        }
        if !plugin.isEmpty && plugin != "container-network-vmnet" {
            args.append(contentsOf: ["--plugin", plugin])
        }
        for label in labels where !label.key.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--label", "\(label.key)=\(label.value)"])
        }
        for opt in options where !opt.key.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--option", "\(opt.key)=\(opt.value)"])
        }
        args.append(name.trimmingCharacters(in: .whitespaces))
        return args
    }
}

// MARK: - Volume Models (`container volume`)

public enum Ext4JournalMode: String, Codable, Sendable, CaseIterable {
    case ordered = "ordered"
    case writeback = "writeback"
    case journal = "journal"

    public var displayDescription: String {
        switch self {
        case .ordered: return "Ordered (Default — journals metadata before data write)"
        case .writeback: return "Writeback (Fastest — metadata only, relaxed ordering)"
        case .journal: return "Full Journal (Safest — journals both metadata and data)"
        }
    }
}

public struct VolumeModel: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String { id }
    public let driver: String
    public let format: String
    public let sourcePath: String
    public let creationDate: Date
    public let sizeInBytes: UInt64?
    public let labels: [String: String]
    public let options: [String: String]
    public let rawInspectJSON: String?

    public init(
        id: String,
        driver: String = "local",
        format: String = "ext4",
        sourcePath: String = "",
        creationDate: Date = Date(),
        sizeInBytes: UInt64? = 549_755_813_888,
        labels: [String: String] = [:],
        options: [String: String] = [:],
        rawInspectJSON: String? = nil
    ) {
        self.id = id
        self.driver = driver
        self.format = format
        self.sourcePath = sourcePath
        self.creationDate = creationDate
        self.sizeInBytes = sizeInBytes
        self.labels = labels
        self.options = options
        self.rawInspectJSON = rawInspectJSON
    }

    public var isAnonymous: Bool {
        labels["com.apple.container.resource.anonymous"] != nil
    }
}

public struct VolumeCreateRequest: Codable, Sendable, Equatable {
    public var name: String
    public var sizeSpec: String
    public var journalMode: Ext4JournalMode
    public var journalSize: String
    public var labels: [KeyValueEntry]

    public init(
        name: String = "",
        sizeSpec: String = "",
        journalMode: Ext4JournalMode = .ordered,
        journalSize: String = "",
        labels: [KeyValueEntry] = []
    ) {
        self.name = name
        self.sizeSpec = sizeSpec
        self.journalMode = journalMode
        self.journalSize = journalSize
        self.labels = labels
    }

    public func buildCLIArguments() -> [String] {
        var args = ["volume", "create"]
        let trimmedSize = sizeSpec.trimmingCharacters(in: .whitespaces)
        if !trimmedSize.isEmpty {
            args.append(contentsOf: ["-s", trimmedSize])
        }
        let trimmedJournalSize = journalSize.trimmingCharacters(in: .whitespaces)
        if journalMode != .ordered || !trimmedJournalSize.isEmpty {
            let journalVal = trimmedJournalSize.isEmpty
                ? "journal=\(journalMode.rawValue)"
                : "journal=\(journalMode.rawValue):\(trimmedJournalSize)"
            args.append(contentsOf: ["--opt", journalVal])
        }
        for label in labels where !label.key.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--label", "\(label.key)=\(label.value)"])
        }
        args.append(name.trimmingCharacters(in: .whitespaces))
        return args
    }
}

// MARK: - Container Machine Models (`container machine`)

public enum HomeMountMode: String, Codable, Sendable, CaseIterable {
    case rw = "rw"
    case ro = "ro"
    case none = "none"

    public var displayTitle: String {
        switch self {
        case .rw: return "Read-Write (rw)"
        case .ro: return "Read-Only (ro)"
        case .none: return "Disabled (none)"
        }
    }
}

public struct MachineModel: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String { id }
    public let status: ContainerState
    public let isDefault: Bool
    public let ipAddress: String?
    public let cpus: Int
    public let memoryBytes: UInt64
    public let diskSizeBytes: UInt64?
    public let createdDate: Date?
    public let startedDate: Date?
    public let imageReference: String?
    public let homeMount: HomeMountMode
    public let virtualizationEnabled: Bool
    public let kernelPath: String?
    public let username: String?
    public let rawInspectJSON: String?

    public init(
        id: String,
        status: ContainerState,
        isDefault: Bool = false,
        ipAddress: String? = nil,
        cpus: Int = 4,
        memoryBytes: UInt64 = 8_589_934_592,
        diskSizeBytes: UInt64? = nil,
        createdDate: Date? = nil,
        startedDate: Date? = nil,
        imageReference: String? = nil,
        homeMount: HomeMountMode = .rw,
        virtualizationEnabled: Bool = false,
        kernelPath: String? = nil,
        username: String? = nil,
        rawInspectJSON: String? = nil
    ) {
        self.id = id
        self.status = status
        self.isDefault = isDefault
        self.ipAddress = ipAddress
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.diskSizeBytes = diskSizeBytes
        self.createdDate = createdDate
        self.startedDate = startedDate
        self.imageReference = imageReference
        self.homeMount = homeMount
        self.virtualizationEnabled = virtualizationEnabled
        self.kernelPath = kernelPath
        self.username = username
        self.rawInspectJSON = rawInspectJSON
    }
}

public struct MachineCreateRequest: Codable, Sendable, Equatable {
    public var name: String
    public var imageReference: String
    public var cpus: Int
    public var memoryGB: Int
    public var homeMount: HomeMountMode
    public var setDefault: Bool
    public var bootImmediately: Bool
    public var enableVirtualization: Bool
    public var customKernelPath: String

    public init(
        name: String = "",
        imageReference: String = "alpine:latest",
        cpus: Int = 4,
        memoryGB: Int = 8,
        homeMount: HomeMountMode = .rw,
        setDefault: Bool = false,
        bootImmediately: Bool = true,
        enableVirtualization: Bool = false,
        customKernelPath: String = ""
    ) {
        self.name = name
        self.imageReference = imageReference
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.homeMount = homeMount
        self.setDefault = setDefault
        self.bootImmediately = bootImmediately
        self.enableVirtualization = enableVirtualization
        self.customKernelPath = customKernelPath
    }

    public func buildCLIArguments() -> [String] {
        var args = ["machine", "create"]
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            args.append(contentsOf: ["--name", trimmedName])
        }
        args.append(contentsOf: ["--cpus", "\(cpus)"])
        args.append(contentsOf: ["--memory", "\(memoryGB)G"])
        args.append(contentsOf: ["--home-mount", homeMount.rawValue])
        if setDefault {
            args.append("--set-default")
        }
        if !bootImmediately {
            args.append("--no-boot")
        }
        if enableVirtualization {
            args.append("--virtualization")
        }
        let kernel = customKernelPath.trimmingCharacters(in: .whitespaces)
        if !kernel.isEmpty {
            args.append(contentsOf: ["--kernel", kernel])
        }
        args.append(imageReference.trimmingCharacters(in: .whitespaces))
        return args
    }
}

public struct MachineUpdateRequest: Codable, Sendable, Equatable {
    public var name: String
    public var cpus: Int
    public var memoryGB: Int
    public var homeMount: HomeMountMode
    public var enableVirtualization: Bool
    public var customKernelPath: String

    public init(
        name: String,
        cpus: Int,
        memoryGB: Int,
        homeMount: HomeMountMode,
        enableVirtualization: Bool = false,
        customKernelPath: String = ""
    ) {
        self.name = name
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.homeMount = homeMount
        self.enableVirtualization = enableVirtualization
        self.customKernelPath = customKernelPath
    }

    public func buildCLIArguments() -> [String] {
        var args = ["machine", "set", "--name", name]
        args.append("cpus=\(cpus)")
        args.append("memory=\(memoryGB)G")
        args.append("home-mount=\(homeMount.rawValue)")
        args.append("virtualization=\(enableVirtualization ? "true" : "false")")
        let trimmedKernel = customKernelPath.trimmingCharacters(in: .whitespaces)
        if !trimmedKernel.isEmpty {
            args.append("kernel=\(trimmedKernel)")
        }
        return args
    }
}

// MARK: - Registry Models (`container registry`)

public struct RegistryModel: Identifiable, Codable, Sendable, Equatable {
    public var id: String { hostname }
    public let hostname: String
    public var username: String
    public var isAuthenticated: Bool
    public var scheme: String
    public var creationDate: Date
    public var modificationDate: Date
    public var lastConnectionStatus: String?

    public init(
        hostname: String,
        username: String,
        isAuthenticated: Bool = true,
        scheme: String = "https",
        creationDate: Date = Date(),
        modificationDate: Date = Date(),
        lastConnectionStatus: String? = nil
    ) {
        self.hostname = hostname
        self.username = username
        self.isAuthenticated = isAuthenticated
        self.scheme = scheme
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.lastConnectionStatus = lastConnectionStatus
    }
}

// MARK: - Activity & Operation Events

public enum ActivityOutcome: String, Codable, Sendable, Equatable {
    case running = "Running"
    case success = "Succeeded"
    case failure = "Failed"
    case warning = "Warning"
}

public struct ActivityEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let correlationID: String
    public let timestamp: Date
    public let category: String
    public let title: String
    public var detail: String
    public var redactedCommand: String?
    public var outcome: ActivityOutcome
    public var durationMs: Int?

    public init(
        id: UUID = UUID(),
        correlationID: String = UUID().uuidString.prefix(8).lowercased(),
        timestamp: Date = Date(),
        category: String,
        title: String,
        detail: String,
        redactedCommand: String? = nil,
        outcome: ActivityOutcome = .success,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.correlationID = correlationID
        self.timestamp = timestamp
        self.category = category
        self.title = title
        self.detail = detail
        self.redactedCommand = redactedCommand
        self.outcome = outcome
        self.durationMs = durationMs
    }
}
