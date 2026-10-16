import XCTest
@testable import Lada

final class RuntimeCapabilitiesAndHealthTests: XCTestCase {
    func testCapabilitiesMatrixForAppleSiliconMacOS26AndM3Plus() {
        let m4Host = HostEnvironmentInfo(
            cpuArchitecture: "arm64",
            cpuBrandString: "Apple M4 Max",
            isAppleSilicon: true,
            supportsNestedVirtualizationChip: true,
            macOSMajorVersion: 26,
            macOSMinorVersion: 1,
            macOSPatchVersion: 0,
            macOSVersionString: "Version 26.1 (Build 25B78)",
            macOSBuildString: "25B78",
            physicalMemoryBytes: 64 * 1024 * 1024 * 1024,
            processorCount: 16,
            availableDiskSpaceBytes: 250 * 1024 * 1024 * 1024,
            hypervisorFrameworkAvailable: true
        )

        let caps = RuntimeCapabilities(
            detectedVersion: SemanticVersion(major: 1, minor: 5, patch: 0),
            hostEnvironment: m4Host
        )
        XCTAssertEqual(caps.containerLifecycle, .supported)
        XCTAssertEqual(caps.nestedVirtualization, .supported)
        XCTAssertEqual(caps.networkManagement, .supported)
        XCTAssertEqual(caps.containerMachines, .supported)
        // Restart policies are explicitly unsupported by upstream apple/container 1.5.0
        if case .unsupported(let reason) = caps.containerRestartPolicies {
            XCTAssertTrue(reason.contains("does not implement"))
        } else {
            XCTFail("Expected containerRestartPolicies to be unsupported")
        }
    }

    func testCapabilitiesMatrixMarksIntelUnavailable() {
        let intelHost = HostEnvironmentInfo(
            cpuArchitecture: "x86_64",
            cpuBrandString: "Intel Core i9",
            isAppleSilicon: false,
            supportsNestedVirtualizationChip: false,
            macOSMajorVersion: 15,
            macOSMinorVersion: 4,
            macOSPatchVersion: 0,
            macOSVersionString: "Version 15.4",
            macOSBuildString: "24E21",
            physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
            processorCount: 8,
            availableDiskSpaceBytes: 80 * 1024 * 1024 * 1024,
            hypervisorFrameworkAvailable: true
        )

        let caps = RuntimeCapabilities(detectedVersion: nil, hostEnvironment: intelHost)
        if case .unsupported = caps.containerLifecycle {
            // Expected
        } else {
            XCTFail("Expected Intel macOS 15 to mark containerLifecycle unsupported")
        }
    }

    func testHealthServicePrerequisiteEvaluationAndUntrustedInstallerOriginRejection() async throws {
        let healthService = RuntimeHealthService()
        let host = HostEnvironmentInfo(
            cpuArchitecture: "arm64",
            cpuBrandString: "Apple M4 Pro",
            isAppleSilicon: true,
            supportsNestedVirtualizationChip: true,
            macOSMajorVersion: 26,
            macOSMinorVersion: 0,
            macOSPatchVersion: 0,
            macOSVersionString: "Version 26.0",
            macOSBuildString: "25A354",
            physicalMemoryBytes: 32 * 1024 * 1024 * 1024,
            processorCount: 14,
            availableDiskSpaceBytes: 120 * 1024 * 1024 * 1024,
            hypervisorFrameworkAvailable: true
        )
        let readyInstall = RuntimeInstallation(
            isInstalled: true,
            executablePath: "/usr/local/bin/container",
            installRootPath: "/usr/local",
            appRootPath: "/Users/dev/Library/Application Support/com.apple.container",
            cliVersion: SemanticVersion(major: 1, minor: 5, patch: 0),
            rawVersionString: "container version 1.5.0",
            helperPluginsPresent: true,
            defaultKernelInstalled: true,
            kernelBinaryPath: "/Users/dev/Library/Application Support/com.apple.container/kernels/default.kernel"
        )
        let runningStatus = RuntimeSystemStatus(
            state: .running,
            clientVersion: RuntimeComponentVersion(appName: "container", version: "1.5.0", buildType: "release", commit: "a1b2c3d"),
            serverVersion: RuntimeComponentVersion(appName: "container-apiserver", version: "1.5.0", buildType: "release", commit: "a1b2c3d"),
            containersTotal: 2,
            containersRunning: 1
        )

        let items = healthService.evaluatePrerequisites(
            host: host,
            installation: readyInstall,
            systemStatus: runningStatus
        )
        XCTAssertGreaterThanOrEqual(items.count, 9)
        XCTAssertTrue(items.filter(\.isRequired).allSatisfy { $0.status == .ready })

        // Verify untrusted mirror URL is rejected before downloading
        let untrustedRelease = ReleaseAssetInfo(
            tagName: "1.5.0",
            releaseName: "container 1.5.0",
            publishedAt: "2026-03-01T00:00:00Z",
            assetName: "container-1.5.0-installer-signed.pkg",
            downloadURL: URL(string: "https://untrusted-mirror.example.com/container.pkg")!,
            sizeBytes: 1024,
            sha256Digest: nil,
            releasePageURL: URL(string: "https://github.com/apple/container/releases/tag/1.5.0")!
        )

        do {
            _ = try await healthService.downloadAndVerifyInstaller(release: untrustedRelease, onProgress: { _ in })
            XCTFail("Expected untrusted origin error")
        } catch let error as LadaError {
            XCTAssertEqual(error.category, .permissionError)
            XCTAssertTrue(error.explanation.contains("untrusted origin"))
        }
    }
}
