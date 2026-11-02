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
    /// `--user` for the preset, when the image's own user cannot write a fresh named volume.
    public let recommendedUser: String?
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
        recommendedUser: String? = nil,
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
        self.recommendedUser = recommendedUser
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
            userSpec: recommendedUser ?? "",
            // Services run detached without a terminal; shell images get `-t` from the builder.
            interactive: false,
            allocateTTY: false,
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

    /// Catalog metadata (stars, pulls, last update, tags with arm64 builds) is a snapshot taken
    /// from the Docker Hub API on 2026-11-02; live search results replace it with current values.
    nonisolated static func hubDate(_ day: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day) ?? Date(timeIntervalSince1970: 0)
    }

    public static let curatedCatalog: [DockerHubRepositoryItem] = [
        DockerHubRepositoryItem(
            slug: "nginx",
            name: "nginx",
            description: "Official build of Nginx high-performance HTTP server and reverse proxy.",
            starCount: 21416,
            pullCount: 13543011190,
            isOfficial: true,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "stable-alpine", "mainline-alpine", "1.31-alpine", "1.30-alpine"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "nginx-html", destination: "/usr/share/nginx/html", readOnly: false, volumeName: "nginx-html")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-31")
        ),
        DockerHubRepositoryItem(
            slug: "postgres",
            name: "postgres",
            description: "The PostgreSQL object-relational database system provides reliability and data integrity.",
            starCount: 15045,
            pullCount: 12175254729,
            isOfficial: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["18-alpine", "17-alpine", "16-alpine", "17", "latest"],
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
            updatedAt: DockerHubService.hubDate("2026-11-01")
        ),
        DockerHubRepositoryItem(
            slug: "redis",
            name: "redis",
            description: "Redis is an open-source, networked, in-memory, key-value data store with optional durability.",
            starCount: 13630,
            pullCount: 11570707528,
            isOfficial: true,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["8-alpine", "8.8-alpine", "alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 6379, containerPort: 6379, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "redis-data", destination: "/data", readOnly: false, volumeName: "redis-data")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-01")
        ),
        DockerHubRepositoryItem(
            slug: "alpine",
            name: "alpine",
            description: "A minimal Docker image based on Alpine Linux with a complete package index and only 5 MB in size.",
            starCount: 11579,
            pullCount: 12454547046,
            isOfficial: true,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "3.24", "3.23", "3.22", "edge"],
            updatedAt: DockerHubService.hubDate("2026-10-23")
        ),
        DockerHubRepositoryItem(
            slug: "ubuntu",
            name: "ubuntu",
            description: "Ubuntu is a Debian-based Linux operating system that runs from the desktop to the cloud.",
            starCount: 17873,
            pullCount: 10143745846,
            isOfficial: true,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["26.04", "24.04", "22.04", "noble", "latest"],
            updatedAt: DockerHubService.hubDate("2026-10-29")
        ),
        DockerHubRepositoryItem(
            slug: "swift",
            name: "swift",
            description: "Swift is a high-performance system programming language with a clean and modern syntax.",
            starCount: 735,
            pullCount: 36768857,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["6.2-slim", "6.2", "slim", "latest", "6.1-slim"],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "node",
            name: "node",
            description: "Node.js is a JavaScript-based platform for server-side and networking applications.",
            starCount: 14213,
            pullCount: 7287739982,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["24-alpine", "22-alpine", "lts-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3000, containerPort: 3000, proto: "tcp")
            ],
            defaultCommand: ["node", "-e", "require('http').createServer((q,r)=>r.end('Node.js running on Lada\\n')).listen(3000)"],
            updatedAt: DockerHubService.hubDate("2026-10-28")
        ),
        DockerHubRepositoryItem(
            slug: "python",
            name: "python",
            description: "Python is an interpreted, interactive, object-oriented, open-source programming language.",
            starCount: 10543,
            pullCount: 9533303866,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["3.14-slim", "3.13-slim", "3.12-slim", "3.14-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8000, containerPort: 8000, proto: "tcp")
            ],
            defaultCommand: ["python3", "-m", "http.server", "8000"],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "mysql",
            name: "mysql",
            description: "MySQL is a widely used, open-source relational database management system (RDBMS).",
            starCount: 16194,
            pullCount: 5229451163,
            isOfficial: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["8.4", "9.7", "lts", "latest"],
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
            updatedAt: DockerHubService.hubDate("2026-10-28")
        ),
        DockerHubRepositoryItem(
            slug: "mongo",
            name: "mongo",
            description: "MongoDB document databases provide high availability and easy scalability.",
            starCount: 10757,
            pullCount: 4909531818,
            isOfficial: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["8.0", "9.0", "7.0", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 27017, containerPort: 27017, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "mongo-data", destination: "/data/db", readOnly: false, volumeName: "mongo-data")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-27")
        ),
        DockerHubRepositoryItem(
            slug: "caddy",
            name: "caddy",
            description: "Caddy 2 is a powerful, enterprise-ready, open source web server with automatic HTTPS written in Go.",
            starCount: 993,
            pullCount: 757709171,
            isOfficial: true,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["2-alpine", "2.11-alpine", "latest", "builder"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8443, containerPort: 443, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "traefik",
            name: "traefik",
            description: "Traefik is a modern HTTP reverse proxy and load balancer that makes deploying microservices easy.",
            starCount: 3674,
            pullCount: 3592096625,
            isOfficial: true,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["v3.7", "v3", "v2.11", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8081, containerPort: 8080, proto: "tcp")
            ],
            defaultCommand: ["--api.insecure=true"],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "rabbitmq",
            name: "rabbitmq",
            description: "RabbitMQ is an open source multi-protocol messaging broker supporting AMQP, MQTT, and STOMP.",
            starCount: 5373,
            pullCount: 3906876281,
            isOfficial: true,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["4-management-alpine", "4.3-management-alpine", "management-alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 5672, containerPort: 5672, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 15672, containerPort: 15672, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "golang",
            name: "golang",
            description: "Go (golang) is a general purpose, higher-level, imperative programming language.",
            starCount: 5122,
            pullCount: 2751818779,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["1.27-alpine", "1.27", "1.26-alpine", "latest"],
            updatedAt: DockerHubService.hubDate("2026-10-29")
        ),
        DockerHubRepositoryItem(
            slug: "rust",
            name: "rust",
            description: "Rust is a systems programming language empowering everyone to build reliable and efficient software.",
            starCount: 1141,
            pullCount: 168112889,
            isOfficial: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["1.99-slim", "slim", "alpine", "latest"],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "grafana/grafana",
            name: "grafana",
            namespace: "grafana",
            description: "The open and composable observability and data visualization platform by Grafana Labs.",
            starCount: 3592,
            pullCount: 5375667716,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "13.2", "latest-slim", "13.2-slim"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3000, containerPort: 3000, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "grafana-storage", destination: "/var/lib/grafana", readOnly: false, volumeName: "grafana-storage")
            ],
            // Named volumes are ext4 images whose root directory belongs to root, and Grafana runs
            // as uid 472, so it cannot create /var/lib/grafana/plugins (verified on container 1.6.1:
            // "GF_PATHS_DATA='/var/lib/grafana' is not writable"). Run it as root instead.
            recommendedUser: "0:0",
            updatedAt: DockerHubService.hubDate("2026-10-27")
        ),
        DockerHubRepositoryItem(
            slug: "prom/prometheus",
            name: "prometheus",
            namespace: "prom",
            description: "Prometheus is a Cloud Native Computing Foundation systems and service monitoring system.",
            starCount: 2077,
            pullCount: 2038735419,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "v3", "v3.15.1"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 9090, containerPort: 9090, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "debian",
            name: "debian",
            description: "Debian is a Linux distribution that's composed entirely of free and open-source software.",
            starCount: 5326,
            pullCount: 1786270271,
            isOfficial: true,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["trixie-slim", "trixie", "bookworm-slim", "latest"],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "httpd",
            name: "httpd",
            description: "The Apache HTTP Server, the long-standing open-source web server.",
            starCount: 4932,
            pullCount: 4752242859,
            category: .webAndProxy,
            architectures: ["arm64", "amd64"],
            availableTags: ["2.4-alpine", "alpine", "2.4", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8082, containerPort: 80, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "httpd-htdocs", destination: "/usr/local/apache2/htdocs", readOnly: false, volumeName: "httpd-htdocs")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "mariadb",
            name: "mariadb",
            description: "MariaDB Server, a community-developed fork of MySQL with drop-in compatibility.",
            starCount: 6117,
            pullCount: 3240528951,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["11.8", "11.4", "lts", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3307, containerPort: 3306, proto: "tcp")
            ],
            recommendedEnv: [
                KeyValueEntry(key: "MARIADB_ROOT_PASSWORD", value: "change-me", isSecret: true),
                KeyValueEntry(key: "MARIADB_DATABASE", value: "appdb")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "mariadb-data", destination: "/var/lib/mysql", readOnly: false, volumeName: "mariadb-data")
            ],
            defaultCommand: ["--datadir=/var/lib/mysql/data"],
            updatedAt: DockerHubService.hubDate("2026-10-29")
        ),
        DockerHubRepositoryItem(
            slug: "clickhouse/clickhouse-server",
            name: "clickhouse-server",
            namespace: "clickhouse",
            description: "ClickHouse, a column-oriented database for real-time analytics (HTTP on 8123, native protocol on 9000).",
            starCount: 280,
            pullCount: 338145136,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .databases,
            architectures: ["arm64", "amd64"],
            availableTags: ["26.9", "26.8", "latest", "26.8-alpine"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8123, containerPort: 8123, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 9000, containerPort: 9000, proto: "tcp")
            ],
            recommendedEnv: [
                KeyValueEntry(key: "CLICKHOUSE_USER", value: "default"),
                KeyValueEntry(key: "CLICKHOUSE_PASSWORD", value: "change-me", isSecret: true),
                KeyValueEntry(key: "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT", value: "1")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "memcached",
            name: "memcached",
            description: "Memcached, a high-performance distributed in-memory key-value cache.",
            starCount: 2473,
            pullCount: 13430166063,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["1.6-alpine", "alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 11211, containerPort: 11211, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "valkey/valkey",
            name: "valkey",
            namespace: "valkey",
            description: "Valkey, the Linux Foundation's open-source (BSD) fork of Redis, wire-compatible with Redis clients.",
            starCount: 137,
            pullCount: 373849641,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["9.0-alpine", "8-alpine", "alpine", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 6380, containerPort: 6379, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "valkey-data", destination: "/data", readOnly: false, volumeName: "valkey-data")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "nats",
            name: "nats",
            description: "NATS, a lightweight messaging system for pub/sub, request/reply and streaming (JetStream).",
            starCount: 522,
            pullCount: 260407077,
            category: .cachingAndQueues,
            architectures: ["arm64", "amd64"],
            availableTags: ["2.15-alpine", "2.15", "latest", "alpine"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 4222, containerPort: 4222, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8222, containerPort: 8222, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-28")
        ),
        DockerHubRepositoryItem(
            slug: "php",
            name: "php",
            description: "PHP, a general-purpose scripting language for web development. The apache tags serve /var/www/html.",
            starCount: 7880,
            pullCount: 1394640402,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["8.4-apache", "8.4-fpm-alpine", "8.4-cli-alpine", "8.5-apache", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8083, containerPort: 80, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-31")
        ),
        DockerHubRepositoryItem(
            slug: "ruby",
            name: "ruby",
            description: "Ruby, a dynamic, open-source programming language focused on simplicity and productivity.",
            starCount: 2411,
            pullCount: 1588252674,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["3.4-alpine", "3.4-slim", "latest"],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "eclipse-temurin",
            name: "eclipse-temurin",
            description: "Eclipse Temurin, Adoptium's certified OpenJDK builds of Java (JRE and JDK). Starts idle; open the Terminal tab to run java.",
            starCount: 803,
            pullCount: 371442645,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["25-jre-alpine", "25-jre", "21-jre", "21-jdk", "latest"],
            defaultCommand: ["sleep", "infinity"],
            updatedAt: DockerHubService.hubDate("2026-11-01")
        ),
        DockerHubRepositoryItem(
            slug: "oven/bun",
            name: "bun",
            namespace: "oven",
            description: "Bun, an all-in-one JavaScript and TypeScript runtime, bundler, test runner and package manager. Starts idle; open the Terminal tab to run bun.",
            starCount: 302,
            pullCount: 69543352,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .languages,
            architectures: ["arm64", "amd64"],
            availableTags: ["1-alpine", "1.4-alpine", "1-slim", "latest"],
            defaultCommand: ["sleep", "infinity"],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "registry",
            name: "registry",
            description: "The CNCF Distribution registry: run a private OCI registry locally and push to it with `container image push`.",
            starCount: 4200,
            pullCount: 1787938092,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["3", "3.1", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 5000, containerPort: 5000, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "registry-data", destination: "/var/lib/registry", readOnly: false, volumeName: "registry-data")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-26")
        ),
        DockerHubRepositoryItem(
            slug: "hashicorp/vault",
            name: "vault",
            namespace: "hashicorp",
            description: "HashiCorp Vault in dev mode (in-memory, unsealed, for local development only) for secrets management.",
            starCount: 219,
            pullCount: 300973298,
            isOfficial: false,
            isVerifiedPublisher: true,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["2.2", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8200, containerPort: 8200, proto: "tcp")
            ],
            recommendedEnv: [
                KeyValueEntry(key: "VAULT_DEV_ROOT_TOKEN_ID", value: "change-me", isSecret: true),
                KeyValueEntry(key: "VAULT_DEV_LISTEN_ADDRESS", value: "0.0.0.0:8200")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-22")
        ),
        DockerHubRepositoryItem(
            slug: "gitea/gitea",
            name: "gitea",
            namespace: "gitea",
            description: "Gitea, a lightweight self-hosted Git service with web UI (3000) and SSH (2222).",
            starCount: 1063,
            pullCount: 393080750,
            isOfficial: false,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["28", "28-rootless", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 3000, containerPort: 3000, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 2222, containerPort: 22, proto: "tcp")
            ],
            recommendedVolumes: [
                MountAttachment(kind: .volume, source: "gitea-data", destination: "/data", readOnly: false, volumeName: "gitea-data")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-01")
        ),
        DockerHubRepositoryItem(
            slug: "axllent/mailpit",
            name: "mailpit",
            namespace: "axllent",
            description: "Mailpit, an email testing tool: SMTP on 1025 and a web inbox on 8025.",
            starCount: 123,
            pullCount: 236359629,
            isOfficial: false,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["v1", "v1.33", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8025, containerPort: 8025, proto: "tcp"),
                PortMapping(hostAddress: "127.0.0.1", hostPort: 1025, containerPort: 1025, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-11-02")
        ),
        DockerHubRepositoryItem(
            slug: "adminer",
            name: "adminer",
            description: "Adminer, a single-file web UI for managing MySQL, MariaDB, PostgreSQL and SQLite databases.",
            starCount: 979,
            pullCount: 409971366,
            category: .devOpsAndTools,
            architectures: ["arm64", "amd64"],
            availableTags: ["standalone", "5", "latest"],
            recommendedPorts: [
                PortMapping(hostAddress: "127.0.0.1", hostPort: 8084, containerPort: 8080, proto: "tcp")
            ],
            updatedAt: DockerHubService.hubDate("2026-10-29")
        ),
        DockerHubRepositoryItem(
            slug: "busybox",
            name: "busybox",
            description: "BusyBox, many common UNIX utilities in a single tiny executable.",
            starCount: 3525,
            pullCount: 12971899586,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["latest", "musl", "1.38-musl", "stable"],
            updatedAt: DockerHubService.hubDate("2026-10-30")
        ),
        DockerHubRepositoryItem(
            slug: "fedora",
            name: "fedora",
            description: "Fedora, the community Linux distribution sponsored by Red Hat.",
            starCount: 1268,
            pullCount: 138397126,
            category: .baseOS,
            architectures: ["arm64", "amd64"],
            availableTags: ["44", "43", "latest"],
            updatedAt: DockerHubService.hubDate("2026-08-26")
        )
    ]
}
