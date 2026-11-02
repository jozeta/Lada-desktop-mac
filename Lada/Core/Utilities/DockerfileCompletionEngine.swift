import Foundation

/// Context-aware Dockerfile completions for the editor: what fits at the cursor, given the
/// instruction on the current line and what the file already defines (build stages, ARG/ENV
/// names, earlier WORKDIRs and USERs). Pure, so it is unit-tested without a text view.
public enum DockerfileCompletionEngine {
    public static let instructions = [
        "FROM", "RUN", "CMD", "COPY", "ADD", "WORKDIR", "ENV", "ARG", "EXPOSE", "ENTRYPOINT",
        "VOLUME", "USER", "LABEL", "HEALTHCHECK", "SHELL", "STOPSIGNAL", "ONBUILD"
    ]

    /// Where the word being completed starts in `lineBeforeCursor` (UTF-16 offset, as NSTextView
    /// counts). Words end at whitespace; a `$` starts a new word so `"/app/${VE` completes `${VE`.
    public static func tokenStart(in lineBeforeCursor: String) -> Int {
        let units = Array(lineBeforeCursor.utf16)
        var i = units.count
        while i > 0 {
            let ch = units[i - 1]
            if ch == 0x20 || ch == 0x09 { break }          // space, tab
            if ch == 0x24 { i -= 1; break }                  // `$` belongs to the token
            i -= 1
        }
        return i
    }

    /// Suggestions that replace the token ending at the cursor.
    public static func suggestions(
        lineBeforeCursor: String,
        previousLine: String? = nil,
        document: String,
        localImages: [String] = [],
        catalog: [DockerHubRepositoryItem] = DockerHubService.curatedCatalog,
        limit: Int = 30
    ) -> [String] {
        let start = tokenStart(in: lineBeforeCursor)
        let utf16 = Array(lineBeforeCursor.utf16)
        let token = String(utf16CodeUnits: Array(utf16[start...]), count: utf16.count - start)
        let before = String(utf16CodeUnits: Array(utf16[..<start]), count: start)
        let words = before.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let facts = DocumentFacts(document)

        var candidates: [String]
        if token.hasPrefix("$") {
            candidates = facts.variables.flatMap { ["${\($0)}", "$\($0)"] }
        } else if words.isEmpty {
            // A continuation line (previous line ends in `\`) is still inside a shell command.
            let continues = previousLine?.trimmingCharacters(in: .whitespaces).hasSuffix("\\") ?? false
            candidates = continues ? [] : instructions
        } else {
            candidates = arguments(instruction: words[0].uppercased(), argumentsSoFar: Array(words.dropFirst()), token: token, facts: facts, localImages: localImages, catalog: catalog)
        }

        let needle = token.lowercased()
        var seen = Set<String>()
        let matches = candidates.filter { c in
            let lc = c.lowercased()
            return lc.hasPrefix(needle) && lc != needle && seen.insert(c).inserted
        }
        return Array(matches.prefix(limit))
    }

    // MARK: - Per instruction

    private static func arguments(
        instruction: String,
        argumentsSoFar args: [String],
        token: String,
        facts: DocumentFacts,
        localImages: [String],
        catalog: [DockerHubRepositoryItem]
    ) -> [String] {
        let positional = args.filter { !$0.hasPrefix("--") }
        switch instruction {
        case "FROM":
            if token.hasPrefix("-") { return ["--platform=linux/arm64", "--platform=linux/amd64", "--platform=$BUILDPLATFORM"] }
            if positional.isEmpty {
                let images = token.isEmpty
                    ? catalog.prefix(12).map { $0.imageReference(forTag: $0.availableTags.first ?? "latest") }
                    : ImageReferenceSuggester.suggestions(for: token, localReferences: localImages, catalog: catalog, limit: 20).map(\.reference)
                // Earlier stages can be built on too.
                return facts.stages + images.map(shortImage)
            }
            if positional.count == 1 { return ["AS"] }
            return []
        case "COPY", "ADD":
            if token.hasPrefix("-") {
                var flags = ["--chown=", "--chmod=", "--link"]
                if instruction == "COPY" { flags = facts.stages.map { "--from=\($0)" } + ["--from="] + flags }
                if instruction == "ADD" { flags += ["--checksum=", "--keep-git-dir=true"] }
                return flags
            }
            return []
        case "RUN":
            if token.hasPrefix("-") {
                return ["--mount=type=cache,target=", "--mount=type=secret,id=", "--mount=type=bind,source=,target=",
                        "--mount=type=ssh", "--network=none", "--network=default"]
            }
            if positional.isEmpty {
                return ["apt-get update && apt-get install -y --no-install-recommends", "apk add --no-cache",
                        "npm ci", "pip install --no-cache-dir -r requirements.txt", "go build -o /out/app ."]
            }
            return []
        case "WORKDIR":
            return facts.workdirs + ["/app", "/usr/src/app", "/srv", "/workspace"]
        case "USER":
            return facts.users + ["root", "nobody", "1000:1000", "node", "nginx"]
        case "EXPOSE":
            return ["80/tcp", "443/tcp", "3000/tcp", "5000/tcp", "8000/tcp", "8080/tcp", "5432/tcp", "3306/tcp", "6379/tcp", "27017/tcp", "53/udp"]
        case "ENV":
            return ["PATH=", "NODE_ENV=production", "PYTHONUNBUFFERED=1", "PYTHONDONTWRITEBYTECODE=1", "TZ=UTC", "LANG=C.UTF-8", "PORT="]
        case "ARG":
            return ["TARGETPLATFORM", "TARGETOS", "TARGETARCH", "BUILDPLATFORM", "VERSION="]
        case "HEALTHCHECK":
            return ["--interval=30s", "--timeout=5s", "--start-period=10s", "--retries=3", "CMD", "NONE"]
        case "STOPSIGNAL":
            return ["SIGTERM", "SIGINT", "SIGQUIT", "SIGKILL"]
        case "SHELL":
            return ["[\"/bin/sh\", \"-c\"]", "[\"/bin/bash\", \"-o\", \"pipefail\", \"-c\"]"]
        case "CMD", "ENTRYPOINT":
            return positional.isEmpty ? ["[\"", "[\"/bin/sh\", \"-c\", \"\"]"] : []
        case "VOLUME":
            return ["[\"/data\"]", "/data", "/var/lib/data"]
        case "LABEL":
            return ["org.opencontainers.image.title=", "org.opencontainers.image.description=", "org.opencontainers.image.source=",
                    "org.opencontainers.image.version=", "org.opencontainers.image.licenses=", "maintainer="]
        case "ONBUILD":
            return positional.isEmpty ? instructions.filter { $0 != "ONBUILD" && $0 != "FROM" } : []
        default:
            return []
        }
    }

    /// `docker.io/library/nginx:1.27` → `nginx:1.27`, as people write it in a Dockerfile.
    static func shortImage(_ reference: String) -> String {
        for prefix in ["docker.io/library/", "docker.io/"] where reference.hasPrefix(prefix) {
            return String(reference.dropFirst(prefix.count))
        }
        return reference
    }

    /// What the file defines so far.
    struct DocumentFacts {
        var stages: [String] = []
        var variables: [String] = []
        var workdirs: [String] = []
        var users: [String] = []

        init(_ document: String) {
            for raw in document.split(separator: "\n", omittingEmptySubsequences: false) {
                let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard let first = parts.first?.uppercased() else { continue }
                switch first {
                case "FROM":
                    if let asIndex = parts.firstIndex(where: { $0.uppercased() == "AS" }), asIndex + 1 < parts.count {
                        add(parts[asIndex + 1], to: &stages)
                    }
                case "ARG":
                    if parts.count > 1 { add(Self.name(parts[1]), to: &variables) }
                case "ENV":
                    // `ENV A=1 B=2` or the legacy `ENV A 1`.
                    let rest = parts.dropFirst()
                    if rest.contains(where: { $0.contains("=") }) {
                        for p in rest where p.contains("=") { add(Self.name(p), to: &variables) }
                    } else if let p = rest.first {
                        add(p, to: &variables)
                    }
                case "WORKDIR":
                    if parts.count > 1 { add(parts[1], to: &workdirs) }
                case "USER":
                    if parts.count > 1 { add(parts[1], to: &users) }
                default:
                    break
                }
            }
        }

        private static func name(_ assignment: String) -> String {
            String(assignment.split(separator: "=", maxSplits: 1).first ?? "")
        }

        private func add(_ value: String, to list: inout [String]) {
            guard !value.isEmpty, !list.contains(value) else { return }
            list.append(value)
        }

    }
}
