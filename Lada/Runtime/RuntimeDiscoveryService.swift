import Foundation
import Darwin

public final class RuntimeDiscoveryService: Sendable {
    public static let candidatePaths: [String] = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
        "/usr/bin/container"
    ]

    private let runner: CommandExecuting

    public init(runner: CommandExecuting = CommandRunner.shared) {
        self.runner = runner
    }

    public func detectHostEnvironment() -> HostEnvironmentInfo {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion

        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif

        let brand = Self.sysctlString("machdep.cpu.brand_string") ?? (arch == "arm64" ? "Apple Silicon" : "Intel")
        let buildString = Self.sysctlString("kern.osversion") ?? "unknown"
        let hvSupport = (Self.sysctlInt("kern.hv_support") ?? 0) == 1

        let isAppleSilicon = arch == "arm64"
        let supportsNestedVirt = isAppleSilicon && Self.detectM3OrNewer(brandString: brand)

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let diskBytes: UInt64
        if let vals = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let avail = vals.volumeAvailableCapacityForImportantUsage {
            diskBytes = UInt64(max(0, avail))
        } else {
            diskBytes = 0
        }

        return HostEnvironmentInfo(
            cpuArchitecture: arch,
            cpuBrandString: brand,
            isAppleSilicon: isAppleSilicon,
            supportsNestedVirtualizationChip: supportsNestedVirt,
            macOSMajorVersion: osVersion.majorVersion,
            macOSMinorVersion: osVersion.minorVersion,
            macOSPatchVersion: osVersion.patchVersion,
            macOSVersionString: processInfo.operatingSystemVersionString,
            macOSBuildString: buildString,
            physicalMemoryBytes: processInfo.physicalMemory,
            processorCount: processInfo.processorCount,
            availableDiskSpaceBytes: diskBytes,
            hypervisorFrameworkAvailable: hvSupport
        )
    }

    public func discoverRuntime(customExecutablePath: String? = nil) async -> RuntimeInstallation {
        let fm = FileManager.default
        let configPath = ("~/.config/container/config.toml" as NSString).expandingTildeInPath
        let defaultAppRoot = ("~/Library/Application Support/com.apple.container" as NSString).expandingTildeInPath

        var searchPaths: [String] = []
        if let custom = customExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            searchPaths.append(custom)
        }
        for candidate in Self.candidatePaths where !searchPaths.contains(candidate) {
            searchPaths.append(candidate)
        }

        guard let resolvedPath = searchPaths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return RuntimeInstallation(
                isInstalled: false,
                executablePath: nil,
                installRootPath: nil,
                appRootPath: fm.fileExists(atPath: defaultAppRoot) ? defaultAppRoot : nil,
                configFilePath: configPath
            )
        }

        let installRoot = URL(fileURLWithPath: resolvedPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        // Check helper plugins under <installRoot>/libexec/container or /usr/local/libexec/container
        let helperCandidates = [
            "\(installRoot)/libexec/container",
            "\(installRoot)/bin/container-apiserver",
            "/usr/local/libexec/container",
            "/usr/local/bin/container-apiserver"
        ]
        let helpersPresent = helperCandidates.contains { fm.fileExists(atPath: $0) }

        // Check default kernel under appRoot
        let kernelCandidates = [
            "\(defaultAppRoot)/kernels/default.kernel",
            "\(defaultAppRoot)/kernels/vmlinux",
            "\(defaultAppRoot)/kernels"
        ]
        var kernelPresent = false
        var resolvedKernelPath: String? = nil
        for kp in kernelCandidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: kp, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let items = try? fm.contentsOfDirectory(atPath: kp), !items.isEmpty {
                        kernelPresent = true
                        resolvedKernelPath = "\(kp)/\(items[0])"
                        break
                    }
                } else {
                    kernelPresent = true
                    resolvedKernelPath = kp
                    break
                }
            }
        }

        // Query CLI version via `container system version --format json` or fallback `container --version`
        var cliVersion: SemanticVersion? = nil
        var rawVersion: String? = nil
        var buildType: String? = nil
        var commitHash: String? = nil

        if let verResult = try? await runner.execute(
            executablePath: resolvedPath,
            arguments: ["system", "version", "--format", "json"],
            environment: nil,
            stdinData: nil,
            timeoutSeconds: 8
        ), verResult.isSuccess,
           let parsed = try? ContainerOutputParser.parseSystemVersions(jsonString: verResult.stdout),
           let cliComp = parsed.first(where: { $0.appName == "container" }) ?? parsed.first {
            rawVersion = cliComp.version
            cliVersion = SemanticVersion(parsing: cliComp.version)
            buildType = cliComp.buildType
            commitHash = cliComp.commit
        } else if let fallbackResult = try? await runner.execute(
            executablePath: resolvedPath,
            arguments: ["--version"],
            environment: nil,
            stdinData: nil,
            timeoutSeconds: 5
        ) {
            let text = fallbackResult.stdout.isEmpty ? fallbackResult.stderr : fallbackResult.stdout
            rawVersion = text.trimmingCharacters(in: .whitespacesAndNewlines)
            cliVersion = SemanticVersion(parsing: text)
        }

        return RuntimeInstallation(
            isInstalled: true,
            executablePath: resolvedPath,
            installRootPath: installRoot,
            appRootPath: defaultAppRoot,
            cliVersion: cliVersion,
            rawVersionString: rawVersion,
            buildType: buildType,
            commitHash: commitHash,
            helperPluginsPresent: helpersPresent,
            defaultKernelInstalled: kernelPresent,
            kernelBinaryPath: resolvedKernelPath,
            configFilePath: configPath
        )
    }

    // MARK: - Helpers

    private static func detectM3OrNewer(brandString: String) -> Bool {
        let pattern = #"Apple M(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: brandString, range: NSRange(brandString.startIndex..., in: brandString)),
              let genRange = Range(match.range(at: 1), in: brandString),
              let gen = Int(brandString[genRange]) else {
            return false
        }
        return gen >= 3
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
