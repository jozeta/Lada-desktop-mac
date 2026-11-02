import Foundation

/// Reference text for the Dockerfile Editor's completion list (IntelliSense): what each
/// instruction does, how it works, its syntax and the flags and parameters it accepts.
/// Follows the Dockerfile reference (BuildKit, Dockerfile syntax 1.x).
public struct DockerfileDoc: Equatable, Sendable {
    public struct Parameter: Equatable, Sendable {
        public let name: String
        public let detail: String
    }

    public let instruction: String
    public let summary: String
    public let howItWorks: String
    public let syntax: [String]
    public let parameters: [Parameter]
    public let example: String
    /// The parameter being completed (e.g. `--mount`), highlighted in the pane.
    public var highlighted: String?
}

public enum DockerfileDocs {
    private static func p(_ name: String, _ detail: String) -> DockerfileDoc.Parameter { .init(name: name, detail: detail) }

    public static let all: [String: DockerfileDoc] = {
        let docs: [DockerfileDoc] = [
            DockerfileDoc(
                instruction: "FROM",
                summary: "Starts a build stage from a base image.",
                howItWorks: "Every Dockerfile begins with FROM (only ARG may come before it). The stage's filesystem starts as the base image's. Each further FROM starts a new stage; name a stage with AS so later stages can COPY --from it, and only the last stage ends up in the image.",
                syntax: ["FROM [--platform=<platform>] <image>[:<tag>|@<digest>] [AS <name>]"],
                parameters: [
                    p("--platform", "Pull the base image for this platform, e.g. linux/arm64 or $BUILDPLATFORM (for cross-compiling stages)."),
                    p("<image>", "Base image reference. Pin a tag or digest instead of :latest so builds are repeatable."),
                    p("AS <name>", "Names the stage for COPY --from=<name> and `--target`.")
                ],
                example: "FROM node:24-alpine AS build",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "RUN",
                summary: "Runs a command while building and saves the result as a new layer.",
                howItWorks: "Shell form runs through /bin/sh -c (or SHELL); exec form [\"cmd\", \"arg\"] runs the program directly without a shell. Each RUN creates a layer, so chain related commands with && and clean package caches in the same RUN.",
                syntax: ["RUN [--mount=…] [--network=…] [--security=…] <command>", "RUN [\"executable\", \"param1\", \"param2\"]"],
                parameters: [
                    p("--mount=type=cache,target=<path>", "A cache kept between builds (package manager caches), not stored in the image."),
                    p("--mount=type=bind,source=<path>,target=<path>", "Bind files from the build context or another stage, read-only by default."),
                    p("--mount=type=secret,id=<id>[,target=<path>]", "Expose a build secret as a file for this RUN only; it never lands in a layer."),
                    p("--mount=type=ssh", "Forward the SSH agent, e.g. to clone private repositories."),
                    p("--mount=type=tmpfs,target=<path>", "A temporary in-memory directory for this RUN."),
                    p("--network=default|none|host", "Network access for this command; none makes it fully offline."),
                    p("--security=insecure|sandbox", "insecure allows privileged operations (needs the builder to permit it).")
                ],
                example: "RUN --mount=type=cache,target=/root/.npm npm ci",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "CMD",
                summary: "The default command (or default arguments) when a container starts.",
                howItWorks: "Only the last CMD counts. Arguments given to `container run <image> …` replace it. With an ENTRYPOINT, CMD supplies its default arguments. Prefer the exec form so the process gets signals directly.",
                syntax: ["CMD [\"executable\", \"param1\"]", "CMD [\"param1\", \"param2\"]  (arguments for ENTRYPOINT)", "CMD command param1"],
                parameters: [p("exec form", "A JSON array; runs without a shell and receives SIGTERM on stop."), p("shell form", "Runs via /bin/sh -c; the shell is PID 1 and may not forward signals.")],
                example: "CMD [\"node\", \"server.js\"]",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "ENTRYPOINT",
                summary: "The program a container always runs; CMD and run arguments are passed to it.",
                howItWorks: "Use it when the image is an executable. `container run <image> args` appends args to the ENTRYPOINT instead of replacing it; `--entrypoint` overrides it. Wrapper scripts should end with `exec \"$@\"` so the real process becomes PID 1.",
                syntax: ["ENTRYPOINT [\"executable\", \"param1\"]", "ENTRYPOINT command param1"],
                parameters: [p("exec form", "Recommended: receives CMD as arguments and gets signals."), p("shell form", "Ignores CMD and run arguments.")],
                example: "ENTRYPOINT [\"/usr/local/bin/docker-entrypoint.sh\"]",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "COPY",
                summary: "Copies files from the build context or another stage into the image.",
                howItWorks: "Sources are relative to the build context (respecting .dockerignore); destinations are relative to WORKDIR. A trailing / on the destination means a directory. Copy dependency manifests first and source later so dependency layers stay cached.",
                syntax: ["COPY [--from=…] [--chown=…] [--chmod=…] [--link] <src>… <dest>", "COPY [\"<src>\", … \"<dest>\"]"],
                parameters: [
                    p("--from=<stage|image>", "Copy from an earlier build stage (by AS name or index) or from an image."),
                    p("--chown=<user>:<group>", "Owner of the copied files (Linux only)."),
                    p("--chmod=<perms>", "Permissions, e.g. 755 or u+x."),
                    p("--link", "Copies into an independent layer so changes elsewhere don't invalidate it."),
                    p("--parents", "Keeps the source's parent directories under the destination."),
                    p("--exclude=<pattern>", "Skips matching files.")
                ],
                example: "COPY --from=build --chown=node:node /app/dist ./dist",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "ADD",
                summary: "Like COPY, but also fetches URLs and Git repositories and unpacks local tar archives.",
                howItWorks: "Use COPY for plain files; reach for ADD only for its extras. Local .tar/.tar.gz sources are extracted into the destination; remote files are downloaded (verify them with --checksum).",
                syntax: ["ADD [--chown=…] [--chmod=…] [--checksum=…] <src>… <dest>"],
                parameters: [
                    p("--checksum=sha256:<hash>", "Verifies a downloaded file."),
                    p("--keep-git-dir=true", "Keeps .git when adding a Git repository."),
                    p("--chown=<user>:<group>", "Owner of the added files."),
                    p("--chmod=<perms>", "Permissions of the added files."),
                    p("--link", "Independent layer, like COPY --link."),
                    p("--exclude=<pattern>", "Skips matching files.")
                ],
                example: "ADD --checksum=sha256:… https://example.com/tool.tar.gz /opt/",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "WORKDIR",
                summary: "Sets the working directory for the instructions that follow and for the container.",
                howItWorks: "Creates the directory if needed. Relative paths build on the previous WORKDIR. RUN, CMD, ENTRYPOINT, COPY and ADD use it; prefer it over `RUN cd …`.",
                syntax: ["WORKDIR /path/to/dir"],
                parameters: [p("/path", "Absolute, or relative to the previous WORKDIR. Can use ENV variables.")],
                example: "WORKDIR /app",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "ENV",
                summary: "Sets environment variables for the rest of the build and for running containers.",
                howItWorks: "Values persist in the image and are visible to `container inspect`, so never put secrets here (use RUN --mount=type=secret). Override at run time with -e. Later instructions can use them as $NAME.",
                syntax: ["ENV <key>=<value> [<key>=<value> …]"],
                parameters: [p("<key>=<value>", "Quote values with spaces: ENV GREETING=\"hello world\".")],
                example: "ENV NODE_ENV=production PORT=3000",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "ARG",
                summary: "Declares a build-time variable, set with `--build-arg`.",
                howItWorks: "Exists only while building, not in running containers. An ARG before FROM can be used in FROM; redeclare it inside a stage to use it there. Values are visible in the image history, so don't pass secrets as build args.",
                syntax: ["ARG <name>[=<default>]"],
                parameters: [
                    p("<name>=<default>", "Default when no --build-arg is given."),
                    p("TARGETPLATFORM, TARGETOS, TARGETARCH", "Predefined: the platform being built for."),
                    p("BUILDPLATFORM", "Predefined: the platform the builder runs on.")
                ],
                example: "ARG VERSION=1.0",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "EXPOSE",
                summary: "Documents the ports the application listens on.",
                howItWorks: "It doesn't publish anything: publish with `container run -p <mac-port>:<container-port>`. Låda uses EXPOSE to suggest port mappings.",
                syntax: ["EXPOSE <port>[/<protocol>] …"],
                parameters: [p("<port>/tcp|udp", "TCP is the default.")],
                example: "EXPOSE 8080/tcp",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "VOLUME",
                summary: "Marks a directory as holding data that should live outside the container's filesystem.",
                howItWorks: "Mount a named volume or folder there at run time (-v) to keep the data. Changes made to that path by later build steps are discarded.",
                syntax: ["VOLUME [\"/data\"]", "VOLUME /data /logs"],
                parameters: [p("<path>", "Directory inside the image.")],
                example: "VOLUME [\"/var/lib/app\"]",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "USER",
                summary: "Sets the user (and group) for the following instructions and the container's process.",
                howItWorks: "Running as a non-root user limits what a compromised process can do. The user must exist in the image (create it with adduser/useradd first).",
                syntax: ["USER <user>[:<group>]", "USER <uid>[:<gid>]"],
                parameters: [p("<user>|<uid>", "Name or numeric ID."), p(":<group>", "Optional primary group.")],
                example: "USER 1000:1000",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "LABEL",
                summary: "Adds metadata to the image as key/value pairs.",
                howItWorks: "Labels show in `container image inspect`. Use the OCI keys (org.opencontainers.image.*) for title, source, version and licence.",
                syntax: ["LABEL <key>=<value> [<key>=<value> …]"],
                parameters: [p("org.opencontainers.image.source", "Where the source lives (a URL)."), p("org.opencontainers.image.version", "The image's version.")],
                example: "LABEL org.opencontainers.image.title=\"web\"",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "HEALTHCHECK",
                summary: "Tells the runtime how to check that the container still works.",
                howItWorks: "The command runs inside the container; exit 0 means healthy, 1 unhealthy. After --retries failures in a row the container is marked unhealthy. NONE disables a check inherited from the base image.",
                syntax: ["HEALTHCHECK [--interval=…] [--timeout=…] [--start-period=…] [--retries=…] CMD <command>", "HEALTHCHECK NONE"],
                parameters: [
                    p("--interval=<duration>", "Time between checks (default 30s)."),
                    p("--timeout=<duration>", "A check taking longer fails (default 30s)."),
                    p("--start-period=<duration>", "Startup grace period in which failures don't count (default 0s)."),
                    p("--start-interval=<duration>", "Time between checks during the start period (default 5s)."),
                    p("--retries=<n>", "Consecutive failures before unhealthy (default 3).")
                ],
                example: "HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:8080/health || exit 1",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "SHELL",
                summary: "Changes the shell used by the shell form of RUN, CMD and ENTRYPOINT.",
                howItWorks: "The default on Linux is [\"/bin/sh\", \"-c\"]. Switching to bash with -o pipefail makes a failing command in a pipe fail the build.",
                syntax: ["SHELL [\"executable\", \"parameters\"]"],
                parameters: [p("[\"/bin/bash\", \"-o\", \"pipefail\", \"-c\"]", "Bash, failing on errors inside pipes.")],
                example: "SHELL [\"/bin/bash\", \"-o\", \"pipefail\", \"-c\"]",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "STOPSIGNAL",
                summary: "The signal sent to the container's main process to stop it.",
                howItWorks: "`container stop` sends it, waits, then kills the process. Use the signal your application handles for a clean shutdown (nginx: SIGQUIT).",
                syntax: ["STOPSIGNAL <signal>"],
                parameters: [p("SIGTERM", "Default: ask to terminate."), p("SIGINT", "Like Ctrl-C."), p("SIGQUIT", "Graceful shutdown for nginx and others.")],
                example: "STOPSIGNAL SIGQUIT",
                highlighted: nil
            ),
            DockerfileDoc(
                instruction: "ONBUILD",
                summary: "Adds an instruction that runs later, when another image is built FROM this one.",
                howItWorks: "Useful for base images that must act on the downstream project's files. ONBUILD can't contain FROM or another ONBUILD.",
                syntax: ["ONBUILD <INSTRUCTION> …"],
                parameters: [p("<INSTRUCTION>", "Any instruction except FROM and ONBUILD.")],
                example: "ONBUILD COPY . /app",
                highlighted: nil
            )
        ]
        return Dictionary(uniqueKeysWithValues: docs.map { ($0.instruction, $0) })
    }()

    /// The reference for a completion suggestion, in the context of the line being typed: an
    /// instruction's own page, or the line's instruction with the completed flag highlighted.
    public static func doc(for item: String, lineBeforeCursor: String) -> DockerfileDoc? {
        if let own = all[item.uppercased()], DockerfileCompletionEngine.instructions.contains(item.uppercased()) {
            return own
        }
        let lineWords = lineBeforeCursor.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = lineWords.first, var doc = all[first.uppercased()] else { return nil }
        if item.hasPrefix("--") {
            let flag = String(item.prefix { $0 != "=" })
            doc.highlighted = doc.parameters.first { $0.name.hasPrefix(flag) }?.name
        } else {
            // A value such as SIGTERM or TARGETARCH: highlight the parameter that names it.
            let value = item.uppercased()
            doc.highlighted = doc.parameters.first { param in
                param.name.uppercased()
                    .components(separatedBy: CharacterSet(charactersIn: " =<>[],|:\""))
                    .contains { $0.count >= 3 && value.hasPrefix($0) }
            }?.name
        }
        return doc
    }
}
