import Foundation

// MARK: - Image Variant & Image Model

public struct ImageVariantModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(os)/\(architecture)/\(variant ?? ""):\(digest)" }
    public let os: String
    public let architecture: String
    public let variant: String?
    public let digest: String
    public let sizeBytes: Int64
    public let created: String?
    public let entrypoint: [String]?
    public let cmd: [String]?
    public let env: [String]?
    public let workingDir: String?
    public let user: String?
    public let exposedPorts: [String]
    public let labels: [String: String]
    public let layerDiffIDs: [String]
    public let history: [ImageHistoryLayer]

    public init(
        os: String = "linux",
        architecture: String = "arm64",
        variant: String? = nil,
        digest: String,
        sizeBytes: Int64 = 0,
        created: String? = nil,
        entrypoint: [String]? = nil,
        cmd: [String]? = nil,
        env: [String]? = nil,
        workingDir: String? = nil,
        user: String? = nil,
        exposedPorts: [String] = [],
        labels: [String: String] = [:],
        layerDiffIDs: [String] = [],
        history: [ImageHistoryLayer] = []
    ) {
        self.os = os
        self.architecture = architecture
        self.variant = variant
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.created = created
        self.entrypoint = entrypoint
        self.cmd = cmd
        self.env = env
        self.workingDir = workingDir
        self.user = user
        self.exposedPorts = exposedPorts
        self.labels = labels
        self.layerDiffIDs = layerDiffIDs
        self.history = history
    }

    public var platformString: String {
        if let variant, !variant.isEmpty {
            return "\(os)/\(architecture)/\(variant)"
        }
        return "\(os)/\(architecture)"
    }
}

public struct ImageHistoryLayer: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(created ?? "")-\(createdBy ?? "")" }
    public let created: String?
    public let createdBy: String?
    public let comment: String?
    public let emptyLayer: Bool

    public init(created: String? = nil, createdBy: String? = nil, comment: String? = nil, emptyLayer: Bool = false) {
        self.created = created
        self.createdBy = createdBy
        self.comment = comment
        self.emptyLayer = emptyLayer
    }
}

public struct ImageModel: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(fullReference)#\(digest)" }
    public let fullReference: String
    public let repository: String
    public let tag: String
    public let registryOrigin: String
    public let digest: String
    public let mediaType: String
    public let creationDate: Date
    public let variants: [ImageVariantModel]
    public let annotations: [String: String]
    public let rawInspectJSON: String?

    public init(
        fullReference: String,
        repository: String? = nil,
        tag: String? = nil,
        registryOrigin: String? = nil,
        digest: String,
        mediaType: String = "application/vnd.oci.image.index.v1+json",
        creationDate: Date = Date(),
        variants: [ImageVariantModel] = [],
        annotations: [String: String] = [:],
        rawInspectJSON: String? = nil
    ) {
        self.fullReference = fullReference
        let parsed = Self.parseReference(fullReference)
        self.repository = repository ?? parsed.repository
        self.tag = tag ?? parsed.tag
        self.registryOrigin = registryOrigin ?? parsed.registry
        self.digest = digest
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.variants = variants
        self.annotations = annotations
        self.rawInspectJSON = rawInspectJSON
    }

    public var shortDigest: String {
        let cleaned = digest.replacingOccurrences(of: "sha256:", with: "")
        return String(cleaned.prefix(12))
    }

    public var totalSizeBytes: Int64 {
        variants.reduce(0) { $0 + $1.sizeBytes }
    }

    public var architecturesSummary: String {
        let valid = variants.filter { !($0.os == "unknown" && $0.architecture == "unknown") }
        guard !valid.isEmpty else { return "arm64" }
        return Array(Set(valid.map(\.platformString))).sorted().joined(separator: ", ")
    }

    public static func parseReference(_ ref: String) -> (registry: String, repository: String, tag: String) {
        var working = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        var tag = "latest"
        if let atIdx = working.lastIndex(of: "@") {
            tag = String(working[working.index(after: atIdx)...])
            working = String(working[..<atIdx])
        } else if let colonIdx = working.lastIndex(of: ":") {
            let afterColon = String(working[working.index(after: colonIdx)...])
            if !afterColon.contains("/") {
                tag = afterColon
                working = String(working[..<colonIdx])
            }
        }
        let parts = working.split(separator: "/").map(String.init)
        if parts.count >= 2,
           let first = parts.first,
           (first.contains(".") || first.contains(":") || first == "localhost") {
            let repo = parts.dropFirst().joined(separator: "/")
            return (first, repo, tag)
        }
        return ("docker.io", working, tag)
    }
}

// MARK: - Image Pull Request

public struct ImagePullRequest: Codable, Sendable, Equatable {
    public var reference: String
    public var platform: String
    public var scheme: String
    public var maxConcurrentDownloads: Int

    public init(
        reference: String = "",
        platform: String = "",
        scheme: String = "https",
        maxConcurrentDownloads: Int = 3
    ) {
        self.reference = reference
        self.platform = platform
        self.scheme = scheme
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }

    public func buildCLIArguments() -> [String] {
        var args = ["image", "pull", "--progress", "plain"]
        if scheme != "https" && !scheme.isEmpty {
            args.append(contentsOf: ["--scheme", scheme])
        }
        if maxConcurrentDownloads != 3 && maxConcurrentDownloads > 0 {
            args.append(contentsOf: ["--max-concurrent-downloads", "\(maxConcurrentDownloads)"])
        }
        if !platform.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--platform", platform.trimmingCharacters(in: .whitespaces)])
        }
        args.append(reference.trimmingCharacters(in: .whitespaces))
        return args
    }
}

// MARK: - Image Build Request & Build History

public struct BuildSecretSpec: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var secretID: String
    public var sourceType: SourceType
    public var sourceValue: String

    public enum SourceType: String, Codable, Sendable, CaseIterable {
        case file = "file"
        case environmentVariable = "env"
    }

    public init(id: UUID = UUID(), secretID: String = "", sourceType: SourceType = .file, sourceValue: String = "") {
        self.id = id
        self.secretID = secretID
        self.sourceType = sourceType
        self.sourceValue = sourceValue
    }

    public var cliFlagValue: String {
        switch sourceType {
        case .file:
            return "id=\(secretID),src=\(sourceValue)"
        case .environmentVariable:
            return "id=\(secretID),env=\(sourceValue)"
        }
    }
}

public struct ImageBuildRequest: Codable, Sendable, Equatable {
    public var contextDirectory: String
    public var containerfilePath: String
    public var tags: [String]
    public var buildArgs: [KeyValueEntry]
    public var labels: [KeyValueEntry]
    public var targetStage: String
    public var platform: String
    public var cpus: Int
    public var memoryMB: Int
    public var noCache: Bool
    public var pullLatest: Bool
    public var forwardSSH: Bool
    public var secrets: [BuildSecretSpec]
    public var outputSpec: String

    public init(
        contextDirectory: String = "",
        containerfilePath: String = "",
        tags: [String] = ["local/my-app:latest"],
        buildArgs: [KeyValueEntry] = [],
        labels: [KeyValueEntry] = [],
        targetStage: String = "",
        platform: String = "",
        cpus: Int = 2,
        memoryMB: Int = 2048,
        noCache: Bool = false,
        pullLatest: Bool = false,
        forwardSSH: Bool = false,
        secrets: [BuildSecretSpec] = [],
        outputSpec: String = ""
    ) {
        self.contextDirectory = contextDirectory
        self.containerfilePath = containerfilePath
        self.tags = tags
        self.buildArgs = buildArgs
        self.labels = labels
        self.targetStage = targetStage
        self.platform = platform
        self.cpus = cpus
        self.memoryMB = memoryMB
        self.noCache = noCache
        self.pullLatest = pullLatest
        self.forwardSSH = forwardSSH
        self.secrets = secrets
        self.outputSpec = outputSpec
    }

    public func buildCLIArguments() -> [String] {
        var args = ["build", "--progress", "plain"]
        let fileTrimmed = containerfilePath.trimmingCharacters(in: .whitespaces)
        if !fileTrimmed.isEmpty {
            args.append(contentsOf: ["-f", fileTrimmed])
        }
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                args.append(contentsOf: ["-t", trimmed])
            }
        }
        for arg in buildArgs {
            let k = arg.key.trimmingCharacters(in: .whitespaces)
            if !k.isEmpty {
                args.append(contentsOf: ["--build-arg", "\(k)=\(arg.value)"])
            }
        }
        for label in labels {
            let k = label.key.trimmingCharacters(in: .whitespaces)
            if !k.isEmpty {
                args.append(contentsOf: ["-l", "\(k)=\(label.value)"])
            }
        }
        if !targetStage.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--target", targetStage.trimmingCharacters(in: .whitespaces)])
        }
        if !platform.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--platform", platform.trimmingCharacters(in: .whitespaces)])
        }
        args.append(contentsOf: ["--cpus", "\(cpus)"])
        args.append(contentsOf: ["--memory", "\(memoryMB)M"])
        if noCache {
            args.append("--no-cache")
        }
        if pullLatest {
            args.append("--pull")
        }
        if forwardSSH {
            args.append(contentsOf: ["--ssh", "default"])
        }
        for secret in secrets where !secret.secretID.isEmpty && !secret.sourceValue.isEmpty {
            args.append(contentsOf: ["--secret", secret.cliFlagValue])
        }
        if !outputSpec.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["-o", outputSpec.trimmingCharacters(in: .whitespaces)])
        }
        args.append(contextDirectory.trimmingCharacters(in: .whitespaces))
        return args
    }
}

public enum BuildStatus: String, Codable, Sendable, Equatable {
    case running = "Running"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

public struct BuildRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let tags: [String]
    public let contextDirectory: String
    public let containerfilePath: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: BuildStatus
    public var exitCode: Int32?
    public var logOutput: String

    public init(
        id: UUID = UUID(),
        tags: [String],
        contextDirectory: String,
        containerfilePath: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: BuildStatus = .running,
        exitCode: Int32? = nil,
        logOutput: String = ""
    ) {
        self.id = id
        self.tags = tags
        self.contextDirectory = contextDirectory
        self.containerfilePath = containerfilePath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.exitCode = exitCode
        self.logOutput = logOutput
    }
}

public struct BuilderStatusModel: Codable, Sendable, Equatable {
    public let isRunning: Bool
    public let id: String
    public let imageReference: String?
    public let state: String
    public let ipAddress: String?
    public let cpus: Int
    public let memoryBytes: UInt64

    public init(
        isRunning: Bool,
        id: String = "buildkit",
        imageReference: String? = nil,
        state: String = "stopped",
        ipAddress: String? = nil,
        cpus: Int = 2,
        memoryBytes: UInt64 = 2_147_483_648
    ) {
        self.isRunning = isRunning
        self.id = id
        self.imageReference = imageReference
        self.state = state
        self.ipAddress = ipAddress
        self.cpus = cpus
        self.memoryBytes = memoryBytes
    }
}
