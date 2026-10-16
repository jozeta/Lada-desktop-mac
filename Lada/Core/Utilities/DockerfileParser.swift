import Foundation

public struct ParsedDockerfile: Sendable, Equatable {
    public var baseImage: String
    public var platform: String
    public var suggestedContainerName: String
    public var exposedPorts: [PortMapping]
    public var environmentVariables: [KeyValueEntry]
    public var workingDirectory: String
    public var userSpec: String
    public var entrypointOverride: String
    public var commandArguments: [String]
    public var mounts: [MountAttachment]
    public var labels: [KeyValueEntry]
    public var buildArgs: [KeyValueEntry]
    public var stages: [String]
    public var hasBuildInstructions: Bool
    public var rawContent: String
    public var sourceFilePath: String?
    public var contextDirectory: String?

    public init(
        baseImage: String = "alpine:latest",
        platform: String = "",
        suggestedContainerName: String = "",
        exposedPorts: [PortMapping] = [],
        environmentVariables: [KeyValueEntry] = [],
        workingDirectory: String = "",
        userSpec: String = "",
        entrypointOverride: String = "",
        commandArguments: [String] = [],
        mounts: [MountAttachment] = [],
        labels: [KeyValueEntry] = [],
        buildArgs: [KeyValueEntry] = [],
        stages: [String] = [],
        hasBuildInstructions: Bool = false,
        rawContent: String = "",
        sourceFilePath: String? = nil,
        contextDirectory: String? = nil
    ) {
        self.baseImage = baseImage
        self.platform = platform
        self.suggestedContainerName = suggestedContainerName
        self.exposedPorts = exposedPorts
        self.environmentVariables = environmentVariables
        self.workingDirectory = workingDirectory
        self.userSpec = userSpec
        self.entrypointOverride = entrypointOverride
        self.commandArguments = commandArguments
        self.mounts = mounts
        self.labels = labels
        self.buildArgs = buildArgs
        self.stages = stages
        self.hasBuildInstructions = hasBuildInstructions
        self.rawContent = rawContent
        self.sourceFilePath = sourceFilePath
        self.contextDirectory = contextDirectory
    }
}

public enum DockerfileParser {
    /// Parses a Dockerfile or Containerfile text and extracts container configuration metadata.
    public static func parse(
        content: String,
        sourceFileURL: URL? = nil
    ) -> ParsedDockerfile {
        let logicalLines = joinContinuationLines(content)

        var baseImage = "alpine:latest"
        var platform = ""
        var exposedPorts: [PortMapping] = []
        var envVars: [KeyValueEntry] = []
        var workingDirectory = ""
        var userSpec = ""
        var entrypointOverride = ""
        var commandArguments: [String] = []
        var mounts: [MountAttachment] = []
        var labels: [KeyValueEntry] = []
        var buildArgs: [KeyValueEntry] = []
        var stages: [String] = []
        var hasBuildInstructions = false

        for rawLine in logicalLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let firstWord = parts.first else { continue }
            let instruction = firstWord.uppercased()
            let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

            switch instruction {
            case "FROM":
                let tokens = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                var imageCandidate: String? = nil
                var i = 0
                while i < tokens.count {
                    let tok = tokens[i]
                    if tok.lowercased().hasPrefix("--platform=") {
                        platform = String(tok.dropFirst("--platform=".count))
                    } else if tok.uppercased() == "AS", i + 1 < tokens.count {
                        stages.append(tokens[i + 1])
                        hasBuildInstructions = true
                        break
                    } else if !tok.hasPrefix("--") && imageCandidate == nil {
                        imageCandidate = tok
                    }
                    i += 1
                }
                if let img = imageCandidate, img.lowercased() != "scratch" {
                    baseImage = img
                }

            case "RUN", "COPY", "ADD":
                hasBuildInstructions = true

            case "WORKDIR":
                if !rest.isEmpty {
                    workingDirectory = unquote(rest)
                }

            case "USER":
                if !rest.isEmpty {
                    userSpec = unquote(rest)
                }

            case "EXPOSE":
                let portTokens = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                for token in portTokens {
                    let sub = token.split(separator: "/")
                    let numPart = String(sub[0])
                    let proto = sub.count > 1 ? String(sub[1]).lowercased() : "tcp"
                    if let cPort = UInt16(numPart), cPort > 0 {
                        // Map privileged container ports (<1024) to high host port (e.g. 80 -> 8080, 443 -> 8443)
                        let hPort: UInt16
                        if cPort == 80 {
                            hPort = 8080
                        } else if cPort == 443 {
                            hPort = 8443
                        } else if cPort < 1024 {
                            hPort = cPort + 8000
                        } else {
                            hPort = cPort
                        }
                        if !exposedPorts.contains(where: { $0.containerPort == cPort && $0.proto == proto }) {
                            exposedPorts.append(
                                PortMapping(
                                    hostAddress: "127.0.0.1",
                                    hostPort: hPort,
                                    containerPort: cPort,
                                    proto: proto
                                )
                            )
                        }
                    }
                }

            case "ENV":
                let parsedPairs = parseKeyValueInstruction(rest)
                for (k, v) in parsedPairs where !k.isEmpty {
                    if let existingIdx = envVars.firstIndex(where: { $0.key == k }) {
                        envVars[existingIdx].value = v
                    } else {
                        envVars.append(KeyValueEntry(key: k, value: v, isSecret: SecretRedactor.isSensitiveKey(k)))
                    }
                }

            case "ARG":
                let parsedPairs = parseKeyValueInstruction(rest)
                for (k, v) in parsedPairs where !k.isEmpty {
                    buildArgs.append(KeyValueEntry(key: k, value: v, isSecret: SecretRedactor.isSensitiveKey(k)))
                }

            case "LABEL":
                let parsedPairs = parseKeyValueInstruction(rest)
                for (k, v) in parsedPairs where !k.isEmpty {
                    labels.append(KeyValueEntry(key: k, value: v))
                    if (k == "lada.mount" || k == "lada.bind_mount" || k == "bind.mount"),
                       v.contains(":") {
                        let parts = v.split(separator: ":", maxSplits: 1).map(String.init)
                        if parts.count == 2, parts[0].hasPrefix("/"), parts[1].hasPrefix("/") {
                            let hostSource = parts[0]
                            let containerDest = parts[1]
                            mounts.removeAll { $0.destination == containerDest }
                            mounts.append(
                                MountAttachment(
                                    kind: .bind,
                                    source: hostSource,
                                    destination: containerDest,
                                    readOnly: false
                                )
                            )
                        }
                    }
                }

            case "VOLUME":
                let paths = parseStringArrayOrSpaceSeparated(rest)
                for spec in paths {
                    if spec.contains(":") {
                        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
                        if parts.count == 2, parts[0].hasPrefix("/"), parts[1].hasPrefix("/") {
                            let hostSource = parts[0]
                            let containerDest = parts[1]
                            mounts.removeAll { $0.destination == containerDest }
                            mounts.append(
                                MountAttachment(
                                    kind: .bind,
                                    source: hostSource,
                                    destination: containerDest,
                                    readOnly: false
                                )
                            )
                            continue
                        }
                    }
                    guard spec.hasPrefix("/") else { continue }
                    let destination = spec
                    let cleanLeaf = URL(fileURLWithPath: destination).lastPathComponent
                        .lowercased()
                        .replacingOccurrences(of: "[^a-z0-9_.-]", with: "-", options: .regularExpression)
                    let volName = cleanLeaf.isEmpty ? "app-data" : "\(cleanLeaf)-vol"
                    if !mounts.contains(where: { $0.destination == destination }) {
                        mounts.append(
                            MountAttachment(
                                kind: .volume,
                                source: volName,
                                destination: destination,
                                readOnly: false,
                                volumeName: volName
                            )
                        )
                    }
                }

            case "ENTRYPOINT":
                let arr = parseStringArrayOrSpaceSeparated(rest)
                if let first = arr.first {
                    entrypointOverride = first
                    let extra = Array(arr.dropFirst())
                    commandArguments = extra
                }

            case "CMD":
                let arr = parseStringArrayOrSpaceSeparated(rest)
                if !arr.isEmpty {
                    if !entrypointOverride.isEmpty && !commandArguments.isEmpty {
                        commandArguments.append(contentsOf: arr)
                    } else {
                        commandArguments = arr
                    }
                }

            default:
                break
            }
        }

        // Determine suggested container name
        var suggestedName = ""
        if let titleLabel = labels.first(where: {
            $0.key == "org.opencontainers.image.title" || $0.key == "name"
        })?.value, !titleLabel.isEmpty {
            suggestedName = titleLabel
        } else if let fileURL = sourceFileURL {
            let fileName = fileURL.lastPathComponent.lowercased()
            if fileName == "dockerfile" || fileName == "containerfile" {
                suggestedName = fileURL.deletingLastPathComponent().lastPathComponent
            } else {
                suggestedName = fileURL.deletingPathExtension().lastPathComponent
            }
        }
        if suggestedName.isEmpty || suggestedName == "/" || suggestedName == "tmp" {
            let repoPart = baseImage.split(separator: ":").first.map(String.init) ?? "app"
            suggestedName = repoPart.split(separator: "/").last.map(String.init) ?? "app"
        }
        suggestedName = sanitizeContainerName(suggestedName)

        let sourcePath = sourceFileURL?.path
        let contextDir = sourceFileURL?.deletingLastPathComponent().path

        return ParsedDockerfile(
            baseImage: baseImage,
            platform: platform,
            suggestedContainerName: suggestedName,
            exposedPorts: exposedPorts,
            environmentVariables: envVars,
            workingDirectory: workingDirectory,
            userSpec: userSpec,
            entrypointOverride: entrypointOverride,
            commandArguments: commandArguments,
            mounts: mounts,
            labels: labels,
            buildArgs: buildArgs,
            stages: stages,
            hasBuildInstructions: hasBuildInstructions,
            rawContent: content,
            sourceFilePath: sourcePath,
            contextDirectory: contextDir
        )
    }

    /// Converts a Dockerfile or Containerfile directly into a pre-populated `ContainerCreateRequest`.
    public static func buildContainerCreateRequest(
        content: String,
        sourceFileURL: URL? = nil,
        defaultCPUs: Int = 4,
        defaultMemoryMB: Int = 1024
    ) -> ContainerCreateRequest {
        let parsed = parse(content: content, sourceFileURL: sourceFileURL)
        let generatedImageTag = parsed.hasBuildInstructions
            ? "local/\(parsed.suggestedContainerName.isEmpty ? "dockerfile-app" : parsed.suggestedContainerName):latest"
            : parsed.baseImage

        return ContainerCreateRequest(
            name: parsed.suggestedContainerName,
            imageReference: generatedImageTag,
            startImmediately: true,
            entrypointOverride: parsed.entrypointOverride,
            commandArguments: parsed.commandArguments,
            workingDirectory: parsed.workingDirectory,
            userSpec: parsed.userSpec,
            publishedPorts: parsed.exposedPorts,
            mounts: parsed.mounts,
            environmentVariables: parsed.environmentVariables,
            cpus: defaultCPUs,
            memoryMB: defaultMemoryMB,
            platform: parsed.platform,
            labels: parsed.labels,
            dockerfileContent: content,
            dockerfileSourcePath: parsed.sourceFilePath,
            dockerfileContextDirectory: parsed.contextDirectory,
            buildFromDockerfileBeforeRun: parsed.hasBuildInstructions,
            dockerfileBaseImage: parsed.baseImage
        )
    }

    // MARK: - Helpers

    private static func joinContinuationLines(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmedRight = rawLine.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if trimmedRight.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                continue
            }
            if trimmedRight.hasSuffix("\\") {
                let withoutSlash = String(trimmedRight.dropLast()).trimmingCharacters(in: .whitespaces)
                current += (current.isEmpty ? "" : " ") + withoutSlash
            } else {
                current += (current.isEmpty ? "" : " ") + trimmedRight.trimmingCharacters(in: .whitespaces)
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func parseKeyValueInstruction(_ rest: String) -> [(String, String)] {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // If no '=' in the line, handle legacy `ENV KEY VALUE` syntax
        if !trimmed.contains("=") {
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let k = parts.first else { return [] }
            let v = parts.count > 1 ? unquote(String(parts[1])) : ""
            return [(String(k), v)]
        }

        // Parse one or more KEY=VALUE or KEY="VALUE WITH SPACES" pairs
        var pairs: [(String, String)] = []
        let pattern = #"([A-Za-z0-9_.-]+)=("[^"]*"|'[^']*'|[^\s]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            for match in matches {
                if let kRange = Range(match.range(at: 1), in: trimmed),
                   let vRange = Range(match.range(at: 2), in: trimmed) {
                    let key = String(trimmed[kRange])
                    let val = unquote(String(trimmed[vRange]))
                    pairs.append((key, val))
                }
            }
        }
        return pairs
    }

    private static func parseStringArrayOrSpaceSeparated(_ rest: String) -> [String] {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]"),
           let data = trimmed.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr
        }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map { unquote(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ value: String) -> String {
        let t = value.trimmingCharacters(in: .whitespaces)
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")), t.count >= 2 {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    private static func sanitizeContainerName(_ raw: String) -> String {
        let cleaned = raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_.-]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^[-._]+|[-._]+$", with: "", options: .regularExpression)
        if cleaned.isEmpty {
            return "container-app"
        }
        return String(cleaned.prefix(50))
    }
}
