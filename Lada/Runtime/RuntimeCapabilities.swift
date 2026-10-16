import Foundation

public enum FeatureSupportState: Sendable, Codable, Equatable {
    case supported
    case experimental(reason: String)
    case unsupported(reason: String)

    public var isEnabledByDefault: Bool {
        if case .supported = self { return true }
        return false
    }

    public var statusDescription: String {
        switch self {
        case .supported:
            return "Supported"
        case .experimental(let reason):
            return "Experimental — \(reason)"
        case .unsupported(let reason):
            return "Unsupported — \(reason)"
        }
    }
}

public struct RuntimeCapabilities: Sendable, Codable, Equatable {
    public let detectedVersion: SemanticVersion?
    public let containerLifecycle: FeatureSupportState
    public let containerStats: FeatureSupportState
    public let containerExportAndCopy: FeatureSupportState
    public let containerRestartPolicies: FeatureSupportState
    public let containerPathMasking: FeatureSupportState
    public let nestedVirtualization: FeatureSupportState
    public let imageManagement: FeatureSupportState
    public let imageBuilds: FeatureSupportState
    public let builderLifecycle: FeatureSupportState
    public let registryAuthentication: FeatureSupportState
    public let networkManagement: FeatureSupportState
    public let volumeManagement: FeatureSupportState
    public let containerMachines: FeatureSupportState
    public let interactiveLogsAndExec: FeatureSupportState
    public let systemDiskUsage: FeatureSupportState
    public let systemProperties: FeatureSupportState
    public let kubernetesClusters: FeatureSupportState

    public init(
        detectedVersion: SemanticVersion?,
        hostEnvironment: HostEnvironmentInfo
    ) {
        self.detectedVersion = detectedVersion
        let version = detectedVersion ?? SemanticVersion(major: 1, minor: 5, patch: 0)

        guard hostEnvironment.isAppleSilicon else {
            let reason = "Apple's container runtime requires a Mac with Apple silicon (arm64)."
            self.containerLifecycle = .unsupported(reason: reason)
            self.containerStats = .unsupported(reason: reason)
            self.containerExportAndCopy = .unsupported(reason: reason)
            self.containerRestartPolicies = .unsupported(reason: reason)
            self.containerPathMasking = .unsupported(reason: reason)
            self.nestedVirtualization = .unsupported(reason: reason)
            self.imageManagement = .unsupported(reason: reason)
            self.imageBuilds = .unsupported(reason: reason)
            self.builderLifecycle = .unsupported(reason: reason)
            self.registryAuthentication = .unsupported(reason: reason)
            self.networkManagement = .unsupported(reason: reason)
            self.volumeManagement = .unsupported(reason: reason)
            self.containerMachines = .unsupported(reason: reason)
            self.interactiveLogsAndExec = .unsupported(reason: reason)
            self.systemDiskUsage = .unsupported(reason: reason)
            self.systemProperties = .unsupported(reason: reason)
            self.kubernetesClusters = .unsupported(reason: reason)
            return
        }

        self.containerLifecycle = .supported
        self.containerStats = version >= SemanticVersion(major: 0, minor: 4, patch: 0)
            ? .supported
            : .unsupported(reason: "Requires container runtime 0.4.0 or newer.")
        self.containerExportAndCopy = .supported
        self.containerRestartPolicies = .unsupported(
            reason: "Apple's `container` runtime does not implement automatic `--restart` policies; containers are started and stopped explicitly or via launchd."
        )
        self.containerPathMasking = .experimental(
            reason: "`--masked-path` and `--read-only-path` are marked experimental in `container` 1.5.0."
        )
        self.nestedVirtualization = hostEnvironment.supportsNestedVirtualizationChip
            ? .supported
            : .unsupported(reason: "Nested virtualization (`--virtualization`) requires Apple silicon M3 or newer and a kernel built with CONFIG_KVM=y.")
        self.imageManagement = .supported
        self.imageBuilds = .supported
        self.builderLifecycle = .supported
        self.registryAuthentication = .supported
        self.networkManagement = hostEnvironment.macOSMajorVersion >= 26
            ? .supported
            : .unsupported(reason: "Isolated user-defined vmnet networks require macOS 26 or newer.")
        self.volumeManagement = .supported
        self.containerMachines = version >= SemanticVersion(major: 0, minor: 10, patch: 0)
            ? .supported
            : .unsupported(reason: "Container machines (`container machine`) require runtime 0.10.0 or newer.")
        self.interactiveLogsAndExec = .supported
        self.systemDiskUsage = .supported
        self.systemProperties = .supported
        self.kubernetesClusters = .experimental(
            reason: "`container k8s` is an upstream experimental plugin."
        )
    }
}
