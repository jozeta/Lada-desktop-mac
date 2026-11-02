import Foundation

/// Plain-language helpers for the Builds screen: find the build file in a folder, suggest and
/// check an image name, and read progress and failures from BuildKit's plain output.
public enum BuildPlanner {
    /// Build file names in order of preference.
    static let preferredNames = ["Containerfile", "Dockerfile", "containerfile", "dockerfile"]

    /// The build file in `folder` (absolute path), or nil if there is none.
    public static func detectBuildFile(in folder: String) -> String? {
        let fm = FileManager.default
        for name in preferredNames {
            let path = (folder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue { return path }
        }
        let variants = ((try? fm.contentsOfDirectory(atPath: folder)) ?? []).filter { name in
            let lower = name.lowercased()
            return lower.hasSuffix(".dockerfile") || lower.hasSuffix(".containerfile")
                || lower.hasPrefix("dockerfile.") || lower.hasPrefix("containerfile.")
        }.sorted()
        return variants.first.map { (folder as NSString).appendingPathComponent($0) }
    }

    /// Absolute path of the build file: a relative path is taken relative to the folder (the CLI
    /// would otherwise resolve it against Låda's own working directory).
    public static func resolvedBuildFile(_ file: String, in folder: String) -> String {
        file.hasPrefix("/") ? file : (folder as NSString).appendingPathComponent(file)
    }

    /// `local/<folder-name>:latest`, lowercased and cleaned to a valid image name.
    public static func suggestedImageName(for folder: String) -> String {
        let base = (folder as NSString).lastPathComponent.lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return "local/\(base.isEmpty ? "app" : base):latest"
    }

    /// An OCI image reference: optional registry host (with port), lowercase path components and
    /// an optional tag. Returns a reason when it is not valid.
    public static func imageNameProblem(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Give the image a name, for example local/my-app:latest." }
        let pattern = #"^([a-zA-Z0-9.-]+(:[0-9]+)?/)?[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$"#
        if trimmed.range(of: pattern, options: .regularExpression) == nil {
            return "Use lowercase letters, digits, '.', '_' or '-', slashes between parts, and an optional ':tag' (for example local/my-app:1.0)."
        }
        return nil
    }

    public struct Progress: Equatable, Sendable {
        public let step: Int
        public let total: Int
        public let description: String
    }

    /// The latest `#n [k/m] INSTRUCTION` line in BuildKit plain output ("step k of m").
    public static func progress(in log: String) -> Progress? {
        let regex = try? NSRegularExpression(pattern: #"^#\d+ \[(?:[^\]\s]+ )?(\d+)/(\d+)\] (.+)$"#, options: [.anchorsMatchLines])
        guard let regex else { return nil }
        let ns = log as NSString
        guard let match = regex.matches(in: log, range: NSRange(location: 0, length: ns.length)).last,
              let step = Int(ns.substring(with: match.range(at: 1))),
              let total = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        return Progress(step: step, total: total, description: ns.substring(with: match.range(at: 3)))
    }

    /// The most useful error line from a failed build: BuildKit's own `#n ERROR: …` line if
    /// present (clearer than the CLI's wrapped `Error: unknown: "failed to solve: …"`), otherwise
    /// the last error-looking line, without prefixes.
    public static func failureSummary(in log: String) -> String? {
        let lines = log.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if let buildKit = lines.last(where: { $0.range(of: #"^#\d+ ERROR: "#, options: .regularExpression) != nil }),
           let range = buildKit.range(of: #"^#\d+ ERROR: "#, options: .regularExpression) {
            return String(buildKit[range.upperBound...])
        }
        guard var line = lines.last(where: { $0.lowercased().contains("error") }) else { return nil }
        if line.hasPrefix("Error: ") { line.removeFirst("Error: ".count) }
        return line.isEmpty ? nil : line
    }
}
