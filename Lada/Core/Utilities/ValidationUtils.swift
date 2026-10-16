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
