import Foundation
import CoreGraphics

/// Every resource Låda knows about as nodes, connected by how they relate (a container runs an
/// image, is attached to a network, has an address in a subnet, mounts a volume…) and by
/// similarity (containers built from the same image repository). Pure, so it is unit-tested.
public struct ResourceGraph: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case stack = "Stack"
        case container = "Container"
        case machine = "Machine"
        case image = "Image"
        case network = "Network"
        case ipAddress = "IP Address"
        case subnet = "Subnet"
        case volume = "Volume"
        case hostFolder = "Mac Folder"
        case port = "Port"
        case registry = "Registry"
    }

    public enum Relation: String, CaseIterable, Sendable {
        case memberOf = "member of"
        case runs = "runs"
        case attachedTo = "attached to"
        case hasAddress = "has address"
        case inSubnet = "in subnet"
        case mounts = "mounts"
        case publishes = "publishes"
        case pulledFrom = "pulled from"
        case similar = "same repository"
    }

    public struct Node: Identifiable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let title: String
        public let subtitle: String
        /// Shown in the hover card, in order.
        public let info: [Field]
        public let destination: UniversalSearchResult.Destination?
        public let isActive: Bool
    }

    public struct Field: Equatable, Sendable {
        public let label: String
        public let value: String
    }

    public struct Edge: Identifiable, Equatable, Sendable {
        public var id: String { "\(from)>\(to):\(relation.rawValue)" }
        public let from: String
        public let to: String
        public let relation: Relation
    }

    public var nodes: [Node] = []
    public var edges: [Edge] = []

    public func neighbors(of id: String) -> Set<String> {
        Set(edges.compactMap { $0.from == id ? $0.to : ($0.to == id ? $0.from : nil) })
    }

    public func degree(of id: String) -> Int {
        edges.filter { $0.from == id || $0.to == id }.count
    }

    /// Neighbours of every node, built in one pass (layouts use this instead of scanning edges
    /// per node).
    public func adjacencyMap() -> [String: Set<String>] {
        var adj: [String: Set<String>] = [:]
        for e in edges {
            adj[e.from, default: []].insert(e.to)
            adj[e.to, default: []].insert(e.from)
        }
        return adj
    }

    /// Only nodes of `kinds`, and edges between them.
    public func filtered(to kinds: Set<Kind>) -> ResourceGraph {
        let kept = nodes.filter { kinds.contains($0.kind) }
        let ids = Set(kept.map(\.id))
        return ResourceGraph(nodes: kept, edges: edges.filter { ids.contains($0.from) && ids.contains($0.to) })
    }
}

// MARK: - Building

public extension ResourceGraph {
    static func build(
        containers: [ContainerModel],
        images: [ImageModel],
        networks: [NetworkModel],
        volumes: [VolumeModel],
        machines: [MachineModel],
        registries: [RegistryModel]
    ) -> ResourceGraph {
        var nodes: [String: Node] = [:]
        var order: [String] = []
        var edges: [Edge] = []
        var edgeIDs = Set<String>()

        func node(_ kind: Kind, _ key: String, title: String, subtitle: String = "", info: [Field] = [],
                  destination: UniversalSearchResult.Destination? = nil, active: Bool = true) -> String {
            let id = "\(kind.rawValue):\(key)"
            if nodes[id] == nil {
                nodes[id] = Node(id: id, kind: kind, title: title, subtitle: subtitle, info: info, destination: destination, isActive: active)
                order.append(id)
            }
            return id
        }
        func link(_ a: String, _ b: String, _ relation: Relation) {
            let edge = Edge(from: a, to: b, relation: relation)
            if a != b, edgeIDs.insert(edge.id).inserted { edges.append(edge) }
        }
        func short(_ ref: String) -> String { DockerfileCompletionEngine.shortImage(ref) }

        // Images first, so containers can link to the local image they run.
        var imageByRef: [String: String] = [:]
        for image in images {
            let id = node(.image, image.fullReference, title: short(image.fullReference), subtitle: image.registryOrigin,
                          info: [Field(label: "Reference", value: image.fullReference),
                                 Field(label: "Digest", value: image.digest.isEmpty ? "—" : String(image.digest.prefix(23))),
                                 Field(label: "Platforms", value: image.variants.map { "\($0.os)/\($0.architecture)" }.joined(separator: ", ")),
                                 Field(label: "Created", value: image.creationDate.formatted(date: .abbreviated, time: .shortened))],
                          destination: .image(image.id))
            imageByRef[image.fullReference] = id
            imageByRef[short(image.fullReference)] = id
            if let registry = registries.first(where: { $0.hostname == image.registryOrigin }) {
                let rid = node(.registry, registry.hostname, title: registry.hostname, subtitle: registry.isAuthenticated ? "signed in" : "signed out",
                               info: [Field(label: "User", value: registry.username)], destination: .registry)
                link(id, rid, .pulledFrom)
            }
        }

        var subnetByNetwork: [String: String] = [:]
        var subnets: [(cidr: String, id: String)] = []
        for net in networks {
            let id = node(.network, net.name, title: net.name, subtitle: net.mode,
                          info: [Field(label: "Mode", value: net.mode),
                                 Field(label: "IPv4 subnet", value: net.ipv4Subnet),
                                 Field(label: "Gateway", value: net.ipv4Gateway),
                                 Field(label: "IPv6 subnet", value: net.ipv6Subnet ?? "—"),
                                 Field(label: "Built in", value: net.isBuiltin ? "Yes" : "No")],
                          destination: .network(net.id))
            if !net.ipv4Subnet.isEmpty {
                let sid = node(.subnet, net.ipv4Subnet, title: net.ipv4Subnet, subtitle: "IPv4",
                               info: [Field(label: "Network", value: net.name), Field(label: "Gateway", value: net.ipv4Gateway)])
                link(id, sid, .inSubnet)
                subnetByNetwork[net.name] = sid
                subnets.append((net.ipv4Subnet, sid))
            }
        }

        for volume in volumes {
            _ = node(.volume, volume.name, title: volume.name, subtitle: volume.format,
                     info: [Field(label: "Path", value: volume.sourcePath),
                            Field(label: "Format", value: volume.format),
                            Field(label: "Size", value: volume.sizeInBytes.map { NordicFormat.bytes(fromByteCount: Int64($0), countStyle: .file) } ?? "—")],
                     destination: .volume(volume.id))
        }

        func addressNode(_ address: String, owner: String) -> String {
            let ip = address.split(separator: "/").first.map(String.init) ?? address
            let id = node(.ipAddress, ip, title: ip, subtitle: owner, info: [Field(label: "Assigned to", value: owner), Field(label: "CIDR", value: address)])
            if let subnet = subnets.first(where: { IPv4.contains(cidr: $0.cidr, address: ip) }) {
                link(id, subnet.id, .inSubnet)
            }
            return id
        }

        for c in containers {
            let running = c.state == .running
            let cid = node(.container, c.id, title: c.id, subtitle: c.state.displayTitle,
                           info: [Field(label: "Image", value: c.imageReference),
                                  Field(label: "State", value: c.state.displayTitle),
                                  Field(label: "Resources", value: "\(c.configuration.cpus) vCPU · \(NordicFormat.bytes(fromByteCount: Int64(c.configuration.memoryInBytes), countStyle: .memory))"),
                                  Field(label: "Ports", value: c.configuration.publishedPorts.map { "\($0.hostPort)→\($0.containerPort)/\($0.proto)" }.joined(separator: ", ").ifEmpty("—")),
                                  Field(label: "Networks", value: c.networks.map(\.network).joined(separator: ", ").ifEmpty("—")),
                                  Field(label: "Mounts", value: "\(c.configuration.mounts.count)")],
                           destination: .container(c.id), active: running)
            if let project = c.composeProject {
                let sid = node(.stack, project, title: project, subtitle: "stack", info: [Field(label: "Project", value: project)], destination: .stack(project))
                link(cid, sid, .memberOf)
            }
            let imageID = imageByRef[c.imageReference] ?? imageByRef[short(c.imageReference)]
                ?? node(.image, c.imageReference, title: short(c.imageReference), subtitle: "not on this Mac",
                        info: [Field(label: "Reference", value: c.imageReference)], active: false)
            link(cid, imageID, .runs)
            for attachment in c.networks {
                let nid = node(.network, attachment.network, title: attachment.network)
                link(cid, nid, .attachedTo)
                if !attachment.ipv4Address.isEmpty {
                    link(cid, addressNode(attachment.ipv4Address, owner: c.id), .hasAddress)
                }
            }
            for mount in c.configuration.mounts {
                switch mount.kind {
                case .volume:
                    let name = mount.volumeName ?? mount.source
                    link(cid, node(.volume, name, title: name, destination: .volume(name)), .mounts)
                case .bind:
                    link(cid, node(.hostFolder, mount.source, title: (mount.source as NSString).lastPathComponent, subtitle: mount.source,
                                   info: [Field(label: "Path on Mac", value: mount.source),
                                          Field(label: "In container", value: mount.destination),
                                          Field(label: "Access", value: mount.readOnly ? "read-only" : "read-write")]), .mounts)
                default:
                    break
                }
            }
            for port in c.configuration.publishedPorts {
                let pid = node(.port, "\(port.hostAddress):\(port.hostPort)/\(port.proto)", title: "\(port.hostPort)/\(port.proto)",
                               subtitle: port.hostAddress,
                               info: [Field(label: "On your Mac", value: "\(port.hostAddress):\(port.hostPort)"),
                                      Field(label: "In container", value: "\(port.containerPort)/\(port.proto)")])
                link(cid, pid, .publishes)
            }
        }

        // Similarity: containers built from the same repository with different tags.
        let byRepo = Dictionary(grouping: containers, by: { ImageReferenceSuggester.shortName($0.imageReference) })
        for group in byRepo.values where group.count > 1 {
            let refs = Set(group.map(\.imageReference))
            guard refs.count > 1 else { continue }   // same image: already joined through the image node
            for (i, a) in group.enumerated() {
                for b in group.dropFirst(i + 1) where a.imageReference != b.imageReference {
                    link("Container:\(a.id)", "Container:\(b.id)", .similar)
                }
            }
        }

        for m in machines {
            let mid = node(.machine, m.id, title: m.id, subtitle: m.status.displayTitle,
                           info: [Field(label: "Image", value: m.imageReference ?? "—"),
                                  Field(label: "State", value: m.status.displayTitle),
                                  Field(label: "Resources", value: "\(m.cpus) vCPU · \(NordicFormat.bytes(fromByteCount: Int64(m.memoryBytes), countStyle: .memory))"),
                                  Field(label: "Home mount", value: m.homeMount.displayTitle),
                                  Field(label: "User", value: m.username ?? "—"),
                                  Field(label: "Default", value: m.isDefault ? "Yes" : "No")],
                           destination: .machine(m.id), active: m.status == .running)
            if let ref = m.imageReference {
                let imageID = imageByRef[ref] ?? imageByRef[short(ref)]
                    ?? node(.image, ref, title: short(ref), subtitle: "not on this Mac", info: [Field(label: "Reference", value: ref)], active: false)
                link(mid, imageID, .runs)
            }
            if let ip = m.ipAddress { link(mid, addressNode(ip, owner: m.id), .hasAddress) }
        }

        return ResourceGraph(nodes: order.compactMap { nodes[$0] }, edges: edges)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// IPv4 helpers for subnet membership.
enum IPv4 {
    static func value(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    static func contains(cidr: String, address: String) -> Bool {
        let pieces = cidr.split(separator: "/")
        guard pieces.count == 2, let base = value(String(pieces[0])), let bits = UInt32(pieces[1]), bits <= 32,
              let ip = value(address) else { return false }
        let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << (32 - bits)
        return (base & mask) == (ip & mask)
    }
}

// MARK: - Layouts

public enum GraphLayout: String, CaseIterable, Identifiable, Sendable {
    case force = "Force-Directed"
    case layered = "Hierarchy"
    case radial = "Radial"
    case circular = "Circular"
    case grouped = "By Type"

    public var id: String { rawValue }

    public var explanation: String {
        switch self {
        case .force: return "Connected nodes pull together and all nodes push apart (Fruchterman–Reingold), so clusters of related resources form on their own."
        case .layered: return "Layers from stacks to containers to what they use (images, networks, storage, ports) to subnets and registries, ordered to reduce crossing lines (Sugiyama-style)."
        case .radial: return "Rings around the selected node (or the most connected one) by how many hops away each node is."
        case .circular: return "All nodes on one circle, grouped by type."
        case .grouped: return "One column per resource type, sorted by name."
        }
    }

    /// Positions for every node inside `size` (with a margin).
    public func positions(for graph: ResourceGraph, in size: CGSize, focus: String? = nil) -> [String: CGPoint] {
        guard !graph.nodes.isEmpty else { return [:] }
        let raw: [String: CGPoint]
        var fixed: Set<String> = []
        switch self {
        case .grouped: raw = Self.grouped(graph, size)
        case .circular: raw = Self.circular(graph, size)
        case .radial:
            raw = Self.radial(graph, size, focus: focus)
            // The focus stays exactly in the middle; its neighbours make room.
            if let root = Self.radialRoot(graph, focus: focus) { fixed = [root] }
        case .layered: raw = Self.layered(graph, size)
        case .force: raw = Self.force(graph, size)
        }
        return Self.removeOverlaps(raw, in: size, fixed: fixed)
    }

    /// The space a node chip takes (world units), with a little air around it.
    static let nodeFootprint = CGSize(width: 196, height: 54)

    /// Pushes apart chips whose boxes overlap, along the axis that needs the smaller move, so
    /// labels never sit on top of each other. Deterministic (processes nodes in id order).
    static func removeOverlaps(_ positions: [String: CGPoint], in size: CGSize, fixed: Set<String> = [], iterations: Int = 80) -> [String: CGPoint] {
        let ids = positions.keys.sorted()
        var pos = ids.map { positions[$0]! }
        let isFixed = ids.map { fixed.contains($0) }
        let w = nodeFootprint.width, h = nodeFootprint.height
        for _ in 0..<iterations {
            var moved = false
            // Only chips in the same or a neighbouring cell can overlap: a grid of chip-sized cells
            // keeps each pass close to linear instead of comparing every pair.
            var grid: [GridKey: [Int]] = [:]
            for (i, p) in pos.enumerated() { grid[GridKey(Int((p.x / w).rounded(.down)), Int((p.y / h).rounded(.down))), default: []].append(i) }
            for i in 0..<pos.count {
                let cx = Int((pos[i].x / w).rounded(.down)), cy = Int((pos[i].y / h).rounded(.down))
                for gx in (cx - 1)...(cx + 1) {
                    for gy in (cy - 1)...(cy + 1) {
                        for j in grid[GridKey(gx, gy)] ?? [] where j > i {
                            let dx = pos[j].x - pos[i].x, dy = pos[j].y - pos[i].y
                            let overlapX = w - abs(dx), overlapY = h - abs(dy)
                            guard overlapX > 0, overlapY > 0 else { continue }
                            if isFixed[i] && isFixed[j] { continue }
                            moved = true
                            // A fixed node doesn't move; the other one takes the whole push.
                            let shareI: CGFloat = isFixed[i] ? 0 : (isFixed[j] ? 1 : 0.5)
                            let shareJ: CGFloat = 1 - shareI
                            if overlapX / w < overlapY / h {
                                let push = overlapX * (dx >= 0 ? 1 : -1)
                                pos[i].x -= push * shareI; pos[j].x += push * shareJ
                            } else {
                                let push = overlapY * (dy >= 0 ? 1 : -1)
                                pos[i].y -= push * shareI; pos[j].y += push * shareJ
                            }
                        }
                    }
                }
            }
            if !moved { break }
        }
        // Keep everything on the canvas; the view grows its world to fit node counts.
        let minX = margin / 2, maxX = max(minX, size.width - margin / 2)
        let minY = margin / 2, maxY = max(minY, size.height - margin / 2)
        return Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            (id, isFixed[i] ? pos[i] : CGPoint(x: min(maxX, max(minX, pos[i].x)), y: min(maxY, max(minY, pos[i].y))))
        })
    }

    struct GridKey: Hashable {
        let x: Int, y: Int
        init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    }

    static let margin: CGFloat = 90

    static func kindIndex(_ k: ResourceGraph.Kind) -> Int { ResourceGraph.Kind.allCases.firstIndex(of: k) ?? 0 }

    static func grouped(_ g: ResourceGraph, _ size: CGSize) -> [String: CGPoint] {
        let groups = Dictionary(grouping: g.nodes, by: \.kind)
        let kinds = ResourceGraph.Kind.allCases.filter { groups[$0] != nil }
        let usableW = max(1, size.width - margin * 2), usableH = max(1, size.height - margin * 2)
        var result: [String: CGPoint] = [:]
        for (col, kind) in kinds.enumerated() {
            let members = (groups[kind] ?? []).sorted { $0.title.lowercased() < $1.title.lowercased() }
            let x = margin + (kinds.count == 1 ? usableW / 2 : usableW * CGFloat(col) / CGFloat(kinds.count - 1))
            for (row, node) in members.enumerated() {
                let y = margin + (members.count == 1 ? usableH / 2 : usableH * CGFloat(row) / CGFloat(members.count - 1))
                result[node.id] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    static func circular(_ g: ResourceGraph, _ size: CGSize) -> [String: CGPoint] {
        let sorted = g.nodes.sorted { (kindIndex($0.kind), $0.title) < (kindIndex($1.kind), $1.title) }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(40, min(size.width, size.height) / 2 - margin)
        var result: [String: CGPoint] = [:]
        for (i, node) in sorted.enumerated() {
            let angle = 2 * Double.pi * Double(i) / Double(sorted.count) - Double.pi / 2
            result[node.id] = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        return result
    }

    /// The selected node, or the most connected one.
    static func radialRoot(_ g: ResourceGraph, focus: String?) -> String? {
        if let f = focus, g.nodes.contains(where: { $0.id == f }) { return f }
        let adj = g.adjacencyMap()
        return g.nodes.max { (adj[$0.id]?.count ?? 0, $1.id) < (adj[$1.id]?.count ?? 0, $0.id) }?.id
    }

    static func radial(_ g: ResourceGraph, _ size: CGSize, focus: String?) -> [String: CGPoint] {
        guard let root = radialRoot(g, focus: focus) else { return [:] }
        // Breadth-first rings; unreachable nodes go on an outer ring.
        let adj = g.adjacencyMap()
        var depth: [String: Int] = [root: 0]
        var queue = [root]
        var head = 0
        while head < queue.count {
            let current = queue[head]; head += 1
            for n in (adj[current] ?? []).sorted() where depth[n] == nil {
                depth[n] = depth[current]! + 1
                queue.append(n)
            }
        }
        let maxDepth = (depth.values.max() ?? 0) + 1
        for node in g.nodes where depth[node.id] == nil { depth[node.id] = maxDepth }
        let rings = Dictionary(grouping: g.nodes, by: { depth[$0.id]! })
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Rings at least a chip apart, and wide enough for the chips on them.
        let step = max(nodeFootprint.width * 0.8, (min(size.width, size.height) / 2 - margin) / CGFloat(max(1, rings.keys.max() ?? 1)))
        var result: [String: CGPoint] = [root: center]
        var previousRadius: CGFloat = 0
        for ring in rings.keys.sorted() where ring > 0 {
            let sorted = rings[ring]!.sorted { (kindIndex($0.kind), $0.title) < (kindIndex($1.kind), $1.title) }
            let fitRadius = CGFloat(sorted.count) * nodeFootprint.height * 1.6 / (2 * .pi)
            let radius = max(previousRadius + step, fitRadius)
            previousRadius = radius
            for (i, node) in sorted.enumerated() {
                let angle = 2 * Double.pi * Double(i) / Double(sorted.count) + Double(ring) * 0.4
                result[node.id] = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
        }
        return result
    }

    /// Layer of each kind for the hierarchy layout.
    static func layer(of kind: ResourceGraph.Kind) -> Int {
        switch kind {
        case .stack: return 0
        case .container, .machine: return 1
        case .image, .network, .volume, .hostFolder, .port, .ipAddress: return 2
        case .subnet, .registry: return 3
        }
    }

    static func layered(_ g: ResourceGraph, _ size: CGSize) -> [String: CGPoint] {
        let adj = g.adjacencyMap()
        var layers = Dictionary(grouping: g.nodes, by: { layer(of: $0.kind) }).mapValues { $0.map(\.id) }
        let keys = layers.keys.sorted()
        for k in keys { layers[k]!.sort() }
        // Barycenter ordering: two down and up sweeps reduce edge crossings.
        func order(_ layer: [String], by reference: [String]) -> [String] {
            var index: [String: Double] = [:]
            for (i, id) in reference.enumerated() { index[id] = Double(i) }
            var scored: [(id: String, score: Double)] = []
            for id in layer {
                let positions: [Double] = (adj[id] ?? []).compactMap { index[$0] }
                let score: Double = positions.isEmpty ? .greatestFiniteMagnitude : positions.reduce(0, +) / Double(positions.count)
                scored.append((id, score))
            }
            scored.sort { a, b in a.score == b.score ? a.id < b.id : a.score < b.score }
            return scored.map(\.id)
        }
        for _ in 0..<2 {
            for (a, b) in zip(keys, keys.dropFirst()) { layers[b] = order(layers[b]!, by: layers[a]!) }
            for (a, b) in zip(keys.reversed(), keys.reversed().dropFirst()) { layers[b] = order(layers[b]!, by: layers[a]!) }
        }
        let usableW = max(1, size.width - margin * 2), usableH = max(1, size.height - margin * 2)
        var result: [String: CGPoint] = [:]
        for (row, k) in keys.enumerated() {
            let members = layers[k]!
            let y = margin + (keys.count == 1 ? usableH / 2 : usableH * CGFloat(row) / CGFloat(keys.count - 1))
            for (i, id) in members.enumerated() {
                let x = margin + usableW * (CGFloat(i) + 0.5) / CGFloat(members.count)
                result[id] = CGPoint(x: x, y: y)
            }
        }
        return result
    }

    /// Fruchterman–Reingold, started from the circular layout so the result is deterministic.
    static func force(_ g: ResourceGraph, _ size: CGSize, iterations requested: Int? = nil) -> [String: CGPoint] {
        // Large graphs settle in fewer rounds; small ones get the full schedule.
        let iterations = requested ?? (g.nodes.count > 150 ? 160 : 300)
        let ids = g.nodes.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let start = circular(g, size)
        var pos = ids.map { start[$0]! }
        let area = Double(max(1, (size.width - margin * 2) * (size.height - margin * 2)))
        let k = sqrt(area / Double(max(1, ids.count))) * 0.55
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let links = g.edges.compactMap { e -> (Int, Int)? in
            guard let a = index[e.from], let b = index[e.to] else { return nil }
            return (a, b)
        }
        var temperature = Double(min(size.width, size.height)) / 8
        for _ in 0..<iterations {
            var disp = Array(repeating: CGVector.zero, count: ids.count)
            // Repulsion only within 2k, found through a grid of 2k cells: the grid variant from
            // Fruchterman & Reingold's paper, near-linear instead of every pair.
            let cell = 2 * k
            var grid: [GridKey: [Int]] = [:]
            for (i, p) in pos.enumerated() { grid[GridKey(Int(Double(p.x) / cell), Int(Double(p.y) / cell)), default: []].append(i) }
            for i in 0..<ids.count {
                let cx = Int(Double(pos[i].x) / cell), cy = Int(Double(pos[i].y) / cell)
                for gx in (cx - 1)...(cx + 1) {
                    for gy in (cy - 1)...(cy + 1) {
                        for j in grid[GridKey(gx, gy)] ?? [] where j > i {
                            var dx = Double(pos[i].x - pos[j].x), dy = Double(pos[i].y - pos[j].y)
                            var dist = sqrt(dx * dx + dy * dy)
                            if dist > cell { continue }
                            if dist < 0.01 { dx = 0.1 * Double(i - j); dy = 0.1; dist = 0.15 }
                            let force = k * k / dist
                            disp[i].dx += dx / dist * force; disp[i].dy += dy / dist * force
                            disp[j].dx -= dx / dist * force; disp[j].dy -= dy / dist * force
                        }
                    }
                }
            }
            for (a, b) in links {
                let dx = Double(pos[a].x - pos[b].x), dy = Double(pos[a].y - pos[b].y)
                let dist = max(0.01, sqrt(dx * dx + dy * dy))
                let force = dist * dist / k
                disp[a].dx -= dx / dist * force; disp[a].dy -= dy / dist * force
                disp[b].dx += dx / dist * force; disp[b].dy += dy / dist * force
            }
            // Gravity toward the centre keeps separate clusters from drifting to the edges.
            for i in 0..<ids.count {
                disp[i].dx += Double(center.x - pos[i].x) * 0.9
                disp[i].dy += Double(center.y - pos[i].y) * 0.9
            }
            for i in 0..<ids.count {
                let len = max(0.01, sqrt(disp[i].dx * disp[i].dx + disp[i].dy * disp[i].dy))
                let step = min(len, temperature)
                pos[i].x = min(size.width - margin, max(margin, pos[i].x + disp[i].dx / len * step))
                pos[i].y = min(size.height - margin, max(margin, pos[i].y + disp[i].dy / len * step))
            }
            temperature = max(0.5, temperature * 0.97)
        }
        return Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, pos[$0]) })
    }
}
