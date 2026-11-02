import XCTest
@testable import Lada

final class ResourceGraphTests: XCTestCase {
    private func sampleGraph() -> ResourceGraph {
        let web = ContainerModel(
            id: "web", imageReference: "docker.io/library/nginx:1.27-alpine", state: .running,
            configuration: ContainerConfigurationModel(
                labels: ["com.lada.compose.project": "shop"],
                mounts: [MountAttachment(kind: .volume, source: "site", destination: "/usr/share/nginx/html", readOnly: false, volumeName: "site"),
                         MountAttachment(kind: .bind, source: "/Users/me/conf", destination: "/etc/nginx/conf.d", readOnly: true)],
                publishedPorts: [PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")]
            ),
            networks: [ContainerNetworkAttachment(network: "default", hostname: "web", ipv4Address: "192.168.64.5/24", ipv4Gateway: "192.168.64.1")]
        )
        let old = ContainerModel(id: "old-web", imageReference: "docker.io/library/nginx:1.25", state: .stopped)
        return ResourceGraph.build(
            containers: [web, old],
            images: [ImageModel(fullReference: "docker.io/library/nginx:1.27-alpine", repository: "nginx", tag: "1.27-alpine", registryOrigin: "docker.io", digest: "sha256:abc")],
            networks: [NetworkModel(id: "default", ipv4Subnet: "192.168.64.0/24", ipv4Gateway: "192.168.64.1")],
            volumes: [VolumeModel(id: "site", sourcePath: "/x/volumes/site")],
            machines: [MachineModel(id: "dev", status: .running, ipAddress: "192.168.64.9", imageReference: "docker.io/library/alpine:3.22")],
            registries: [RegistryModel(hostname: "docker.io", username: "me", isAuthenticated: true)]
        )
    }

    private func has(_ g: ResourceGraph, _ from: String, _ to: String, _ r: ResourceGraph.Relation) -> Bool {
        g.edges.contains { $0.from == from && $0.to == to && $0.relation == r }
    }

    func testRelationships() {
        let g = sampleGraph()
        XCTAssertTrue(has(g, "Container:web", "Image:docker.io/library/nginx:1.27-alpine", .runs))
        XCTAssertTrue(has(g, "Container:web", "Stack:shop", .memberOf))
        XCTAssertTrue(has(g, "Container:web", "Network:default", .attachedTo))
        XCTAssertTrue(has(g, "Container:web", "IP Address:192.168.64.5", .hasAddress))
        XCTAssertTrue(has(g, "IP Address:192.168.64.5", "Subnet:192.168.64.0/24", .inSubnet))
        XCTAssertTrue(has(g, "Network:default", "Subnet:192.168.64.0/24", .inSubnet))
        XCTAssertTrue(has(g, "Container:web", "Volume:site", .mounts))
        XCTAssertTrue(has(g, "Container:web", "Mac Folder:/Users/me/conf", .mounts))
        XCTAssertTrue(has(g, "Container:web", "Port:127.0.0.1:8080/tcp", .publishes))
        XCTAssertTrue(has(g, "Image:docker.io/library/nginx:1.27-alpine", "Registry:docker.io", .pulledFrom))
        XCTAssertTrue(has(g, "Machine:dev", "IP Address:192.168.64.9", .hasAddress))
        XCTAssertTrue(has(g, "IP Address:192.168.64.9", "Subnet:192.168.64.0/24", .inSubnet))
    }

    func testSimilarityAndMissingImages() {
        let g = sampleGraph()
        // Same repository, different tags.
        XCTAssertTrue(has(g, "Container:web", "Container:old-web", .similar))
        // Images not on this Mac still appear, marked inactive.
        let missing = g.nodes.first { $0.id == "Image:docker.io/library/nginx:1.25" }
        XCTAssertEqual(missing?.isActive, false)
    }

    func testFilteringDropsEdgesToHiddenKinds() {
        let g = sampleGraph().filtered(to: [.container, .image])
        XCTAssertTrue(g.nodes.allSatisfy { $0.kind == .container || $0.kind == .image })
        XCTAssertTrue(g.edges.allSatisfy { e in g.nodes.contains { $0.id == e.from } && g.nodes.contains { $0.id == e.to } })
    }

    func testEveryLayoutPlacesEveryNodeInsideTheCanvas() {
        let g = sampleGraph()
        let size = CGSize(width: 1200, height: 800)
        for layout in GraphLayout.allCases {
            let positions = layout.positions(for: g, in: size)
            XCTAssertEqual(Set(positions.keys), Set(g.nodes.map(\.id)), layout.rawValue)
            for p in positions.values {
                XCTAssertTrue((0...size.width).contains(p.x) && (0...size.height).contains(p.y), "\(layout.rawValue) placed a node outside")
            }
        }
    }

    func testLayoutsAreDeterministicAndLayeredOrdersByType() {
        let g = sampleGraph()
        let size = CGSize(width: 1200, height: 800)
        XCTAssertEqual(GraphLayout.force.positions(for: g, in: size), GraphLayout.force.positions(for: g, in: size))
        let layered = GraphLayout.layered.positions(for: g, in: size)
        XCTAssertLessThan(layered["Stack:shop"]!.y, layered["Container:web"]!.y)
        XCTAssertLessThan(layered["Container:web"]!.y, layered["Image:docker.io/library/nginx:1.27-alpine"]!.y)
        XCTAssertLessThan(layered["Image:docker.io/library/nginx:1.27-alpine"]!.y, layered["Subnet:192.168.64.0/24"]!.y)
    }

    func testRadialPutsTheFocusInTheMiddle() {
        let g = sampleGraph()
        let p = GraphLayout.radial.positions(for: g, in: CGSize(width: 1000, height: 800), focus: "Container:web")
        XCTAssertEqual(p["Container:web"], CGPoint(x: 500, y: 400))
    }

    func testForceLayoutSeparatesNodes() {
        let p = GraphLayout.force.positions(for: sampleGraph(), in: CGSize(width: 1200, height: 800))
        let points = Array(p.values)
        for i in points.indices {
            for j in points.indices where j > i {
                XCTAssertGreaterThan(hypot(points[i].x - points[j].x, points[i].y - points[j].y), 20)
            }
        }
    }

    func testSubnetMembership() {
        XCTAssertTrue(IPv4.contains(cidr: "192.168.64.0/24", address: "192.168.64.200"))
        XCTAssertFalse(IPv4.contains(cidr: "192.168.64.0/24", address: "192.168.65.1"))
        XCTAssertTrue(IPv4.contains(cidr: "10.0.0.0/8", address: "10.200.3.4"))
        XCTAssertFalse(IPv4.contains(cidr: "nonsense", address: "10.0.0.1"))
    }
}
