import Foundation

/// One hit of the toolbar's universal search.
public struct UniversalSearchResult: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case container = "Container"
        case stack = "Stack"
        case image = "Image"
        case machine = "Machine"
        case volume = "Volume"
        case network = "Network"
        case registry = "Registry"
        case libraryImage = "Library"
        case section = "Page"
    }

    /// Where opening the result goes.
    public enum Destination: Equatable, Sendable {
        case container(String)
        case stack(String)
        case image(String)
        case machine(String)
        case volume(String)
        case network(String)
        case registry
        case libraryImage(String)
        case section(NavigationSection)
    }

    public var id: String { "\(kind.rawValue):\(title):\(location)" }
    public let kind: Kind
    public let title: String
    /// Where it lives: the page, and a path, address or reference when it has one.
    public let location: String
    /// State or a key fact (running, size, subnet…).
    public let detail: String
    public let destination: Destination
    /// Lower ranks first: 0 name starts with the query, 1 a word in the name does, 2 the name
    /// contains it, 3 only another field (image, path, address…) does.
    let rank: Int
}

/// Searches every resource Låda knows about. Pure, so it is unit-tested without views.
public enum UniversalSearch {
    public struct Inputs: Sendable {
        public var containers: [ContainerModel] = []
        public var images: [ImageModel] = []
        public var machines: [MachineModel] = []
        public var volumes: [VolumeModel] = []
        public var networks: [NetworkModel] = []
        public var registries: [RegistryModel] = []
        public var catalog: [DockerHubRepositoryItem] = []
        public init() {}
    }

    public static func results(for query: String, in inputs: Inputs, limit: Int = 40) -> [UniversalSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [UniversalSearchResult] = []

        func add(_ kind: UniversalSearchResult.Kind, title: String, location: String, detail: String,
                 destination: UniversalSearchResult.Destination, also other: [String] = []) {
            guard let rank = rank(of: q, title: title, other: other + [location]) else { return }
            hits.append(UniversalSearchResult(kind: kind, title: title, location: location, detail: detail, destination: destination, rank: rank))
        }

        var stacks: [String: [ContainerModel]] = [:]
        for c in inputs.containers {
            if let project = c.composeProject { stacks[project, default: []].append(c) }
            let ports = c.configuration.publishedPorts.map { "\($0.hostPort)" }
            add(.container, title: c.id,
                location: "Containers" + (c.composeProject.map { " › \($0)" } ?? "") + " · \(c.shortImageReference)",
                detail: c.state.displayTitle,
                destination: .container(c.id),
                also: [c.imageReference, c.primaryIPv4 ?? ""] + ports)
        }
        for (name, members) in stacks {
            let running = members.filter { $0.state == .running }.count
            add(.stack, title: name, location: "Containers › stack of \(members.count)",
                detail: "\(running) of \(members.count) running", destination: .stack(name),
                also: members.map(\.id))
        }
        for image in inputs.images {
            add(.image, title: image.fullReference.replacingOccurrences(of: "docker.io/library/", with: ""),
                location: "Images · \(image.registryOrigin)",
                detail: image.digest.isEmpty ? "" : String(image.digest.prefix(19)),
                destination: .image(image.id),
                also: [image.repository, image.tag, image.digest])
        }
        for m in inputs.machines {
            add(.machine, title: m.id,
                location: "Machines" + (m.ipAddress.map { " · \($0)" } ?? "") + (m.homeDirectory.map { " · \($0)" } ?? ""),
                detail: m.status.displayTitle + (m.isDefault ? " · default" : ""),
                destination: .machine(m.id),
                also: [m.imageReference ?? "", m.containerID ?? ""])
        }
        for v in inputs.volumes {
            add(.volume, title: v.name, location: "Volumes · \(v.sourcePath)",
                detail: v.sizeInBytes.map { NordicFormat.bytes(fromByteCount: Int64($0), countStyle: .file) } ?? v.format,
                destination: .volume(v.id))
        }
        for n in inputs.networks {
            add(.network, title: n.name, location: "Networks · \(n.ipv4Subnet)",
                detail: n.isBuiltin ? "built-in" : n.mode, destination: .network(n.id),
                also: [n.ipv4Gateway, n.ipv6Subnet ?? ""])
        }
        for r in inputs.registries {
            add(.registry, title: r.hostname, location: "Registries", detail: r.isAuthenticated ? "Signed in as \(r.username)" : "Signed out",
                destination: .registry, also: [r.username])
        }
        for item in inputs.catalog {
            add(.libraryImage, title: item.name, location: "Image Library · \(item.category.rawValue)",
                detail: item.availableTags.first ?? "", destination: .libraryImage(item.name),
                also: [item.description])
        }
        for section in NavigationSection.allCases {
            add(.section, title: section.rawValue, location: "Sidebar", detail: "", destination: .section(section))
        }

        let kindOrder = Dictionary(uniqueKeysWithValues: UniversalSearchResult.Kind.allCases.enumerated().map { ($1, $0) })
        let sorted = hits.sorted {
            ($0.rank, kindOrder[$0.kind] ?? 0, $0.title.lowercased()) < ($1.rank, kindOrder[$1.kind] ?? 0, $1.title.lowercased())
        }
        return Array(sorted.prefix(limit))
    }

    static func rank(of q: String, title: String, other: [String]) -> Int? {
        let t = title.lowercased()
        if t.hasPrefix(q) { return 0 }
        if t.split(whereSeparator: { "-_./: ".contains($0) }).contains(where: { $0.hasPrefix(q) }) { return 1 }
        if t.contains(q) { return 2 }
        if other.contains(where: { $0.lowercased().contains(q) }) { return 3 }
        return nil
    }
}
