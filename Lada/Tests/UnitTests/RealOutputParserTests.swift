import XCTest
@testable import Lada

/// Parser tests against real `container` 1.6.1 output, captured on macOS 27 / Apple silicon
/// (client 1.6.1, apiserver 1.5.0 still running from before the upgrade) and sanitized: the user
/// name is replaced with `dev`, and image history is trimmed. Refresh these fixtures when targeting
/// a new upstream version.
final class RealOutputParserTests: XCTestCase {
    func testSystemVersionReportsClientAndServerSeparately() throws {
        let versions = try ContainerOutputParser.parseSystemVersions(jsonString: Fixtures161.systemVersion)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions.first(where: { $0.appName == "container" })?.version, "1.6.1")
        XCTAssertEqual(versions.first(where: { $0.appName == "container-apiserver" })?.version, "1.5.0")
    }

    func testSystemStatus() throws {
        let status = try ContainerOutputParser.parseSystemStatus(jsonString: Fixtures161.systemStatus)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.clientVersion?.version, "1.6.1")
        XCTAssertEqual(status.serverVersion?.version, "1.5.0")
        XCTAssertEqual(status.containersTotal, 0)
        XCTAssertEqual(status.imagesTotal, 2)
    }

    func testImageListWithVariantPlatformAndSize() throws {
        let images = try ContainerOutputParser.parseImages(jsonString: Fixtures161.imageList)
        XCTAssertEqual(images.count, 1)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(image.fullReference, "ghcr.io/apple/containerization/vminit:0.47.0")
        XCTAssertEqual(image.tag, "0.47.0")
        let variant = try XCTUnwrap(image.variants.first)
        XCTAssertEqual(variant.os, "linux")
        XCTAssertEqual(variant.architecture, "arm64")
        XCTAssertEqual(variant.variant, "v8")
        XCTAssertEqual(variant.sizeBytes, 69_254_279)
    }

    func testNetworkList() throws {
        let networks = try ContainerOutputParser.parseNetworks(jsonString: Fixtures161.networkList)
        let network = try XCTUnwrap(networks.first)
        XCTAssertEqual(network.id, "default")
        XCTAssertEqual(network.mode, "nat")
        XCTAssertEqual(network.ipv4Subnet, "192.168.64.0/24")
        XCTAssertEqual(network.ipv4Gateway, "192.168.64.1")
        XCTAssertEqual(network.ipv6Subnet, "fdb7:64c1:dbf3:4208::/64")
        XCTAssertTrue(network.isBuiltin)
    }

    func testVolumeList() throws {
        let volumes = try ContainerOutputParser.parseVolumes(jsonString: Fixtures161.volumeList)
        XCTAssertEqual(volumes.map(\.id), ["nginx-html", "postgres-data"])
        XCTAssertEqual(volumes.first?.format, "ext4")
        XCTAssertEqual(volumes.first?.sizeInBytes, 549_755_813_888)
        XCTAssertTrue(volumes.first?.sourcePath.hasSuffix("/volumes/nginx-html/volume.img") == true)
    }

    func testMachineList() throws {
        let machines = try ContainerOutputParser.parseMachines(jsonString: Fixtures161.machineList)
        let machine = try XCTUnwrap(machines.first)
        XCTAssertEqual(machine.id, "testmachine01")
        XCTAssertEqual(machine.status, .running)
        XCTAssertTrue(machine.isDefault)
        XCTAssertEqual(machine.ipAddress, "192.168.64.28")
        XCTAssertEqual(machine.cpus, 4)
        XCTAssertEqual(machine.memoryBytes, 8_589_934_592)
        XCTAssertEqual(machine.diskSizeBytes, 1_169_408_000)
    }

    func testStats() throws {
        let stats = try ContainerOutputParser.parseContainerStats(jsonString: Fixtures161.stats)
        let s = try XCTUnwrap(stats.first)
        XCTAssertEqual(s.id, "testmachine01-f1fd0a")
        XCTAssertEqual(s.cpuUsageUsec, 7_968)
        XCTAssertEqual(s.memoryUsageBytes, 6_148_096)
        XCTAssertEqual(s.memoryLimitBytes, 8_589_934_592)
        XCTAssertEqual(s.networkRxBytes, 140_043_553)
        XCTAssertEqual(s.numProcesses, 7)
    }

    func testSystemDiskUsage() throws {
        let df = try ContainerOutputParser.parseDiskUsage(jsonString: Fixtures161.systemDF)
        XCTAssertEqual(df.containers.active, 1)
        XCTAssertEqual(df.images.total, 2)
        XCTAssertEqual(df.images.reclaimable, 1_776_570_368)
        XCTAssertEqual(df.volumes.sizeInBytes, 187_817_984)
    }

    func testSystemProperties() throws {
        let props = try ContainerOutputParser.parseSystemProperties(jsonString: Fixtures161.systemProperties)
        XCTAssertEqual(props.build.cpus, 2)
        XCTAssertEqual(props.build.memory, "2048mb")
        XCTAssertEqual(props.build.image, "ghcr.io/apple/container-builder-shim/builder:0.13.2")
        XCTAssertEqual(props.container.cpus, 4)
        XCTAssertEqual(props.container.memory, "1gb")
        XCTAssertEqual(props.registry.domain, "docker.io")
        XCTAssertEqual(props.vminit.image, "ghcr.io/apple/containerization/vminit:0.53.0")
        XCTAssertNotNil(props.kernel.binaryPath)
        XCTAssertEqual(props.machine.cpus, 9)
        XCTAssertEqual(props.machine.memory, "32gb")
        XCTAssertEqual(props.machine.memoryGB, 32)
        XCTAssertEqual(props.machine.homeMount, .rw)
        XCTAssertEqual(props.machine.virtualization, false)
    }

    func testMemorySpecParsingAndMissingMachineDefaults() throws {
        XCTAssertEqual(SystemProperties.bytes(fromMemorySpec: "1gb"), 1_073_741_824)
        XCTAssertEqual(SystemProperties.bytes(fromMemorySpec: "2048mb"), 2_147_483_648)
        XCTAssertEqual(SystemProperties.bytes(fromMemorySpec: "512M"), 536_870_912)
        XCTAssertNil(SystemProperties.bytes(fromMemorySpec: "lots"))
        // Older runtimes have no `machine` section: nothing is invented.
        let props = try ContainerOutputParser.parseSystemProperties(jsonString: #"{"container":{"cpus":4,"memory":"1gb"}}"#)
        XCTAssertEqual(props.machine, SystemProperties.MachineDefaults())
        XCTAssertNil(props.machine.memoryGB)
    }

    func testInspectOfRunningContainer() throws {
        let containers = try ContainerOutputParser.parseContainers(jsonString: Fixtures161.machineBackedContainerInspect)
        let c = try XCTUnwrap(containers.first)
        XCTAssertEqual(c.id, "testmachine01-f1fd0a")
        XCTAssertEqual(c.state, .running)
        XCTAssertEqual(c.imageReference, "docker.io/library/alpine:latest")
        XCTAssertEqual(c.configuration.cpus, 4)
        XCTAssertEqual(c.configuration.memoryInBytes, 8_589_934_592)
        XCTAssertEqual(c.configuration.mounts.count, 3)
        XCTAssertEqual(c.configuration.labels["com.apple.container.plugin"], "machine")
        XCTAssertTrue(c.configuration.sshForwarding)
        XCTAssertEqual(c.primaryIPv4, "192.168.64.28")
        XCTAssertEqual(c.networks.first?.macAddress, "f6:ee:47:dc:b4:d6")
    }

    func testEmptyListsFromIdleRuntime() throws {
        XCTAssertTrue(try ContainerOutputParser.parseContainers(jsonString: "[]").isEmpty)
        XCTAssertTrue(try ContainerOutputParser.parseRegistries(jsonString: "[]").isEmpty)
        XCTAssertFalse(try ContainerOutputParser.parseBuilderStatus(jsonString: "[]").isRunning)
    }
}

private enum Fixtures161 {
    static let systemVersion = #"[{"appName":"container","buildType":"release","commit":"aa8d76b44a834eee3ebf6a0bc577e376f65f6361","version":"1.6.1"},{"appName":"container-apiserver","buildType":"release","commit":"d265d669ecae041bf338cb3b39c4118316d138f0","version":"1.5.0"}]"#
    static let systemStatus = #"{"client":{"appName":"container","build":"release","commit":"aa8d76b44a834eee3ebf6a0bc577e376f65f6361","version":"1.6.1"},"host":{"architecture":"arm64","cpus":18,"operatingSystem":"Version 27.0 (Build 26A428)"},"paths":{"appRoot":"/Users/dev/Library/Application Support/com.apple.container/","installRoot":"/usr/local/"},"resources":{"containersRunning":0,"containersTotal":0,"images":2},"server":{"appName":"container-apiserver","build":"release","commit":"d265d669ecae041bf338cb3b39c4118316d138f0","version":"1.5.0"},"status":"running"}"#
    static let imageList = #"[{"configuration":{"creationDate":"1970-01-01T00:00:00Z","descriptor":{"digest":"sha256:4c1836052eafcbc944c403fb23ded06562962d2402c9dcc651495a32300614df","mediaType":"application/vnd.oci.image.index.v1+json","size":306},"name":"ghcr.io/apple/containerization/vminit:0.47.0"},"id":"4c1836052eafcbc944c403fb23ded06562962d2402c9dcc651495a32300614df","variants":[{"config":{"architecture":"arm64","config":{"Labels":{"org.opencontainers.image.source":"https://github.com/apple/containerization"}},"os":"linux","rootfs":{"diff_ids":["sha256:288a5de3805fef8beec785de9bd9f57857c26d04ac96b562a28cbcb352814b19"],"type":"layers"},"history":[]},"digest":"sha256:c5c20071df2a9f249f82c9c2940539bd568360540559921a29f9f8b78df67ade","platform":{"architecture":"arm64","os":"linux","variant":"v8"},"size":69254279}]}]"#
    static let networkList = #"[{"configuration":{"creationDate":"2026-10-16T09:53:07Z","labels":{"com.apple.container.resource.role":"builtin"},"mode":"nat","name":"default","options":{},"plugin":"container-network-vmnet"},"id":"default","status":{"ipv4Gateway":"192.168.64.1","ipv4Subnet":"192.168.64.0/24","ipv6Subnet":"fdb7:64c1:dbf3:4208::/64"}}]"#
    static let volumeList = #"[{"configuration":{"creationDate":"2026-10-16T10:35:13Z","driver":"local","format":"ext4","labels":{},"name":"nginx-html","options":{},"sizeInBytes":549755813888,"source":"/Users/dev/Library/Application Support/com.apple.container/volumes/nginx-html/volume.img"},"id":"nginx-html"},{"configuration":{"creationDate":"2026-10-16T11:31:31Z","driver":"local","format":"ext4","labels":{},"name":"postgres-data","options":{},"sizeInBytes":549755813888,"source":"/Users/dev/Library/Application Support/com.apple.container/volumes/postgres-data/volume.img"},"id":"postgres-data"}]"#
    static let machineList = #"[{"status":"running","ipAddress":"192.168.64.28","memory":8589934592,"id":"testmachine01","default":true,"diskSize":1169408000,"createdDate":"2026-10-16T11:34:37Z","cpus":4}]"#
    static let stats = #"[{"blockReadBytes":4755456,"blockWriteBytes":0,"cpuUsageUsec":7968,"id":"testmachine01-f1fd0a","memoryLimitBytes":8589934592,"memoryUsageBytes":6148096,"networkRxBytes":140043553,"networkTxBytes":602,"numProcesses":7}]"#
    static let systemDF = #"{"containers":{"active":1,"reclaimable":0,"sizeInBytes":219484160,"total":1},"images":{"active":0,"reclaimable":1776570368,"sizeInBytes":1776570368,"total":2},"volumes":{"active":0,"reclaimable":187817984,"sizeInBytes":187817984,"total":2}}"#
    static let systemProperties = #"{"build":{"cpus":2,"image":"ghcr.io/apple/container-builder-shim/builder:0.13.2","memory":"2048mb","rosetta":true},"container":{"cpus":4,"memory":"1gb"},"dns":{},"kernel":{"binaryPath":"opt/kata/share/kata-containers/vmlinux-6.18.35-197-debug","digest":"sha256:8736c054d9223974735394f822000823baef509e1c33405ec798240fa9b6e4b5","url":"https://github.com/kata-containers/kata-containers/releases/download/3.32.0/kata-static-3.32.0-arm64.tar.zst"},"machine":{"cpus":9,"homeMount":"rw","memory":"32gb","virtualization":false},"network":{},"registry":{"domain":"docker.io"},"vminit":{"image":"ghcr.io/apple/containerization/vminit:0.53.0"}}"#
    static let machineBackedContainerInspect = #"[{"configuration":{"capAdd":["ALL"],"capDrop":[],"creationDate":"2026-10-16T11:35:05Z","dns":{"domain":"machine","nameservers":[],"options":[],"searchDomains":["machine"]},"id":"testmachine01-f1fd0a","image":{"descriptor":{"digest":"sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6","mediaType":"application/vnd.oci.image.index.v1+json","size":9218},"reference":"docker.io/library/alpine:latest"},"initProcess":{"arguments":[],"environment":["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin","CONTAINER_MACHINE_ID=testmachine01","CONTAINER_USER=dev","CONTAINER_HOME=/home/dev","CONTAINER_UID=501","CONTAINER_GID=20"],"executable":"/sbin.machine/init","rlimits":[],"supplementalGroups":[],"terminal":true,"user":{"id":{"gid":0,"uid":0}},"workingDirectory":"/"},"labels":{"com.apple.container.plugin":"machine"},"maskedPaths":[],"mounts":[{"destination":"/sbin.machine","options":["ro"],"source":"/Users/dev/Library/Application Support/com.apple.container/plugin-state/machine-apiserver/machines/testmachine01/sbin.machine","type":{"virtiofs":{}}},{"destination":"/etc/.machine.initialized","options":["rw"],"source":"/Users/dev/Library/Application Support/com.apple.container/plugin-state/machine-apiserver/machines/testmachine01/machine.initialized","type":{"virtiofs":{}}},{"destination":"/Users/dev","options":["rw"],"source":"/Users/dev","type":{"virtiofs":{}}}],"networks":[{"network":"default","options":{"hostname":"testmachine01.machine."}}],"platform":{"architecture":"arm64","os":"linux"},"publishedPorts":[],"publishedSockets":[],"readOnly":false,"readonlyPaths":[],"resources":{"cpuOverhead":0,"cpus":4,"memoryInBytes":8589934592},"rosetta":false,"runtimeHandler":"container-runtime-linux","ssh":true,"sysctls":{},"useInit":false,"virtualization":false},"id":"testmachine01-f1fd0a","status":{"networks":[{"hostname":"testmachine01.machine.","ipv4Address":"192.168.64.28/24","ipv4Gateway":"192.168.64.1","ipv6Address":"fdb7:64c1:dbf3:4208:f4ee:47ff:fedc:b4d6/64","macAddress":"f6:ee:47:dc:b4:d6","network":"default","variant":"reserved"}],"startedDate":"2026-10-16T11:35:05Z","state":"running"}}]"#
}
