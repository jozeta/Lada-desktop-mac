import Foundation

/// Edits a docker-compose.yml one service at a time, so the Stacks form and the text editor stay
/// in sync: adding, changing or removing a service rewrites only that service's block (and adds
/// missing top-level volumes); the rest of the file, including comments, stays as written.
public enum ComposeDocument {
    // MARK: - Serialization

    /// YAML lines (indented for the `services:` section) for one service, in the subset that
    /// `ComposeParser` reads back.
    public static func serviceBlock(_ svc: ComposeServiceSpec, projectName: String) -> String {
        var lines = ["  \(svc.serviceName):"]
        if let build = svc.buildContext, !build.isEmpty { lines.append("    build: \(quoted(build))") }
        if !svc.imageReference.isEmpty { lines.append("    image: \(svc.imageReference)") }
        if !svc.containerName.isEmpty && svc.containerName != "\(projectName)-\(svc.serviceName)" {
            lines.append("    container_name: \(svc.containerName)")
        }
        let command = svc.commandOverride.trimmingCharacters(in: .whitespaces)
        if !command.isEmpty { lines.append("    command: \(quoted(command))") }
        if let cpus = svc.cpuLimit { lines.append("    cpus: \(cpus)") }
        if let mb = svc.memoryLimitMB { lines.append("    mem_limit: \(mb % 1024 == 0 ? "\(mb / 1024)g" : "\(mb)m")") }
        let workdir = svc.workingDirectory.trimmingCharacters(in: .whitespaces)
        if !workdir.isEmpty { lines.append("    working_dir: \(quoted(workdir))") }
        if !svc.publishedPorts.isEmpty {
            lines.append("    ports:")
            for p in svc.publishedPorts {
                let host = p.hostAddress.isEmpty || p.hostAddress == "127.0.0.1" ? "\(p.hostPort)" : "\(p.hostAddress):\(p.hostPort)"
                lines.append("      - \"\(host):\(p.containerPort)\(p.proto == "udp" ? "/udp" : "")\"")
            }
        }
        let env = svc.environment.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        if !env.isEmpty {
            lines.append("    environment:")
            for e in env { lines.append("      \(e.key.trimmingCharacters(in: .whitespaces)): \(quoted(e.value))") }
        }
        if !svc.volumes.isEmpty {
            lines.append("    volumes:")
            for m in svc.volumes {
                let source = m.kind == .volume ? (m.volumeName ?? m.source) : m.source
                lines.append("      - \(source):\(m.destination)\(m.readOnly ? ":ro" : "")")
            }
        }
        if !svc.dependsOn.isEmpty {
            lines.append("    depends_on:")
            for d in svc.dependsOn { lines.append("      - \(d)") }
        }
        if !svc.networkAliases.isEmpty {
            lines.append("    networks:")
            lines.append("      default:")
            lines.append("        aliases:")
            for a in svc.networkAliases { lines.append("          - \(a)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Quotes a scalar when YAML (or the parser) could misread it; otherwise leaves it bare.
    static func quoted(_ value: String) -> String {
        let needsQuotes = value.isEmpty || value.first == " " || value.last == " "
            || value.contains(": ") || value.contains(" #") || value.hasPrefix("-") || value.hasPrefix("{")
            || value.hasPrefix("[") || ["true", "false", "yes", "no", "null", "~"].contains(value.lowercased())
            || Double(value) != nil
        guard needsQuotes else { return value }
        if !value.contains("\"") { return "\"\(value)\"" }
        if !value.contains("'") { return "'\(value)'" }
        return value
    }

    // MARK: - Editing

    /// Adds the service, or replaces it if one with the same name exists (`replacing` lets a
    /// rename replace the old block).
    public static func upsert(_ svc: ComposeServiceSpec, replacing oldName: String? = nil, in yaml: String) -> String {
        let project = ComposeParser.parse(yaml: yaml).projectName
        let block = serviceBlock(svc, projectName: project).components(separatedBy: "\n")
        var lines = yaml.components(separatedBy: "\n")

        if let range = blockRange(of: oldName ?? svc.serviceName, in: lines) ?? (oldName != nil ? blockRange(of: svc.serviceName, in: lines) : nil) {
            lines.replaceSubrange(range, with: block)
        } else if let servicesIndex = lines.firstIndex(where: { isTopLevelKey($0, "services") }) {
            // End of the services section: before the next top-level key, without trailing blanks.
            var end = lines.indices.dropFirst(servicesIndex + 1).first(where: { isTopLevel(lines[$0]) }) ?? lines.count
            while end > servicesIndex + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            let separator = end > servicesIndex + 1 ? [""] : []
            lines.insert(contentsOf: separator + block, at: end)
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines.append("services:")
            lines.append(contentsOf: block)
        }
        return ensureNamedVolumes(for: svc, in: lines.joined(separator: "\n"))
    }

    /// Removes a service's block and drops it from other services' `depends_on`.
    public static func remove(service name: String, from yaml: String) -> String {
        var lines = yaml.components(separatedBy: "\n")
        guard let range = blockRange(of: name, in: lines) else { return yaml }
        var removeEnd = range.upperBound
        // Also drop one blank separator line that followed the block.
        if removeEnd < lines.count, lines[removeEnd].trimmingCharacters(in: .whitespaces).isEmpty { removeEnd += 1 }
        lines.removeSubrange(range.lowerBound..<removeEnd)
        // Remove "- name" entries under depends_on.
        var result: [String] = []
        var inDependsOn = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("depends_on:") { inDependsOn = true; result.append(line); continue }
            if inDependsOn && indent <= 4 && !trimmed.isEmpty { inDependsOn = false }
            if inDependsOn && (trimmed == "- \(name)" || trimmed == "- \"\(name)\"" || trimmed == "\(name):") { continue }
            result.append(line)
        }
        // A `depends_on:` left without entries would confuse readers; drop it.
        var cleaned: [String] = []
        for (i, line) in result.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "depends_on:" {
                let next = result.dropFirst(i + 1).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if next.map({ $0.prefix { $0 == " " }.count <= line.prefix { $0 == " " }.count }) ?? true { continue }
            }
            cleaned.append(line)
        }
        return cleaned.joined(separator: "\n")
    }

    /// Sets the top-level `name:` (the stack/project name), adding it at the top if missing.
    public static func setProjectName(_ name: String, in yaml: String) -> String {
        var lines = yaml.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { isTopLevelKey($0, "name") }) {
            lines[i] = "name: \(name)"
        } else {
            lines.insert(contentsOf: ["name: \(name)", ""], at: 0)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func isTopLevel(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first != " " && first != "\t" && first != "#"
    }

    private static func isTopLevelKey(_ line: String, _ key: String) -> Bool {
        isTopLevel(line) && line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):")
    }

    /// Lines of `name`'s block inside `services:` (the `  name:` line through its last nested line).
    static func blockRange(of name: String, in lines: [String]) -> Range<Int>? {
        guard let servicesIndex = lines.firstIndex(where: { isTopLevelKey($0, "services") }) else { return nil }
        var i = servicesIndex + 1
        while i < lines.count, !isTopLevel(lines[i]) {
            let line = lines[i]
            let indent = line.prefix { $0 == " " }.count
            let key = line.trimmingCharacters(in: .whitespaces)
            if indent == 2, key == "\(name):" || key == "\"\(name)\":" || key == "'\(name)':" {
                var end = i + 1
                while end < lines.count {
                    let l = lines[end]
                    if isTopLevel(l) { break }
                    let ind = l.prefix { $0 == " " }.count
                    if !l.trimmingCharacters(in: .whitespaces).isEmpty && ind <= 2 { break }
                    end += 1
                }
                // Trailing blank lines belong between blocks, not to this block.
                while end > i + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
                return i..<end
            }
            i += 1
        }
        return nil
    }

    /// Adds `name:` entries under a top-level `volumes:` for named volumes the service uses.
    private static func ensureNamedVolumes(for svc: ComposeServiceSpec, in yaml: String) -> String {
        let names = svc.volumes.filter { $0.kind == .volume }.map { $0.volumeName ?? $0.source }
        guard !names.isEmpty else { return yaml }
        let declared = Set(ComposeParser.parse(yaml: yaml).declaredVolumes)
        let missing = names.filter { !declared.contains($0) }
        guard !missing.isEmpty else { return yaml }
        var lines = yaml.components(separatedBy: "\n")
        if let volumesIndex = lines.firstIndex(where: { isTopLevelKey($0, "volumes") }) {
            var end = lines.indices.dropFirst(volumesIndex + 1).first(where: { isTopLevel(lines[$0]) }) ?? lines.count
            while end > volumesIndex + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            lines.insert(contentsOf: missing.map { "  \($0):" }, at: end)
        } else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            lines.append("")
            lines.append("volumes:")
            lines.append(contentsOf: missing.map { "  \($0):" })
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
