import Foundation
import CryptoKit
import AppKit

public final class RuntimeHealthService: Sendable {
    public static let minimumSupportedRuntimeVersion = SemanticVersion(major: 0, minor: 4, patch: 0)
    public static let recommendedRuntimeVersion = SemanticVersion(major: 1, minor: 5, patch: 0)
    public static let officialReleasesURL = URL(string: "https://github.com/apple/container/releases")!
    public static let officialLatestReleaseAPIURL = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!

    private let discoveryService: RuntimeDiscoveryService
    private let runner: CommandExecuting

    public init(
        discoveryService: RuntimeDiscoveryService = RuntimeDiscoveryService(),
        runner: CommandExecuting = CommandRunner.shared
    ) {
        self.discoveryService = discoveryService
        self.runner = runner
    }

    public func evaluatePrerequisites(
        host: HostEnvironmentInfo,
        installation: RuntimeInstallation,
        systemStatus: RuntimeSystemStatus
    ) -> [PrerequisiteItem] {
        var items: [PrerequisiteItem] = []

        // 1. Compatible Mac hardware
        items.append(PrerequisiteItem(
            id: "hardware.arch",
            name: "Compatible Mac Hardware",
            detectedStatusText: "\(host.cpuBrandString) (\(host.cpuArchitecture))",
            isRequired: true,
            explanation: "Apple's container runtime runs lightweight Linux virtual machines optimized specifically for Apple silicon (arm64).",
            recommendedRemediation: host.isAppleSilicon
                ? "Apple silicon hardware verified."
                : "Apple silicon (M1 or newer) is required to run Apple's container runtime.",
            status: host.isAppleSilicon ? .ready : .incompatible
        ))

        // 2. Supported macOS version
        items.append(PrerequisiteItem(
            id: "os.version",
            name: "Supported macOS Version",
            detectedStatusText: "macOS \(host.macOSMajorVersion).\(host.macOSMinorVersion) (Build \(host.macOSBuildString))",
            isRequired: true,
            explanation: "Apple's container runtime requires macOS 26 or later for Virtualization.framework and vmnet isolation features.",
            recommendedRemediation: host.isSupportedMacOS
                ? "Supported macOS release verified."
                : "Upgrade to macOS 26 or newer to use Apple's container runtime.",
            status: host.isSupportedMacOS ? .ready : .incompatible
        ))

        // 3. Virtualization & Hypervisor Capabilities
        items.append(PrerequisiteItem(
            id: "host.virtualization",
            name: "Virtualization & Hypervisor Support",
            detectedStatusText: host.hypervisorFrameworkAvailable
                ? (host.supportsNestedVirtualizationChip ? "Hypervisor ready (Nested KVM supported)" : "Hypervisor ready")
                : "Hypervisor unavailable",
            isRequired: true,
            explanation: "Every container runs inside a dedicated lightweight virtual machine managed by macOS Virtualization.framework.",
            recommendedRemediation: host.hypervisorFrameworkAvailable
                ? "Hardware virtualization capabilities are enabled."
                : "Verify that macOS virtualization is supported on this machine and not blocked by hypervisor restrictions.",
            status: host.hypervisorFrameworkAvailable ? .ready : .failed
        ))

        // 4. Sufficient Available Disk Space
        let diskGB = Double(host.availableDiskSpaceBytes) / 1_073_741_824.0
        let minDiskBytes: UInt64 = 5 * 1_073_741_824 // 5 GiB
        items.append(PrerequisiteItem(
            id: "host.disk",
            name: "Available Disk Space",
            detectedStatusText: String(format: "%.1f GB available", diskGB),
            isRequired: true,
            explanation: "OCI images, container rootfs sparse images, BuildKit caches, and Linux kernels require local storage.",
            recommendedRemediation: host.availableDiskSpaceBytes >= minDiskBytes
                ? "Sufficient disk capacity available."
                : "Free at least 5 GB of disk space before pulling images or initializing the runtime.",
            status: host.availableDiskSpaceBytes >= minDiskBytes ? .ready : .needsAttention
        ))

        // 5. Apple `container` CLI Installed
        items.append(PrerequisiteItem(
            id: "cli.installed",
            name: "Apple `container` CLI Installed",
            detectedStatusText: installation.isInstalled
                ? (installation.executablePath ?? "Installed")
                : "Not found in /usr/local/bin or /opt/homebrew/bin",
            isRequired: true,
            explanation: "Låda communicates with Apple's official `container` command-line binary to manage containers, images, and services.",
            recommendedRemediation: installation.isInstalled
                ? "CLI executable discovered at \(installation.executablePath ?? "")."
                : "Download and install the signed official `container` installer package from Apple's GitHub releases.",
            status: installation.isInstalled ? .ready : .missing,
            actionTitle: installation.isInstalled ? nil : "Install Official Package…",
            actionType: installation.isInstalled ? .none : .installCLI
        ))

        // 6. CLI Executable Accessible
        let cliAccessible = installation.isInstalled && (installation.executablePath != nil)
        items.append(PrerequisiteItem(
            id: "cli.accessible",
            name: "CLI Executable Accessible",
            detectedStatusText: cliAccessible ? "Executable permissions verified" : "Unavailable",
            isRequired: true,
            explanation: "Låda requires execute permissions on the resolved `container` binary.",
            recommendedRemediation: cliAccessible
                ? "Executable is accessible."
                : "Install the `container` CLI or configure a valid binary path in Settings → Runtime.",
            status: cliAccessible ? .ready : .missing
        ))

        // 7. Runtime Version Compatible with Låda
        let versionStatus: PrerequisiteStatus
        let versionText: String
        if let ver = installation.cliVersion {
            versionText = "v\(ver.description)"
            versionStatus = ver >= Self.minimumSupportedRuntimeVersion ? .ready : .incompatible
        } else if installation.isInstalled {
            versionText = installation.rawVersionString ?? "Unknown version"
            versionStatus = .needsAttention
        } else {
            versionText = "Not installed"
            versionStatus = .missing
        }
        items.append(PrerequisiteItem(
            id: "cli.version",
            name: "Runtime Version Compatibility",
            detectedStatusText: versionText,
            isRequired: true,
            explanation: "Låda supports Apple container runtime \(Self.minimumSupportedRuntimeVersion.description)+ and is optimized for v\(Self.recommendedRuntimeVersion.description).",
            recommendedRemediation: versionStatus == .ready
                ? "Installed runtime version is compatible."
                : "Install or upgrade to Apple `container` v\(Self.recommendedRuntimeVersion.description).",
            status: versionStatus,
            actionTitle: versionStatus == .incompatible ? "Update Runtime…" : nil,
            actionType: versionStatus == .incompatible ? .installCLI : .none
        ))

        // 8. Required Helper Components Installed
        let helpersStatus: PrerequisiteStatus = !installation.isInstalled
            ? .missing
            : (installation.helperPluginsPresent ? .ready : .needsAttention)
        items.append(PrerequisiteItem(
            id: "runtime.helpers",
            name: "Required Helper Components",
            detectedStatusText: installation.helperPluginsPresent
                ? "APIServer & runtime plugins present"
                : (installation.isInstalled ? "Helper directory not detected" : "Not installed"),
            isRequired: true,
            explanation: "`container-apiserver`, `container-runtime-linux`, and `container-network-vmnet` provide the background XPC services.",
            recommendedRemediation: installation.helperPluginsPresent
                ? "Helper executables and plugins are installed."
                : "Reinstall the official `container` signed installer package so all plugins under `/usr/local/libexec/container` are present.",
            status: helpersStatus
        ))

        // 9. Container System Initialized & API Server Responsive
        let apiResponsive = systemStatus.state == .running
        let apiStatus: PrerequisiteStatus
        if !installation.isInstalled {
            apiStatus = .missing
        } else if apiResponsive {
            apiStatus = .ready
        } else {
            apiStatus = .needsAttention
        }
        items.append(PrerequisiteItem(
            id: "runtime.apiserver",
            name: "Container API Server Responsive",
            detectedStatusText: systemStatus.state.displayTitle,
            isRequired: true,
            explanation: "`container-apiserver` must be registered with launchd and running to manage containers, images, volumes, and networks.",
            recommendedRemediation: apiResponsive
                ? "API server is running and responding to health checks."
                : "Click 'Start System' to run `container system start` and register background services.",
            status: apiStatus,
            actionTitle: (installation.isInstalled && !apiResponsive) ? "Start System" : nil,
            actionType: (installation.isInstalled && !apiResponsive) ? .startSystemService : .none
        ))

        // 10. Required Linux Kernel Available
        let kernelReady = installation.defaultKernelInstalled || apiResponsive
        let kernelStatus: PrerequisiteStatus
        if !installation.isInstalled {
            kernelStatus = .missing
        } else if kernelReady {
            kernelStatus = .ready
        } else {
            kernelStatus = .needsAttention
        }
        items.append(PrerequisiteItem(
            id: "runtime.kernel",
            name: "Default Linux Kernel Available",
            detectedStatusText: installation.defaultKernelInstalled
                ? (installation.kernelBinaryPath ?? "Installed")
                : (apiResponsive ? "Managed by active runtime" : "Kernel not yet initialized"),
            isRequired: false,
            explanation: "A guest Linux kernel (Kata Containers vmlinux) is required to boot container VMs.",
            recommendedRemediation: kernelReady
                ? "Guest Linux kernel is available."
                : "Run `container system kernel set --recommended` or `container system start --enable-kernel-install`.",
            status: kernelStatus,
            actionTitle: (installation.isInstalled && !kernelReady) ? "Install Recommended Kernel" : nil,
            actionType: (installation.isInstalled && !kernelReady) ? .installDefaultKernel : .none
        ))

        return items
    }

    // MARK: - Official Release Discovery & Verification

    public func fetchLatestOfficialRelease() async throws -> ReleaseAssetInfo {
        var request = URLRequest(url: Self.officialLatestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LadaError(
                category: .networkFailure,
                explanation: "Unable to query official release metadata from GitHub (`apple/container`).",
                suggestedRemediation: "Check your internet connection or open https://github.com/apple/container/releases directly.",
                isRetryable: true,
                documentationURL: Self.officialReleasesURL
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLStr = json["html_url"] as? String,
              let releasePageURL = URL(string: htmlURLStr),
              let assets = json["assets"] as? [[String: Any]] else {
            throw LadaError(
                category: .internalError,
                explanation: "Unexpected release metadata structure from GitHub API.",
                suggestedRemediation: "Open the official release page manually to download the signed `.pkg` installer.",
                isRetryable: true,
                documentationURL: Self.officialReleasesURL
            )
        }

        // Prefer the signed installer package (`*-installer-signed.pkg`)
        let signedAsset = assets.first {
            guard let name = $0["name"] as? String else { return false }
            return name.hasSuffix("-installer-signed.pkg")
        } ?? assets.first {
            guard let name = $0["name"] as? String else { return false }
            return name.hasSuffix(".pkg")
        }

        guard let asset = signedAsset,
              let assetName = asset["name"] as? String,
              let downloadURLStr = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLStr),
              downloadURL.scheme == "https" else {
            throw LadaError(
                category: .missingPrerequisites,
                explanation: "No signed `.pkg` installer asset found in release \(tagName).",
                suggestedRemediation: "Download the installer from the official GitHub release page.",
                isRetryable: false,
                documentationURL: releasePageURL
            )
        }

        let sizeBytes = Int64((asset["size"] as? Int) ?? 0)
        let digest = asset["digest"] as? String
        let publishedAt = (json["published_at"] as? String) ?? ""
        let releaseName = (json["name"] as? String) ?? tagName

        return ReleaseAssetInfo(
            tagName: tagName,
            releaseName: releaseName,
            publishedAt: publishedAt,
            assetName: assetName,
            downloadURL: downloadURL,
            sizeBytes: sizeBytes,
            sha256Digest: digest,
            releasePageURL: releasePageURL
        )
    }

    public func downloadAndVerifyInstaller(
        release: ReleaseAssetInfo,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        guard release.downloadURL.scheme == "https",
              let host = release.downloadURL.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".githubusercontent.com") else {
            throw LadaError(
                category: .permissionError,
                explanation: "Refusing to download installer from untrusted origin: \(release.downloadURL.absoluteString)",
                suggestedRemediation: "Only official HTTPS releases from github.com/apple/container are permitted.",
                isRetryable: false
            )
        }

        onProgress("Downloading \(release.assetName) (\(ByteCountFormatter.string(fromByteCount: release.sizeBytes, countStyle: .file)))…")

        let (tempURL, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LadaError(
                category: .networkFailure,
                explanation: "Failed to download \(release.assetName) over HTTPS.",
                suggestedRemediation: "Verify your network connection or download manually from \(release.releasePageURL.absoluteString).",
                isRetryable: true
            )
        }

        let destinationDir = FileManager.default.temporaryDirectory.appendingPathComponent("com.lada.installer", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let pkgURL = destinationDir.appendingPathComponent(release.assetName)
        if FileManager.default.fileExists(atPath: pkgURL.path) {
            try FileManager.default.removeItem(at: pkgURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: pkgURL)

        // Verify SHA-256 digest if provided by release metadata
        if let expectedDigest = release.sha256Digest, !expectedDigest.isEmpty {
            onProgress("Verifying SHA-256 cryptographic digest…")
            let data = try Data(contentsOf: pkgURL, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data)
            let computedHex = "sha256:" + hash.compactMap { String(format: "%02x", $0) }.joined()
            if computedHex.lowercased() != expectedDigest.lowercased() {
                try? FileManager.default.removeItem(at: pkgURL)
                throw LadaError(
                    category: .permissionError,
                    explanation: "Installer SHA-256 checksum mismatch (expected \(expectedDigest), got \(computedHex)).",
                    suggestedRemediation: "The downloaded package was removed for safety. Please retry or inspect your network connection.",
                    isRetryable: true
                )
            }
        }

        // Verify Apple / Developer ID package signature via `/usr/sbin/pkgutil --check-signature`
        if FileManager.default.isExecutableFile(atPath: "/usr/sbin/pkgutil") {
            onProgress("Verifying package cryptographic signature via pkgutil…")
            let sigResult = try await runner.execute(
                executablePath: "/usr/sbin/pkgutil",
                arguments: ["--check-signature", pkgURL.path],
                environment: nil,
                stdinData: nil,
                timeoutSeconds: 20
            )
            if !sigResult.isSuccess {
                try? FileManager.default.removeItem(at: pkgURL)
                throw LadaError(
                    category: .permissionError,
                    explanation: "Package signature verification failed for \(release.assetName).",
                    exitStatus: sigResult.exitStatus,
                    diagnosticOutput: sigResult.stderr.isEmpty ? sigResult.stdout : sigResult.stderr,
                    suggestedRemediation: "Only signed official packages are accepted.",
                    isRetryable: false
                )
            }
        }

        onProgress("Verified \(release.assetName) (\(release.tagName)). Ready for installation.")
        return pkgURL
    }

    @MainActor
    public func openNativeMacOSInstaller(for pkgURL: URL) {
        NSWorkspace.shared.open(pkgURL)
    }
}
