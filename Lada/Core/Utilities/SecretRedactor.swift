import Foundation

public enum SecretRedactor {
    private static let sensitiveKeyFragments: [String] = [
        "PASSWORD", "PASSWD", "SECRET", "TOKEN", "API_KEY", "APIKEY",
        "PRIVATE_KEY", "ACCESS_KEY", "AUTH", "CREDENTIAL", "BEARER"
    ]

    public static func isSensitiveKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        return sensitiveKeyFragments.contains { upper.contains($0) }
    }

    public static func redact(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var result = input

        // Redact key=value pairs where key looks sensitive
        let kvPattern = #"(?i)\b([A-Z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_KEY|APIKEY|PRIVATE_KEY|ACCESS_KEY|CREDENTIAL|AUTH)[A-Z0-9_]*)\s*=\s*("[^"]*"|'[^']*'|[^\s,;]+)"#
        if let regex = try? NSRegularExpression(pattern: kvPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1=<REDACTED>"
            )
        }

        // Redact Bearer tokens
        let bearerPattern = #"(?i)(Bearer\s+)[A-Za-z0-9\-._~+/]+=*"#
        if let regex = try? NSRegularExpression(pattern: bearerPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1<REDACTED>"
            )
        }

        // Redact CLI flags like --password <val>
        let flagPattern = #"(?i)(--password(?:=|\s+))("[^"]*"|'[^']*'|[^\s]+)"#
        if let regex = try? NSRegularExpression(pattern: flagPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1<REDACTED>"
            )
        }

        return result
    }

    public static func redactArguments(_ arguments: [String]) -> [String] {
        var output: [String] = []
        var redactNext = false
        for arg in arguments {
            if redactNext {
                output.append("<REDACTED>")
                redactNext = false
                continue
            }
            let lower = arg.lowercased()
            if lower == "--password" || lower == "--token" {
                output.append(arg)
                redactNext = true
                continue
            }
            if let eqIndex = arg.firstIndex(of: "=") {
                let key = String(arg[..<eqIndex])
                let cleanedKey = key.replacingOccurrences(of: "^-+[a-zA-Z-]+\\s*", with: "", options: .regularExpression)
                if isSensitiveKey(cleanedKey) || lower.hasPrefix("--password=") {
                    output.append("\(key)=<REDACTED>")
                    continue
                }
            }
            output.append(redact(arg))
        }
        return output
    }

    public static func formatCommandPreview(executable: String, arguments: [String]) -> String {
        let safeArgs = redactArguments(arguments).map { arg -> String in
            if arg.contains(" ") || arg.contains("\"") {
                return "\"\(arg.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return arg
        }
        return ([executable] + safeArgs).joined(separator: " ")
    }
}
