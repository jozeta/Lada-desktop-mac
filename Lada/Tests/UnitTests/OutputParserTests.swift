import XCTest
@testable import Lada

final class OutputParserTests: XCTestCase {
    func testParseSystemVersionsAndSystemStatus() throws {
        let versionsJSON = """
        [
          {
            "appName": "container",
            "version": "1.5.0",
            "buildType": "release",
            "commit": "a1b2c3d"
          },
          {
            "appName": "container-apiserver",
            "version": "1.5.0",
            "buildType": "release",
            "commit": "a1b2c3d"
          }
        ]
        """
        let versions = try ContainerOutputParser.parseSystemVersions(jsonString: versionsJSON)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions.first?.version, "1.5.0")

        let statusJSON = """
        {
          "status": "running",
          "client": {"appName": "container", "version": "1.5.0", "build": "release", "commit": "a1b2c3d"},
          "server": {"appName": "container-apiserver", "version": "1.5.0", "build": "release", "commit": "a1b2c3d"},
          "paths": {
            "appRoot": "/Users/dev/Library/Application Support/com.apple.container",
            "installRoot": "/usr/local"
          },
          "resources": {
            "containersTotal": 3,
            "containersRunning": 2,
            "images": 4
          }
        }
        """
        let status = try ContainerOutputParser.parseSystemStatus(jsonString: statusJSON)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.containersTotal, 3)
        XCTAssertEqual(status.containersRunning, 2)
        XCTAssertEqual(status.serverVersion?.version, "1.5.0")
    }

    func testParseContainersAndStats() throws {
        let containersJSON = """
        [
          {
            "configuration": {
              "id": "alpine-shell",
              "image": {
                "reference": "docker.io/library/alpine:3.20",
                "descriptor": {"digest": "sha256:abcdef123456"}
              },
              "initProcess": {
                "executable": "/bin/sh",
                "arguments": ["-l"],
                "environment": ["APP_ENV=production", "SECRET_TOKEN=xyz987"],
                "workingDirectory": "/root",
                "terminal": true
              },
              "resources": {
                "cpus": 2,
                "memoryInBytes": 1073741824
              },
              "publishedPorts": [
                {"hostAddress": "127.0.0.1", "hostPort": 8080, "containerPort": 80, "proto": "tcp", "count": 1}
              ],
              "mounts": [
                {"type": {"volume": {"name": "app-data"}}, "source": "app-data", "destination": "/data", "options": ["rw"]}
              ],
              "labels": {"tier": "web"},
              "rosetta": false,
              "virtualization": false
            },
            "status": {
              "state": "running",
              "startedDate": "2026-03-15T10:00:02Z",
              "networks": [
                {"network": "default", "hostname": "alpine-shell", "ipv4Address": "192.168.64.5/24", "ipv4Gateway": "192.168.64.1", "macAddress": "02:42:ac:11:00:05"}
              ]
            }
          }
        ]
        """

        let containers = try ContainerOutputParser.parseContainers(jsonString: containersJSON)
        XCTAssertEqual(containers.count, 1)
        let first = try XCTUnwrap(containers.first)
        XCTAssertEqual(first.id, "alpine-shell")
        XCTAssertEqual(first.state, .running)
        XCTAssertEqual(first.configuration.cpus, 2)
        XCTAssertEqual(first.configuration.memoryInBytes, 1073741824)
        XCTAssertEqual(first.configuration.publishedPorts.first?.hostPort, 8080)
        XCTAssertEqual(first.primaryIPv4, "192.168.64.5")
        XCTAssertEqual(first.configuration.mounts.first?.volumeName, "app-data")

        let statsJSON = """
        [
          {
            "id": "alpine-shell",
            "cpuUsageUsec": 240000,
            "memoryUsageBytes": 134217728,
            "memoryLimitBytes": 1073741824,
            "networkRxBytes": 20480,
            "networkTxBytes": 10240,
            "blockReadBytes": 4096,
            "blockWriteBytes": 8192,
            "numProcesses": 5
          }
        ]
        """
        let stats = try ContainerOutputParser.parseContainerStats(jsonString: statsJSON)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.first?.numProcesses, 5)
        XCTAssertEqual(stats.first?.memoryPercentage ?? 0, 12.5, accuracy: 0.1)
    }

    func testParseImagesNetworksVolumesMachinesRegistriesAndDiskUsage() throws {
        let imagesJSON = """
        [
          {
            "configuration": {
              "name": "ghcr.io/apple/container-base:1.5",
              "descriptor": {
                "digest": "sha256:1122334455667788",
                "mediaType": "application/vnd.oci.image.index.v1+json"
              }
            },
            "variants": [
              {
                "platform": {"os": "linux", "architecture": "arm64"},
                "digest": "sha256:1122334455667788",
                "size": 157286400
              }
            ]
          }
        ]
        """
        let images = try ContainerOutputParser.parseImages(jsonString: imagesJSON)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.repository, "apple/container-base")
        XCTAssertEqual(images.first?.registryOrigin, "ghcr.io")
        XCTAssertEqual(images.first?.tag, "1.5")
        XCTAssertEqual(images.first?.totalSizeBytes, 157286400)

        let networksJSON = """
        [
          {
            "configuration": {
              "name": "default",
              "mode": "nat",
              "plugin": "container-network-vmnet"
            },
            "status": {
              "ipv4Subnet": "192.168.64.0/24",
              "ipv4Gateway": "192.168.64.1"
            }
          }
        ]
        """
        let networks = try ContainerOutputParser.parseNetworks(jsonString: networksJSON)
        XCTAssertEqual(networks.count, 1)
        XCTAssertEqual(networks.first?.isBuiltin, true)
        XCTAssertEqual(networks.first?.ipv4Subnet, "192.168.64.0/24")

        let volumesJSON = """
        [
          {
            "configuration": {
              "name": "postgres-data",
              "driver": "local",
              "format": "ext4",
              "source": "/Users/test/Library/Application Support/com.apple.container/volumes/postgres-data.ext4",
              "sizeInBytes": 536870912
            }
          }
        ]
        """
        let volumes = try ContainerOutputParser.parseVolumes(jsonString: volumesJSON)
        XCTAssertEqual(volumes.count, 1)
        XCTAssertEqual(volumes.first?.name, "postgres-data")
        XCTAssertEqual(volumes.first?.sizeInBytes, 536870912)

        let machinesJSON = """
        [
          {
            "id": "default",
            "status": "running",
            "default": true,
            "cpus": 4,
            "memory": 8589934592,
            "diskSize": 68719476736,
            "bootConfig": {
              "homeMount": "rw",
              "virtualization": true
            }
          }
        ]
        """
        let machines = try ContainerOutputParser.parseMachines(jsonString: machinesJSON)
        XCTAssertEqual(machines.count, 1)
        XCTAssertEqual(machines.first?.status, .running)
        XCTAssertEqual(machines.first?.virtualizationEnabled, true)

        let dfJSON = """
        {
          "images": {"total": 5, "active": 2, "sizeInBytes": 1073741824, "reclaimable": 536870912},
          "containers": {"total": 3, "active": 1, "sizeInBytes": 268435456, "reclaimable": 134217728},
          "volumes": {"total": 2, "active": 1, "sizeInBytes": 536870912, "reclaimable": 0}
        }
        """
        let df = try ContainerOutputParser.parseDiskUsage(jsonString: dfJSON)
        XCTAssertEqual(df.images.total, 5)
        XCTAssertEqual(df.images.reclaimable, 536870912)
        XCTAssertEqual(df.totalReclaimableBytes, 536870912 + 134217728)
    }

    func testMalformedJSONThrowsError() {
        let malformed = "{not valid json [["
        XCTAssertThrowsError(try ContainerOutputParser.parseContainers(jsonString: malformed))
    }
}
