import Foundation

public enum DockerHubCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case all = "All Categories"
    case webAndProxy = "Web & Proxy"
    case databases = "Databases"
    case languages = "Languages & Runtimes"
    case cachingAndQueues = "Caching & Queues"
    case devOpsAndTools = "DevOps & Utilities"
    case baseOS = "Base OS"

    public var id: String { rawValue }
}

public enum DockerHubSortOption: String, CaseIterable, Sendable, Identifiable {
    case mostPulls = "Most Pulls"
    case mostStars = "Most Stars"
    case nameAZ = "Name (A–Z)"
    case recentlyUpdated = "Recently Updated"

    public var id: String { rawValue }
}

public enum DockerHubBadgeFilter: String, CaseIterable, Sendable, Identifiable {
    case all = "All Images"
    case officialOnly = "Official Images"
    case verifiedOnly = "Verified Publishers"
    case arm64Native = "Apple Silicon (ARM64)"

    public var id: String { rawValue }
}

public struct DockerHubRepositoryItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String { slug }
    public let slug: String
    public let name: String
    public let namespace: String
    public let description: String
    public let starCount: Int
    public let pullCount: Int64
    public let isOfficial: Bool
    public let isVerifiedPublisher: Bool
    public let category: DockerHubCategory
    public let architectures: [String]
    public let availableTags: [String]
    public let recommendedPorts: [PortMapping]
    public let recommendedEnv: [KeyValueEntry]
    public let recommendedVolumes: [MountAttachment]
    public let defaultCommand: [String]
    public let updatedAt: Date

    public init(
        slug: String,
        name: String,
        namespace: String = "library",
        description: String,
        starCount: Int,
        pullCount: Int64,
        isOfficial: Bool = true,
        isVerifiedPublisher: Bool = false,
        category: DockerHubCategory = .baseOS,
        architectures: [String] = ["arm64", "amd64"],
        availableTags: [String] = ["latest"],
        recommendedPorts: [PortMapping] = [],
        recommendedEnv: [KeyValueEntry] = [],
        recommendedVolumes: [MountAttachment] = [],
        defaultCommand: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.slug = slug
        self.name = name
        self.namespace = namespace
        self.description = description
        self.starCount = starCount
        self.pullCount = pullCount
        self.isOfficial = isOfficial
        self.isVerifiedPublisher = isVerifiedPublisher
        self.category = category
        self.architectures = architectures
        self.availableTags = availableTags
        self.recommendedPorts = recommendedPorts
        self.recommendedEnv = recommendedEnv
        self.recommendedVolumes = recommendedVolumes
        self.defaultCommand = defaultCommand
        self.updatedAt = updatedAt
    }

    public func imageReference(forTag tag: String = "latest") -> String {
        let prefix = isOfficial || namespace == "library" ? "" : "\(namespace)/"
        return "\(prefix)\(name):\(tag)"
    }

    public var formattedPullCount: String {
        if pullCount >= 1_000_000_000 {
            return String(format: "%.1fB+", Double(pullCount) / 1_000_000_000.0)
        } else if pullCount >= 1_000_000 {
            return String(format: "%.1fM+", Double(pullCount) / 1_000_000.0)
        } else if pullCount >= 1_000 {
            return String(format: "%.1fK", Double(pullCount) / 1_000.0)
        }
        return "\(pullCount)"
    }

    public var formattedStarCount: String {
        if starCount >= 1_000 {
            return String(format: "%.1fk", Double(starCount) / 1_000.0)
        }
        return "\(starCount)"
    }

    public func buildDeployRequest(
        selectedTag: String,
        defaultCPUs: Int = 4,
        defaultMemoryMB: Int = 1024
    ) -> ContainerCreateRequest {
        let sanitizedName = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_.-]", with: "-", options: .regularExpression)
        return ContainerCreateRequest(
            name: sanitizedName,
            imageReference: imageReference(forTag: selectedTag),
            startImmediately: true,
            commandArguments: defaultCommand,
            interactive: true,
            allocateTTY: true,
            publishedPorts: recommendedPorts,
            mounts: recommendedVolumes,
            environmentVariables: recommendedEnv,
            cpus: defaultCPUs,
            memoryMB: defaultMemoryMB
        )
    }
}

public actor DockerHubService {
    public static let shared = DockerHubService()

    public init() {}

    /// Searches `hub.docker.com` live API and merges with rich deployment metadata.
    public func searchRepositories(query: String) async -> [DockerHubRepositoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = Self.curatedCatalog

        if trimmed.isEmpty {
            return catalog
        }

        // Filter curated catalog first for instant matching
        let localMatches = catalog.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.slug.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed) ||
            $0.category.rawValue.localizedCaseInsensitiveContains(trimmed)
        }

        // Also query live Docker Hub Search API (`https://hub.docker.com/v2/search/repositories/`)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://hub.docker.com/v2/search/repositories/?query=\(encoded)&page_size=25") else {
            return localMatches
        }

        do {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Lada-Desktop/1.5.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return localMatches
            }

            struct HubSearchResponse: Decodable {
                struct Result: Decodable {
                    let repo_name: String?
                    let short_description: String?
                    let star_count: Int?
                    let pull_count: Int64?
                    let is_official: Bool?
                    let is_automated: Bool?
                }
                let results: [Result]?
            }

            let decoded = try JSONDecoder().decode(HubSearchResponse.self, from: data)
            var merged: [DockerHubRepositoryItem] = localMatches
            let existingSlugs = Set(merged.map { $0.slug.lowercased() })

            for item in decoded.results ?? [] {
                guard let repoName = item.repo_name, !repoName.isEmpty else { continue }
                if existingSlugs.contains(repoName.lowercased()) { continue }

                let parts = repoName.split(separator: "/", maxSplits: 1).map(String.init)
                let isOfficial = item.is_official ?? (parts.count == 1)
                let namespace = parts.count > 1 ? parts[0] : "library"
                let shortName = parts.count > 1 ? parts[1] : repoName

                let inferred = Self.inferMetadata(for: shortName, description: item.short_description ?? "")
                merged.append(
                    DockerHubRepositoryItem(
                        slug: repoName,
                        name: shortName,
                        namespace: namespace,
                        description: (item.short_description?.isEmpty == false)
                            ? item.short_description!
                            : "Container image hosted on Docker Hub (\(repoName)).",
                        starCount: item.star_count ?? 0,
                        pullCount: item.pull_count ?? 0,
                        isOfficial: isOfficial,
                        isVerifiedPublisher: !isOfficial && (item.is_automated ?? false),
                        category: inferred.category,
                        architectures: ["arm64", "amd64"],
                        availableTags: ["latest", "alpine", "slim"],
                        recommendedPorts: inferred.ports,
                        recommendedEnv: inferred.env,
                        recommendedVolumes: inferred.volumes
                    )
                )
            }
            return merged
        } catch {
            return localMatches
        }
    }

    /// Fetches live tags for a repository from `hub.docker.com`.
    public func fetchTags(for item: DockerHubRepositoryItem) async -> [String] {
        let ns = item.isOfficial ? "library" : item.namespace
        guard let url = URL(string: "https://hub.docker.com/v2/repositories/\(ns)/\(item.name)/tags?page_size=15") else {
            return item.availableTags
        }
        do {
            var req = URLRequest(url: url, timeoutInterval: 6)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return item.availableTags
            }
            struct TagResponse: Decodable {
                struct TagEntry: Decodable {
                    let name: String
                }
                let results: [TagEntry]?
            }
            let decoded = try JSONDecoder().decode(TagResponse.self, from: data)
            let names = (decoded.results ?? []).map(\.name).filter { !$0.isEmpty }
            return names.isEmpty ? item.availableTags : names
        } catch {
            return item.availableTags
        }
    }

    private static func inferMetadata(
        for name: String,
        description: String
    ) -> (category: DockerHubCategory, ports: [PortMapping], env: [KeyValueEntry], volumes: [MountAttachment]) {
        let lower = (name + " " + description).lowercased()
        if lower.contains("postgres") {
            return (
                .databases,
                [PortMapping(hostAddress: "127.0.0.1", hostPort: 5432, containerPort: 5432, proto: "tcp")],
                [
                    KeyValueEntry(key: "POSTGRES_USER", value: "postgres"),
                    KeyValueEntry(key: "POSTGRES_PASSWORD", value: "postgres", isSecret: true),
                    KeyValueEntry(key: "POSTGRES_DB", value: "appdb"),
                    KeyValueEntry(key: "PGDATA", value: "/var/lib/postgresql/data/pgdata")
                ],
                [MountAttachment(kind: .volume, source: "postgres-data", destination: "/var/lib/postgresql/data", readOnly: false, volumeName: "postgres-data")]
            )
        }
        if lower.contains("db") || lower.contains("sql") || lower.contains("mongo") || lower.contains("database") {
            return (.databases, [], [], [])
        }
        if lower.contains("nginx") || lower.contains("http") || lower.contains("web") || lower.contains("proxy") || lower.contains("caddy") {
            return (
                .webAndProxy,
                [PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")],
                [],
                []
            )
        }
        if lower.contains("redis") || lower.contains("kafka") || lower.contains("rabbit") || lower.contains("cache") {
            return (.cachingAndQueues, [], [], [])
        }
        if lower.contains("python") || lower.contains("node") || lower.contains("swift") || lower.contains("golang") || lower.contains("rust") || lower.contains("java") {
            return (.languages, [], [], [])
        }
        return (.devOpsAndTools, [], [], [])
    }

    // MARK: - Curated Docker Hub Catalog (`hub.docker.com`)

    public static let curatedCatalog: [DockerHubRepositoryItem] = [
        DockerHubRepositoryItem(
            slug: "nginx",
            name: "nginx",
            description: "Official build of Nginx high-performance HTTP server and reverse proxy.",
            starCount: 20400,
            pullCount: 10_000_000_000,
            isOfficial: true,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "1.27-alpine", "stable-alpine", "mainline"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "nginx-html", destination: "/usr/share/nginx/html", readOnly: false, volumeName: "nginx-html")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 6)
        ),
        DockerHubRepositoryItem(
            slug: "postgres",
            name: "postgres",
            description: "The PostgreSQL object-relational database system provides reliability and data integrity.",
            starCount: 14200,
            pullCount: 8_500_000_000,
            isOfficial: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["17-alpine", "16-alpine", "16", "15-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 5432, containerPort: 5432, proto: "tcp")
            ],
            recommendedEnv: [
                KeyValueEntry(key: "POSTGRES_USER", value: "postgres"),
                KeyValueEntry(key: "POSTGRES_PASSWORD", value: "postgres", isSecret: true),
                KeyValueEntry(key: "POSTGRES_DB", value: "appdb"),
                KeyValueEntry(key: "PGDATA", value: "/var/lib/postgresql/data/pgdata")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "postgres-data", destination: "/var/lib/postgresql/data", readOnly: false, volumeName: "postgres-data")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 12)
        ),
        DockerHubRepositoryItem(
            slug: "redis",
            name: "redis",
            description: "Redis is an open-source, networked, in-memory, key-value data store with optional durability.",
            starCount: 13600,
            pullCount: 9_200_000_000,
            isOfficial: true,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["7-alpine", "7.4-alpine", "latest", "alpine"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 6379, containerPort: 6379, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "redis-data", destination: "/data", readOnly: false, volumeName: "redis-data")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 8)
        ),
        DockerHubRepositoryItem(
            slug: "alpine",
            name: "alpine",
            description: "A minimal Docker image based on Alpine Linux with a complete package index and only 5 MB in size.",
            starCount: 11200,
            pullCount: 12_000_000_000,
            isOfficial: true,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "3.21", "3.20", "3.19", "edge"],
            updatedAt: Date().addingTimeInterval(-3600 * 4)
        ),
        DockerHubRepositoryItem(
            slug: "ubuntu",
            name: "ubuntu",
            description: "Ubuntu is a Debian-based Linux operating system that runs from the desktop to the cloud.",
            starCount: 17500,
            pullCount: 11_000_000_000,
            isOfficial: true,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["24.04", "22.04", "latest", "noble", "jammy"],
            updatedAt: Date().addingTimeInterval(-3600 * 18)
        ),
        DockerHubRepositoryItem(
            slug: "swift",
            name: "swift",
            description: "Swift is a high-performance system programming language with a clean and modern syntax.",
            starCount: 2450,
            pullCount: 120_000_000,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["6.0-slim", "6.0", "5.10-slim", "latest"],
            updatedAt: Date().addingTimeInterval(-3600 * 24)
        ),
        DockerHubRepositoryItem(
            slug: "node",
            name: "node",
            description: "Node.js is a JavaScript-based platform for server-side and networking applications.",
            starCount: 10800,
            pullCount: 7_800_000_000,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["22-alpine", "20-alpine", "lts-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3000, containerPort: 3000, proto: "tcp")
            ],
            defaultCommand: ["node", "-e", "require('http').createServer((q,r)=>r.end('Node.js running on Lada\\n')).listen(3000)"],
            updatedAt: Date().addingTimeInterval(-3600 * 10)
        ),
        DockerHubRepositoryItem(
            slug: "python",
            name: "python",
            description: "Python is an interpreted, interactive, object-oriented, open-source programming language.",
            starCount: 10300,
            pullCount: 8_100_000_000,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["3.13-slim", "3.12-slim", "3.12-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8000, containerPort: 8000, proto: "tcp")
            ],
            defaultCommand: ["python3", "-m", "http.server", "8000"],
            updatedAt: Date().addingTimeInterval(-3600 * 14)
        ),
        DockerHubRepositoryItem(
            slug: "mysql",
            name: "mysql",
            description: "MySQL is a widely used, open-source relational database management system (RDBMS).",
            starCount: 15400,
            pullCount: 6_400_000_000,
            isOfficial: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["8.4", "9.0", "8.0", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3306, containerPort: 3306, proto: "tcp")
            ],
            recommendedEnv: [
                KeyValueEntry(key: "MYSQL_ROOT_PASSWORD", value: "rootpassword", isSecret: true),
                KeyValueEntry(key: "MYSQL_DATABASE", value: "appdb")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "mysql-data", destination: "/var/lib/mysql", readOnly: false, volumeName: "mysql-data")
            ],
            defaultCommand: ["--datadir=/var/lib/mysql/data"],
            updatedAt: Date().addingTimeInterval(-3600 * 28)
        ),
        DockerHubRepositoryItem(
            slug: "mongo",
            name: "mongo",
            description: "MongoDB document databases provide high availability and easy scalability.",
            starCount: 10900,
            pullCount: 5_200_000_000,
            isOfficial: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["8.0", "7.0", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 27017, containerPort: 27017, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "mongo-data", destination: "/data/db", readOnly: false, volumeName: "mongo-data")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 20)
        ),
        DockerHubRepositoryItem(
            slug: "caddy",
            name: "caddy",
            description: "Caddy 2 is a powerful, enterprise-ready, open source web server with automatic HTTPS written in Go.",
            starCount: 5200,
            pullCount: 950_000_000,
            isOfficial: true,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["2-alpine", "latest", "builder"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8443, containerPort: 443, proto: "tcp")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 15)
        ),
        DockerHubRepositoryItem(
            slug: "traefik",
            name: "traefik",
            description: "Traefik is a modern HTTP reverse proxy and load balancer that makes deploying microservices easy.",
            starCount: 4600,
            pullCount: 3_100_000_000,
            isOfficial: true,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["v3.2", "v2.11", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8081, containerPort: 8080, proto: "tcp")
            ],
            defaultCommand: ["--api.insecure=true"],
            updatedAt: Date().addingTimeInterval(-3600 * 22)
        ),
        DockerHubRepositoryItem(
            slug: "rabbitmq",
            name: "rabbitmq",
            description: "RabbitMQ is an open source multi-protocol messaging broker supporting AMQP, MQTT, and STOMP.",
            starCount: 5900,
            pullCount: 3_800_000_000,
            isOfficial: true,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["4-management-alpine", "3-management-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 5672, containerPort: 5672, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 15672, containerPort: 15672, proto: "tcp")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 30)
        ),
        DockerHubRepositoryItem(
            slug: "golang",
            name: "golang",
            description: "Go (golang) is a general purpose, higher-level, imperative programming language.",
            starCount: 5100,
            pullCount: 4_500_000_000,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["1.23-alpine", "1.23-bookworm", "latest"],
            updatedAt: Date().addingTimeInterval(-3600 * 16)
        ),
        DockerHubRepositoryItem(
            slug: "rust",
            name: "rust",
            description: "Rust is a systems programming language empowering everyone to build reliable and efficient software.",
            starCount: 2800,
            pullCount: 680_000_000,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["1.82-slim", "alpine", "latest"],
            updatedAt: Date().addingTimeInterval(-3600 * 26)
        ),
        DockerHubRepositoryItem(
            slug: "grafana/grafana",
            name: "grafana",
            namespace: "grafana",
            description: "The open and composable observability and data visualization platform by Grafana Labs.",
            starCount: 6400,
            pullCount: 4_900_000_000,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "oss", "11.3.0"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3000, containerPort: 3000, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "grafana-storage", destination: "/var/lib/grafana", readOnly: false, volumeName: "grafana-storage")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 9)
        ),
        DockerHubRepositoryItem(
            slug: "prom/prometheus",
            name: "prometheus",
            namespace: "prom",
            description: "Prometheus is a Cloud Native Computing Foundation systems and service monitoring system.",
            starCount: 5800,
            pullCount: 3_700_000_000,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "v3.0.0", "v2.55.0"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 9090, containerPort: 9090, proto: "tcp")
            ],
            updatedAt: Date().addingTimeInterval(-3600 * 19)
        ),
        DockerHubRepositoryItem(
            slug: "debian",
            name: "debian",
            description: "Debian is a Linux distribution that's composed entirely of free and open-source software.",
            starCount: 5400,
            pullCount: 6_900_000_000,
            isOfficial: true,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["bookworm-slim", "bookworm", "trixie-slim", "latest"],
            updatedAt: Date().addingTimeInterval(-3600 * 11)
        )
    ]
}
