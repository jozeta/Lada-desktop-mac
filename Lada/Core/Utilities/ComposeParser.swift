import Foundation

// MARK: - Compose Stack Models

public struct ComposeServiceSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: String { serviceName }
    public var serviceName: String
    public var containerName: String
    public var imageReference: String
    public var buildContext: String?
    public var publishedPorts: [PortMapping]
    public var environment: [KeyValueEntry]
    public var volumes: [MountAttachment]
    public var commandOverride: String
    public var workingDirectory: String
    public var dependsOn: [String]
    public var networks: [String]

    public init(
        serviceName: String,
        containerName: String,
        imageReference: String,
        buildContext: String? = nil,
        publishedPorts: [PortMapping] = [],
        environment: [KeyValueEntry] = [],
        volumes: [MountAttachment] = [],
        commandOverride: String = "",
        workingDirectory: String = "",
        dependsOn: [String] = [],
        networks: [String] = []
    ) {
        self.serviceName = serviceName
        self.containerName = containerName
        self.imageReference = imageReference
        self.buildContext = buildContext
        self.publishedPorts = publishedPorts
        self.environment = environment
        self.volumes = volumes
        self.commandOverride = commandOverride
        self.workingDirectory = workingDirectory
        self.dependsOn = dependsOn
        self.networks = networks
    }
}

public struct ParsedComposeStack: Sendable, Equatable {
    public var projectName: String
    public var services: [ComposeServiceSpec]
    public var declaredNetworks: [String]
    public var declaredVolumes: [String]
    public var warnings: [String]

    public init(
        projectName: String,
        services: [ComposeServiceSpec] = [],
        declaredNetworks: [String] = [],
        declaredVolumes: [String] = [],
        warnings: [String] = []
    ) {
        self.projectName = projectName
        self.services = services
        self.declaredNetworks = declaredNetworks
        self.declaredVolumes = declaredVolumes
        self.warnings = warnings
    }

    /// Returns services ordered topologically so dependencies (`depends_on`) start first.
    public var topologicalServices: [ComposeServiceSpec] {
        var visited = Set<String>()
        var result: [ComposeServiceSpec] = []
        let map = Dictionary(uniqueKeysWithValues: services.map { ($0.serviceName, $0) })

        func visit(_ name: String) {
            guard !visited.contains(name), let svc = map[name] else { return }
            visited.insert(name)
            for dep in svc.dependsOn {
                visit(dep)
            }
            result.append(svc)
        }

        for svc in services {
            visit(svc.serviceName)
        }
        return result
    }
}

// MARK: - Starter Compose Templates

public struct ComposeStackTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let projectName: String
    public let yamlContent: String

    public static let allTemplates: [ComposeStackTemplate] = [
        ComposeStackTemplate(
            id: "web-postgres-redis",
            title: "Web App + PostgreSQL + Redis",
            subtitle: "3-tier web stack with Nginx frontend, PostgreSQL 16 database, and Redis 7 cache",
            projectName: "nordic-web",
            yamlContent: """
            name: nordic-web

            services:
              db:
                image: docker.io/library/postgres:16-alpine
                container_name: nordic-postgres
                ports:
                  - "5432:5432"
                environment:
                  POSTGRES_USER: lada
                  POSTGRES_PASSWORD: lada_secret_password
                  POSTGRES_DB: lada_app
                  PGDATA: /var/lib/postgresql/data/pgdata
                volumes:
                  - pgdata:/var/lib/postgresql/data

              redis:
                image: docker.io/library/redis:7-alpine
                container_name: nordic-redis
                ports:
                  - "6379:6379"

              web:
                image: docker.io/library/nginx:1.27-alpine
                container_name: nordic-frontend
                ports:
                  - "8088:80"
                depends_on:
                  - db
                  - redis

            volumes:
              pgdata:
            """
        ),
        ComposeStackTemplate(
            id: "wordpress-mysql",
            title: "WordPress + MySQL 8.4 CMS",
            subtitle: "Complete WordPress publishing stack backed by MySQL 8.4 with persistent volumes",
            projectName: "wp-studio",
            yamlContent: """
            name: wp-studio

            services:
              mysql:
                image: docker.io/library/mysql:8.4
                container_name: wp-mysql
                command: --datadir=/var/lib/mysql/data
                ports:
                  - "3306:3306"
                environment:
                  MYSQL_ROOT_PASSWORD: root_secret_password
                  MYSQL_DATABASE: wordpress
                  MYSQL_USER: wp_user
                  MYSQL_PASSWORD: wp_password
                volumes:
                  - wp_db:/var/lib/mysql

              wordpress:
                image: docker.io/library/nginx:1.27-alpine
                container_name: wp-web
                ports:
                  - "8085:80"
                environment:
                  WORDPRESS_DB_HOST: wp-mysql:3306
                  WORDPRESS_DB_USER: wp_user
                  WORDPRESS_DB_PASSWORD: wp_password
                  WORDPRESS_DB_NAME: wordpress
                depends_on:
                  - mysql

            volumes:
              wp_db:
            """
        ),
        ComposeStackTemplate(
            id: "observability-prometheus-grafana",
            title: "Prometheus + Grafana Telemetry",
            subtitle: "Metrics collection and visualization dashboard stack on ports 9090 and 3001",
            projectName: "telemetry",
            yamlContent: """
            name: telemetry

            services:
              prometheus:
                image: docker.io/prom/prometheus:latest
                container_name: telemetry-prometheus
                ports:
                  - "9090:9090"

              grafana:
                image: docker.io/grafana/grafana:latest
                container_name: telemetry-grafana
                ports:
                  - "3001:3000"
                environment:
                  GF_SECURITY_ADMIN_USER: admin
                  GF_SECURITY_ADMIN_PASSWORD: lada_admin
                depends_on:
                  - prometheus
            """
        ),
        ComposeStackTemplate(
            id: "python-api-redis",
            title: "Python Microservice + Redis Queue",
            subtitle: "Python 3.12 HTTP API service paired with Redis in-memory store",
            projectName: "py-stack",
            yamlContent: """
            name: py-stack

            services:
              cache:
                image: docker.io/library/redis:7-alpine
                container_name: py-redis
                ports:
                  - "6380:6379"

              api:
                image: docker.io/library/python:3.12-slim
                container_name: py-api
                working_dir: /app
                command: python3 -m http.server 8000
                ports:
                  - "8000:8000"
                environment:
                  REDIS_URL: redis://py-redis:6379/0
                  PYTHONUNBUFFERED: "1"
                depends_on:
                  - cache
            """
        )
    ]
}

// MARK: - Compose YAML Parser

public enum ComposeParser {
    public static func isComposeFile(url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "docker-compose.yml"
            || name == "docker-compose.yaml"
            || name == "compose.yml"
            || name == "compose.yaml"
            || name.hasSuffix(".compose.yml")
            || name.hasSuffix(".compose.yaml")
    }

    public static func isComposeContent(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        return lines.contains {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed == "services:" || trimmed.hasPrefix("services:")
        }
    }

    public static func parse(yaml: String, defaultProjectName: String = "stack") -> ParsedComposeStack {
        var projectName = defaultProjectName
        var services: [ComposeServiceSpec] = []
        var declaredNetworks: [String] = []
        var declaredVolumes: [String] = []
        var warnings: [String] = []

        enum TopSection {
            case none
            case services
            case networks
            case volumes
        }

        enum ServiceSubsection {
            case none
            case ports
            case environment
            case volumes
            case dependsOn
            case networks
        }

        var topSection: TopSection = .none
        var currentService: ComposeServiceSpec? = nil
        var subSection: ServiceSubsection = .none

        func flushCurrentService() {
            guard var svc = currentService else { return }
            if svc.imageReference.isEmpty {
                svc.imageReference = "docker.io/library/alpine:latest"
                warnings.append("Service '\(svc.serviceName)' had no 'image:' field; defaulted to alpine:latest.")
            } else if !svc.imageReference.contains("/") {
                svc.imageReference = "docker.io/library/\(svc.imageReference)"
            }
            // Apply Apple container ext4 compatibility defaults for Postgres/MySQL when mounted
            if svc.imageReference.lowercased().contains("postgres") {
                let hasPGData = svc.environment.contains { $0.key.uppercased() == "PGDATA" }
                if !hasPGData {
                    svc.environment.append(KeyValueEntry(key: "PGDATA", value: "/var/lib/postgresql/data/pgdata"))
                }
            }
            if svc.imageReference.lowercased().contains("mysql") && svc.commandOverride.isEmpty {
                svc.commandOverride = "--datadir=/var/lib/mysql/data"
            }
            services.append(svc)
            currentService = nil
        }

        let rawLines = yaml.components(separatedBy: .newlines)
        for rawLine in rawLines {
            let commentStripped: String = {
                if let hashIdx = rawLine.range(of: " #")?.lowerBound {
                    return String(rawLine[..<hashIdx])
                }
                return rawLine
            }()
            let trimmed = commentStripped.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" {
                continue
            }

            let indent = commentStripped.prefix(while: { $0 == " " || $0 == "\t" }).count

            // Top-level keys (indent == 0)
            if indent == 0 {
                flushCurrentService()
                subSection = .none
                if trimmed.hasPrefix("name:") {
                    let val = unquote(trimmed.dropFirst("name:".count))
                    if !val.isEmpty { projectName = sanitizeIdentifier(val) }
                    topSection = .none
                } else if trimmed == "services:" || trimmed.hasPrefix("services:") {
                    topSection = .services
                } else if trimmed == "networks:" || trimmed.hasPrefix("networks:") {
                    topSection = .networks
                } else if trimmed == "volumes:" || trimmed.hasPrefix("volumes:") {
                    topSection = .volumes
                } else {
                    topSection = .none
                }
                continue
            }

            switch topSection {
            case .networks:
                if indent <= 4, trimmed.hasSuffix(":") {
                    let netName = unquote(trimmed.dropLast())
                    if !netName.isEmpty && !declaredNetworks.contains(netName) {
                        declaredNetworks.append(netName)
                    }
                }
            case .volumes:
                if indent <= 4, trimmed.hasSuffix(":") {
                    let volName = unquote(trimmed.dropLast())
                    if !volName.isEmpty && !declaredVolumes.contains(volName) {
                        declaredVolumes.append(volName)
                    }
                }
            case .services:
                // Service header (typically indent == 2)
                if indent == 2 && trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") {
                    flushCurrentService()
                    subSection = .none
                    let svcName = sanitizeIdentifier(unquote(trimmed.dropLast()))
                    currentService = ComposeServiceSpec(
                        serviceName: svcName,
                        containerName: "\(projectName)-\(svcName)",
                        imageReference: ""
                    )
                    continue
                }

                guard currentService != nil else { continue }

                // Service properties (typically indent == 4)
                if indent == 4 && !trimmed.hasPrefix("-") {
                    subSection = .none
                    if let colonIndex = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                        let val = unquote(trimmed[trimmed.index(after: colonIndex)...])

                        switch key {
                        case "image":
                            currentService?.imageReference = val
                        case "container_name":
                            if !val.isEmpty {
                                currentService?.containerName = sanitizeIdentifier(val)
                            }
                        case "build":
                            if !val.isEmpty {
                                currentService?.buildContext = val
                            }
                        case "command":
                            currentService?.commandOverride = val
                        case "working_dir":
                            currentService?.workingDirectory = val
                        case "ports":
                            subSection = .ports
                        case "environment":
                            subSection = .environment
                        case "volumes":
                            subSection = .volumes
                        case "depends_on":
                            subSection = .dependsOn
                        case "networks":
                            subSection = .networks
                        default:
                            break
                        }
                    }
                    continue
                }

                // Subsection items (indent >= 4)
                switch subSection {
                case .ports:
                    if trimmed.hasPrefix("-") {
                        let spec = unquote(trimmed.dropFirst())
                        if let pm = parsePortSpec(spec) {
                            currentService?.publishedPorts.append(pm)
                        }
                    }
                case .environment:
                    if trimmed.hasPrefix("-") {
                        let item = unquote(trimmed.dropFirst())
                        if let eq = item.firstIndex(of: "=") {
                            let k = String(item[..<eq]).trimmingCharacters(in: .whitespaces)
                            let v = unquote(item[item.index(after: eq)...])
                            currentService?.environment.append(KeyValueEntry(key: k, value: v, isSecret: SecretRedactor.isSensitiveKey(k)))
                        }
                    } else if let colon = trimmed.firstIndex(of: ":") {
                        let k = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                        let v = unquote(trimmed[trimmed.index(after: colon)...])
                        currentService?.environment.append(KeyValueEntry(key: k, value: v, isSecret: SecretRedactor.isSensitiveKey(k)))
                    }
                case .volumes:
                    if trimmed.hasPrefix("-") {
                        let spec = unquote(trimmed.dropFirst())
                        if let mount = parseVolumeSpec(spec, projectName: projectName) {
                            currentService?.volumes.append(mount)
                            if mount.kind == .volume && !declaredVolumes.contains(mount.source) {
                                declaredVolumes.append(mount.source)
                            }
                        }
                    }
                case .dependsOn:
                    if trimmed.hasPrefix("-") {
                        let dep = sanitizeIdentifier(unquote(trimmed.dropFirst()))
                        if !dep.isEmpty {
                            currentService?.dependsOn.append(dep)
                        }
                    } else if indent == 6 && trimmed.hasSuffix(":") {
                        let dep = sanitizeIdentifier(unquote(trimmed.dropLast()))
                        if !dep.isEmpty {
                            currentService?.dependsOn.append(dep)
                        }
                    }
                case .networks:
                    if trimmed.hasPrefix("-") {
                        let net = sanitizeIdentifier(unquote(trimmed.dropFirst()))
                        if !net.isEmpty {
                            currentService?.networks.append(net)
                        }
                    }
                case .none:
                    break
                }
            case .none:
                break
            }
        }

        flushCurrentService()
        return ParsedComposeStack(
            projectName: projectName,
            services: services,
            declaredNetworks: declaredNetworks,
            declaredVolumes: declaredVolumes,
            warnings: warnings
        )
    }

    public static func buildContainerRequest(
        for service: ComposeServiceSpec,
        projectName: String,
        networkName: String,
        defaultCPUs: Int,
        defaultMemoryMB: Int
    ) -> ContainerCreateRequest {
        var cmdArgs: [String] = []
        var entryOverride = ""
        let trimmedCmd = service.commandOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCmd.isEmpty {
            let parts = trimmedCmd.split(separator: " ").map(String.init)
            if let first = parts.first {
                if first.hasPrefix("-") {
                    // Passed as arguments to the image's default entrypoint (e.g. `--datadir=/var/lib/mysql/data`)
                    cmdArgs = parts
                } else {
                    entryOverride = first
                    cmdArgs = Array(parts.dropFirst())
                }
            }
        }

        return ContainerCreateRequest(
            name: service.containerName,
            imageReference: service.imageReference,
            startImmediately: true,
            entrypointOverride: entryOverride,
            commandArguments: cmdArgs,
            workingDirectory: service.workingDirectory,
            publishedPorts: service.publishedPorts,
            networkName: networkName,
            mounts: service.volumes,
            environmentVariables: service.environment,
            cpus: defaultCPUs,
            memoryMB: defaultMemoryMB,
            labels: [
                KeyValueEntry(key: "com.lada.compose.project", value: projectName),
                KeyValueEntry(key: "com.lada.compose.service", value: service.serviceName)
            ]
        )
    }

    private static func parsePortSpec(_ raw: String) -> PortMapping? {
        var proto = "tcp"
        var cleaned = raw
        if cleaned.lowercased().hasSuffix("/udp") {
            proto = "udp"
            cleaned = String(cleaned.dropLast(4))
        } else if cleaned.lowercased().hasSuffix("/tcp") {
            proto = "tcp"
            cleaned = String(cleaned.dropLast(4))
        }
        let segments = cleaned.split(separator: ":").map(String.init)
        if segments.count == 2,
           let hostPort = UInt16(segments[0]),
           let containerPort = UInt16(segments[1]) {
            return PortMapping(hostAddress: "127.0.0.1", hostPort: hostPort, containerPort: containerPort, proto: proto)
        } else if segments.count == 3,
                  let hostPort = UInt16(segments[1]),
                  let containerPort = UInt16(segments[2]) {
            return PortMapping(hostAddress: segments[0], hostPort: hostPort, containerPort: containerPort, proto: proto)
        } else if segments.count == 1,
                  let port = UInt16(segments[0]) {
            return PortMapping(hostAddress: "127.0.0.1", hostPort: port, containerPort: port, proto: proto)
        }
        return nil
    }

    private static func parseVolumeSpec(_ raw: String, projectName: String) -> MountAttachment? {
        let parts = raw.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let src = parts[0]
        let dst = parts[1]
        let ro = parts.count >= 3 && parts[2].lowercased().contains("ro")
        if src.hasPrefix("/") || src.hasPrefix("./") || src.hasPrefix("../") || src.hasPrefix("~") {
            let expanded = (src as NSString).expandingTildeInPath
            return MountAttachment(kind: .bind, source: expanded, destination: dst, readOnly: ro)
        } else {
            return MountAttachment(kind: .volume, source: src, destination: dst, readOnly: ro, volumeName: src)
        }
    }

    private static func unquote<S: StringProtocol>(_ s: S) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            if t.count >= 2 {
                t.removeFirst()
                t.removeLast()
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeIdentifier(_ raw: String) -> String {
        let allowed = raw.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." {
                return ch
            }
            return "-"
        }
        let cleaned = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        if cleaned.count < 2 {
            return cleaned.isEmpty ? "stack-svc" : "\(cleaned)01"
        }
        return cleaned
    }
}
