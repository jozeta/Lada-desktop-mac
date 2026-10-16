import XCTest
@testable import Lada

final class CLIArgumentBuilderTests: XCTestCase {
    func testContainerCreateRequestFullCLIArguments() {
        var req = ContainerCreateRequest(
            name: "api-gateway",
            imageReference: "ghcr.io/apple/swift:6.0-slim"
        )
        req.entrypointOverride = "/bin/sh"
        req.commandArguments = ["-c", "swift --version"]
        req.workingDirectory = "/workspace"
        req.userSpec = "1000:1000"
        req.allocateTTY = true
        req.interactive = true
        req.removeWhenStopped = true
        req.readOnlyRootfs = true
        req.sshAgentForwarding = true
        req.enableRosetta = true
        req.exposeVirtualization = true
        req.platform = "linux/amd64"
        req.cpus = 4
        req.memoryMB = 4096
        req.networkName = "backend-net"
        req.macAddress = "02:42:ac:11:00:02"
        req.dnsNameservers = ["1.1.1.1", "8.8.8.8"]
        req.dnsSearchDomains = ["corp.local"]
        req.dnsOptions = ["ndots:2"]
        req.publishedPorts = [
            PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 8080, proto: "tcp"),
            PortMapping(hostAddress: "", hostPort: 5353, containerPort: 53, proto: "udp")
        ]
        req.publishedSockets = [
            SocketMapping(hostPath: "/tmp/host.sock", containerPath: "/var/run/app.sock")
        ]
        req.mounts = [
            MountAttachment(kind: .volume, source: "pg-data", destination: "/var/lib/postgresql/data", readOnly: false, volumeName: "pg-data"),
            MountAttachment(kind: .bind, source: "/Users/dev/project", destination: "/workspace", readOnly: true),
            MountAttachment(kind: .tmpfs, source: "", destination: "/tmp/scratch", readOnly: false)
        ]
        req.environmentVariables = [
            KeyValueEntry(key: "PORT", value: "8080"),
            KeyValueEntry(key: "API_SECRET", value: "s3cr3t-token", isSecret: true)
        ]
        req.envFilePath = "/Users/dev/.env"
        req.labels = [
            KeyValueEntry(key: "com.example.env", value: "staging")
        ]
        req.ulimits = ["nofile=65535:65535"]
        req.capAdd = ["NET_ADMIN"]
        req.capDrop = ["ALL"]
        req.startImmediately = true

        let args = req.buildCLIArguments()

        XCTAssertEqual(args.first, "run")
        XCTAssertTrue(args.contains("-d"))
        XCTAssertTrue(args.contains("--name"))
        XCTAssertTrue(args.contains("api-gateway"))
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("--rm"))
        XCTAssertTrue(args.contains("--read-only"))
        XCTAssertTrue(args.contains("--ssh"))
        XCTAssertTrue(args.contains("--rosetta"))
        XCTAssertTrue(args.contains("--virtualization"))
        XCTAssertTrue(args.contains("--platform"))
        XCTAssertTrue(args.contains("linux/amd64"))
        XCTAssertTrue(args.contains("--cpus"))
        XCTAssertTrue(args.contains("4"))
        XCTAssertTrue(args.contains("--memory"))
        XCTAssertTrue(args.contains("4096M"))
        XCTAssertTrue(args.contains("backend-net,mac=02:42:ac:11:00:02"))
        XCTAssertTrue(args.contains("127.0.0.1:8080:8080/tcp"))
        XCTAssertTrue(args.contains("5353:53/udp"))
        XCTAssertTrue(args.contains("/tmp/host.sock:/var/run/app.sock"))
        XCTAssertTrue(args.contains("type=volume,source=pg-data,target=/var/lib/postgresql/data"))
        XCTAssertTrue(args.contains("type=bind,source=/Users/dev/project,target=/workspace,readonly"))
        XCTAssertTrue(args.contains("type=tmpfs,target=/tmp/scratch"))
        XCTAssertTrue(args.contains("PORT=8080"))
        XCTAssertTrue(args.contains("API_SECRET=s3cr3t-token"))
        XCTAssertTrue(args.contains("com.example.env=staging"))
        XCTAssertTrue(args.contains("nofile=65535:65535"))
        XCTAssertTrue(args.contains("NET_ADMIN"))
        XCTAssertTrue(args.contains("ALL"))

        // Verify image and command are at the end
        let suffix = Array(args.suffix(3))
        XCTAssertEqual(suffix, ["ghcr.io/apple/swift:6.0-slim", "-c", "swift --version"])
    }

    func testContainerCreateWithoutImmediateStartUsesCreateSubcommand() {
        var req = ContainerCreateRequest(name: "offline-worker", imageReference: "alpine:3.20")
        req.startImmediately = false
        let args = req.buildCLIArguments()
        XCTAssertEqual(args.first, "create")
        XCTAssertFalse(args.contains("-d"))
    }

    func testDuplicateContainerRequestCopiesConfigurationWithCopySuffix() {
        let cfg = ContainerConfigurationModel(
            executable: "redis-server",
            arguments: ["--appendonly", "yes"],
            environment: ["REDIS_PASSWORD=secret123", "PORT=6379"],
            workingDirectory: "/data",
            terminal: true,
            user: "redis",
            cpus: 2,
            memoryInBytes: 2 * 1024 * 1024 * 1024,
            readOnlyRootfs: true,
            rosetta: false,
            virtualization: false,
            sshForwarding: false,
            labels: ["app": "cache"],
            mounts: [MountAttachment(kind: .volume, source: "redis-data", destination: "/data", readOnly: false, volumeName: "redis-data")],
            publishedPorts: [PortMapping(hostAddress: "127.0.0.1", hostPort: 6379, containerPort: 6379, proto: "tcp")],
            publishedSockets: [],
            configuredNetworks: ["default"]
        )
        let original = ContainerModel(
            id: "redis-cache",
            imageReference: "redis:7-alpine",
            imageDigest: "sha256:1234",
            state: .running,
            configuration: cfg,
            networks: [
                ContainerNetworkAttachment(
                    network: "default",
                    hostname: "redis-cache",
                    ipv4Address: "192.168.64.2/24",
                    ipv4Gateway: "192.168.64.1"
                )
            ]
        )

        let duplicated = ContainerCreateRequest.duplicating(original)
        XCTAssertEqual(duplicated.name, "redis-cache-copy")
        XCTAssertEqual(duplicated.imageReference, "redis:7-alpine")
        XCTAssertEqual(duplicated.cpus, 2)
        XCTAssertEqual(duplicated.memoryMB, 2048)
        XCTAssertEqual(duplicated.publishedPorts.count, 1)
        XCTAssertEqual(duplicated.mounts.count, 1)
        XCTAssertTrue(duplicated.readOnlyRootfs)
        XCTAssertTrue(duplicated.allocateTTY)
        XCTAssertEqual(duplicated.environmentVariables.first(where: { $0.key == "REDIS_PASSWORD" })?.isSecret, true)
    }

    func testImagePullAndBuildArguments() {
        let pullReq = ImagePullRequest(reference: "ubuntu:24.04", platform: "linux/arm64", scheme: "http")
        XCTAssertEqual(pullReq.buildCLIArguments(), [
            "image", "pull", "--progress", "plain", "--scheme", "http", "--platform", "linux/arm64", "ubuntu:24.04"
        ])

        let buildReq = ImageBuildRequest(
            contextDirectory: "/Users/dev/app",
            containerfilePath: "/Users/dev/app/Containerfile",
            tags: ["my-app:latest", "my-app:1.0"],
            buildArgs: [KeyValueEntry(key: "SWIFT_VERSION", value: "6.0")],
            labels: [KeyValueEntry(key: "org.opencontainers.image.vendor", value: "Acme")],
            targetStage: "production",
            platform: "linux/arm64",
            cpus: 4,
            memoryMB: 4096,
            noCache: true,
            pullLatest: true,
            forwardSSH: true
        )
        let buildArgs = buildReq.buildCLIArguments()
        XCTAssertEqual(buildArgs.prefix(3), ["build", "--progress", "plain"])
        XCTAssertTrue(buildArgs.contains("-f"))
        XCTAssertTrue(buildArgs.contains("my-app:latest"))
        XCTAssertTrue(buildArgs.contains("my-app:1.0"))
        XCTAssertTrue(buildArgs.contains("linux/arm64"))
        XCTAssertTrue(buildArgs.contains("--no-cache"))
        XCTAssertTrue(buildArgs.contains("--pull"))
        XCTAssertTrue(buildArgs.contains("--ssh"))
        XCTAssertEqual(buildArgs.last, "/Users/dev/app")
    }

    func testNetworkVolumeAndMachineCLIArguments() {
        let netReq = NetworkCreateRequest(
            name: "isolated-net",
            ipv4Subnet: "192.168.100.0/24",
            ipv6Subnet: "fd00:100::/64",
            isInternal: true,
            labels: [KeyValueEntry(key: "tier", value: "backend")]
        )
        XCTAssertEqual(netReq.buildCLIArguments(), [
            "network", "create",
            "--internal",
            "--subnet", "192.168.100.0/24",
            "--subnet-v6", "fd00:100::/64",
            "--label", "tier=backend",
            "isolated-net"
        ])

        let volReq = VolumeCreateRequest(
            name: "db-storage",
            sizeSpec: "10G",
            journalMode: .writeback,
            journalSize: "64M",
            labels: [KeyValueEntry(key: "env", value: "dev")]
        )
        XCTAssertEqual(volReq.buildCLIArguments(), [
            "volume", "create",
            "-s", "10G",
            "--opt", "journal=writeback:64M",
            "--label", "env=dev",
            "db-storage"
        ])

        let machineCreate = MachineCreateRequest(
            name: "dev-vm",
            imageReference: "alpine:latest",
            cpus: 6,
            memoryGB: 12,
            homeMount: .ro,
            setDefault: true,
            bootImmediately: true,
            enableVirtualization: true
        )
        XCTAssertEqual(machineCreate.buildCLIArguments(), [
            "machine", "create",
            "--name", "dev-vm",
            "--cpus", "6",
            "--memory", "12G",
            "--home-mount", "ro",
            "--set-default",
            "--virtualization",
            "alpine:latest"
        ])

        let machineUpdate = MachineUpdateRequest(
            name: "dev-vm",
            cpus: 8,
            memoryGB: 16,
            homeMount: .rw,
            enableVirtualization: true,
            customKernelPath: "/opt/vmlinux"
        )
        XCTAssertEqual(machineUpdate.buildCLIArguments(), [
            "machine", "set", "--name", "dev-vm",
            "cpus=8",
            "memory=16G",
            "home-mount=rw",
            "virtualization=true",
            "kernel=/opt/vmlinux"
        ])
    }
}
