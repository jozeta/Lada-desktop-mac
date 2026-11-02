import Foundation

/// The `.command` file Terminal.app runs to open a shell in a container or machine. Terminal runs
/// it with `/bin/sh`, so every word is single-quoted: names, paths and arguments can never break
/// out into extra shell commands.
public enum ExternalTerminalScript {
    /// POSIX single-quoting: `it's` → `'it'\''s'`.
    public static func quote(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func make(heading: String, command: [String]) -> String {
        let quoted = command.map(quote).joined(separator: " ")
        return """
        #!/bin/sh
        clear
        printf '\\033[1;36m==> Lada: %s\\033[0m\\n\\n' \(quote(heading))
        \(quoted)
        status=$?
        if [ "$status" -ne 0 ]; then
            printf '\\n\\033[1;31m[Lada] The shell exited with status %d.\\033[0m\\n' "$status"
            printf 'Press Enter to close this window...'
            read -r _
        fi

        """
    }
}
