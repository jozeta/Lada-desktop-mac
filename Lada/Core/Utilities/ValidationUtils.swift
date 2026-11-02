import Foundation

public enum ValidationUtils {
    /// Upstream rule from `ManagedContainer.nameValid`:
    /// Length 2...63, pattern `^[a-zA-Z0-9][a-zA-Z0-9_.-]+$`
    public static func isValidContainerName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 63 else { return false }
        let pattern = #"^[a-zA-Z0-9][a-zA-Z0-9_.-]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Upstream rule from `NetworkResource.nameValid`:
    /// `^[a-z0-9](?:[a-z0-9._-]{0,61}[a-z0-9])?$`
    public static func isValidNetworkName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 63 else { return false }
        let pattern = #"^[a-z0-9](?:[a-z0-9._-]{0,61}[a-z0-9])?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Upstream rule from `VolumeResource.nameValid`:
    /// `^[A-Za-z0-9][A-Za-z0-9_.-]*$`, max 255
    public static func isValidVolumeName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255 else { return false }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9_.-]*$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Upstream rule from `MachineConfiguration.validate`:
    /// `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, max 56 characters
    public static func isValidMachineName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 56 else { return false }
        let pattern = #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// An absolute path inside a container: starts with `/` (so it can never be read as a command
    /// option when passed to `ls`, `rm`, etc.) and has no control characters such as NUL or newline.
    public static func isValidAbsoluteContainerPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count <= 4096 else { return false }
        return !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// A single path component typed by the user (new folder name, upload name): not empty, not
    /// `.` or `..`, no `/`, and no control characters.
    public static func isValidFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 255, name != ".", name != "..", !name.contains("/") else { return false }
        return !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    public static func isValidIPv4CIDR(_ cidr: String) -> Bool {
        let parts = cidr.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (1...32).contains(prefix) else { return false }
        let octets = parts[0].split(separator: ".")
        guard octets.count == 4 else { return false }
        for octet in octets {
            guard let val = Int(octet), (0...255).contains(val) else { return false }
        }
        return true
    }

    public static func isValidIPv6CIDR(_ cidr: String) -> Bool {
        let parts = cidr.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (1...128).contains(prefix) else { return false }
        let addr = String(parts[0])
        var sin6 = sockaddr_in6()
        return addr.withCString { cstr in
            inet_pton(AF_INET6, cstr, &sin6.sin6_addr) == 1
        }
    }

    public static func validateResourceName(_ name: String, fieldName: String = "Resource name") -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "\(fieldName) cannot be empty."
        }
        if fieldName.lowercased().contains("machine") {
            guard isValidMachineName(trimmed) else {
                return "\(fieldName) '\(trimmed)' must use lowercase letters, digits, or hyphens (max 56 chars)."
            }
        } else {
            guard isValidNetworkName(trimmed) else {
                return "\(fieldName) '\(trimmed)' must use lowercase alphanumeric characters, '.', '_', or '-' (max 63 chars)."
            }
        }
        return nil
    }

    public static func validateVolumeName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidVolumeName(trimmed) else {
            return "Volume name '\(trimmed)' must start with an alphanumeric character and contain only letters, digits, '.', '_', or '-' (max 255 chars)."
        }
        return nil
    }

    public static func validateIPv4CIDR(_ cidr: String) -> String? {
        let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard isValidIPv4CIDR(trimmed) else {
            return "Invalid IPv4 CIDR '\(trimmed)'. Expected format like 192.168.70.0/24."
        }
        return nil
    }

    public static func validateIPv6CIDR(_ cidr: String) -> String? {
        let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard isValidIPv6CIDR(trimmed) else {
            return "Invalid IPv6 CIDR '\(trimmed)'. Expected format like fd00:70::/64."
        }
        return nil
    }

    public static func isValidMACAddress(_ mac: String) -> Bool {
        let pattern = #"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"#
        return mac.trimmingCharacters(in: .whitespaces).range(of: pattern, options: .regularExpression) != nil
    }

    /// Most aliases one network attachment may declare (upstream `AliasPolicy`, container 1.6).
    public static let maximumDNSAliasesPerNetwork = 32

    /// A DNS alias for `--network <name>,alias=<alias>`: a DNS name (labels of 1–63 letters,
    /// digits or hyphens, not starting or ending with a hyphen), optionally with a trailing dot,
    /// or a subtree alias with a leading dot such as `.api.example.test`.
    public static func isValidDNSAlias(_ alias: String) -> Bool {
        var name = Substring(alias)
        if name.hasPrefix(".") { name = name.dropFirst() }
        if name.hasSuffix(".") { name = name.dropLast() }
        guard !name.isEmpty, name.utf8.count <= 253 else { return false }
        let label = #"^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            String($0).range(of: label, options: .regularExpression) != nil
        }
    }

    /// Number of labels in an alias, ignoring a leading (subtree) or trailing dot.
    public static func dnsLabelCount(_ alias: String) -> Int {
        alias.split(separator: ".").count
    }

    public static func isValidEnvironmentKey(_ key: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_]*$"#
        return key.trimmingCharacters(in: .whitespaces).range(of: pattern, options: .regularExpression) != nil
    }

    public static func isValidMemorySizeSpec(_ spec: String) -> Bool {
        let pattern = #"^\d+(?i:[bkmgtp]i?b?)?$"#
        return spec.trimmingCharacters(in: .whitespaces).range(of: pattern, options: .regularExpression) != nil
    }

    public static func validateContainerCreateRequest(_ req: ContainerCreateRequest) -> [String] {
        var issues: [String] = []
        if req.imageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Image reference is required (for example, `alpine:latest` or `nginx:latest`).")
        }
        let trimmedName = req.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && !isValidContainerName(trimmedName) {
            issues.append("Container name '\(trimmedName)' must start with an alphanumeric character, contain only letters, digits, '.', '_', or '-', and be at most 63 characters.")
        }
        if let unsupportedRestart = req.requestedUnsupportedRestartPolicy, !unsupportedRestart.isEmpty, unsupportedRestart != "none" {
            issues.append("Restart policy '\(unsupportedRestart)' is not supported by Apple's `container` runtime. Please set restart behavior to 'None (Manual)' before creating the container.")
        }
        if req.cpus < 1 || req.cpus > 128 {
            issues.append("CPU allocation must be between 1 and 128 cores.")
        }
        if req.memoryMB < 64 {
            issues.append("Memory allocation must be at least 64 MiB.")
        }
        // Databases that refuse to initialise without credentials. Låda used to inject well-known
        // passwords here; now the user (or the preset's generated secret) must provide them.
        let envValue: (String) -> String? = { name in
            req.environmentVariables.first { $0.key.trimmingCharacters(in: .whitespaces) == name }?.value
        }
        let hasValue: (String) -> Bool = { !(envValue($0) ?? "").isEmpty }
        switch ContainerCreateRequest.repositoryName(req.imageReference) {
        case "postgres":
            if !hasValue("POSTGRES_PASSWORD") && !hasValue("POSTGRES_PASSWORD_FILE") && !hasValue("POSTGRES_HOST_AUTH_METHOD") {
                issues.append("PostgreSQL needs POSTGRES_PASSWORD. Add it under Environment Variables (the key button generates a random one).")
            }
        case "mysql", "mariadb":
            let auth = ["MYSQL_ROOT_PASSWORD", "MYSQL_ALLOW_EMPTY_PASSWORD", "MYSQL_RANDOM_ROOT_PASSWORD",
                        "MARIADB_ROOT_PASSWORD", "MARIADB_ALLOW_EMPTY_ROOT_PASSWORD", "MARIADB_RANDOM_ROOT_PASSWORD"]
            if !auth.contains(where: hasValue) {
                issues.append("MySQL/MariaDB need a root password (MYSQL_ROOT_PASSWORD or MARIADB_ROOT_PASSWORD). Add it under Environment Variables (the key button generates a random one).")
            }
        default:
            break
        }
        let aliases = req.dnsAliases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if aliases.count > maximumDNSAliasesPerNetwork {
            issues.append("At most \(maximumDNSAliasesPerNetwork) DNS aliases are allowed per network.")
        }
        for alias in aliases where !isValidDNSAlias(alias) {
            issues.append("DNS alias '\(alias)' is not a valid DNS name (letters, digits and hyphens per label; a leading '.' makes a subtree alias).")
        }
        // `db.test` and `.db.test` are different rules (exact vs subtree); only a trailing dot is cosmetic.
        let lowered = aliases.map { $0.lowercased().hasSuffix(".") ? String($0.lowercased().dropLast()) : $0.lowercased() }
        if Set(lowered).count != lowered.count {
            issues.append("Each DNS alias may be listed only once.")
        }
        if !req.macAddress.trimmingCharacters(in: .whitespaces).isEmpty && !isValidMACAddress(req.macAddress) {
            issues.append("MAC address must be in XX:XX:XX:XX:XX:XX format.")
        }
        for env in req.environmentVariables {
            let k = env.key.trimmingCharacters(in: .whitespaces)
            if !k.isEmpty && !isValidEnvironmentKey(k) {
                issues.append("Environment variable key '\(k)' is invalid. Use letters, digits, and underscores, starting with a letter or underscore.")
            }
        }
        var seenHostPorts = Set<String>()
        for port in req.publishedPorts {
            if port.hostPort == 0 || port.containerPort == 0 {
                issues.append("Port numbers must be between 1 and 65535.")
            }
            let key = "\(port.hostAddress):\(port.hostPort)/\(port.proto)"
            if seenHostPorts.contains(key) {
                issues.append("Duplicate published host port mapping: \(key).")
            }
            seenHostPorts.insert(key)
        }
        for mount in req.mounts {
            let dst = mount.destination.trimmingCharacters(in: .whitespaces)
            if dst.isEmpty || !dst.hasPrefix("/") {
                issues.append("Mount destination path '\(dst)' must be an absolute path inside the container (starting with `/`).")
            }
            if mount.kind == .bind && mount.source.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append("Bind mount targeting '\(dst)' requires a host source path.")
            }
        }
        return issues
    }
}
