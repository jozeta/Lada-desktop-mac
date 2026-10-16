import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Starter Templates

public struct DockerfileTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let content: String

    public static let allTemplates: [DockerfileTemplate] = [
        DockerfileTemplate(
            id: "nginx-web",
            title: "Nginx Static Web Server",
            subtitle: "Alpine-based HTTP web server exposing port 80",
            content: """
            # Technical Nordic Nginx Web Container
            FROM nginx:1.27-alpine

            LABEL maintainer="platform@lada.local"
            ENV NGINX_HOST=localhost
            ENV NGINX_PORT=80

            WORKDIR /usr/share/nginx/html
            RUN echo "<h1>Running on Apple Container via Lada</h1>" > index.html

            EXPOSE 80/tcp
            CMD ["nginx", "-g", "daemon off;"]
            """
        ),
        DockerfileTemplate(
            id: "python-api",
            title: "Python HTTP Microservice",
            subtitle: "Python 3.12 slim service on port 8000",
            content: """
            FROM python:3.12-slim

            ENV PYTHONDONTWRITEBYTECODE=1
            ENV PYTHONUNBUFFERED=1
            ENV APP_PORT=8000

            WORKDIR /app
            VOLUME ["/app/data"]

            EXPOSE 8000/tcp
            CMD ["python3", "-m", "http.server", "8000"]
            """
        ),
        DockerfileTemplate(
            id: "node-service",
            title: "Node.js 22 Alpine Service",
            subtitle: "Lightweight Node.js runtime on port 3000",
            content: """
            FROM node:22-alpine

            ENV NODE_ENV=production
            ENV PORT=3000

            WORKDIR /usr/src/app
            USER node

            EXPOSE 3000/tcp
            CMD ["node", "-e", "require('http').createServer((_, res) => res.end('Hello from Lada Node container')).listen(3000)"]
            """
        ),
        DockerfileTemplate(
            id: "swift-service",
            title: "Swift 6.0 Linux Container",
            subtitle: "Official Swift 6.0 slim container",
            content: """
            FROM swift:6.0-slim

            ENV SWIFT_BACKTRACE=enable=yes
            WORKDIR /workspace

            EXPOSE 8080/tcp
            CMD ["swift", "--version"]
            """
        ),
        DockerfileTemplate(
            id: "go-multistage",
            title: "Go 1.23 HTTP Server",
            subtitle: "Lightweight Go Alpine microservice on port 8080",
            content: """
            FROM golang:1.23-alpine

            WORKDIR /app
            ENV CGO_ENABLED=0
            ENV PORT=8080

            EXPOSE 8080/tcp
            CMD ["go", "version"]
            """
        ),
        DockerfileTemplate(
            id: "postgres-ext4",
            title: "PostgreSQL 16 (Apple Ext4 Optimized)",
            subtitle: "Pre-configured with PGDATA subdirectory for Apple container ext4 volumes",
            content: """
            FROM postgres:16-alpine

            ENV POSTGRES_USER=lada
            ENV POSTGRES_PASSWORD=lada_secret_password
            ENV POSTGRES_DB=lada_app
            ENV PGDATA=/var/lib/postgresql/data/pgdata

            VOLUME ["/var/lib/postgresql/data"]
            EXPOSE 5432/tcp
            """
        )
    ]
}

// MARK: - Live Dockerfile Linter & Quick Fixes

public struct DockerfileDiagnostic: Identifiable, Sendable {
    public enum Severity: String, Sendable {
        case warning = "Warning"
        case bestPractice = "Best Practice"
    }

    public let id: String
    public let line: Int
    public let severity: Severity
    public let title: String
    public let detail: String
    public let quickFixTitle: String?
    public let fixedDockerfile: String?
}

public enum DockerfileLinter {
    public static func analyze(_ content: String) -> [DockerfileDiagnostic] {
        var diagnostics: [DockerfileDiagnostic] = []
        let lines = content.components(separatedBy: .newlines)
        var hasWorkdir = false
        var hasExpose = false
        var isPostgresImage = false
        var hasPGDataEnv = false

        for (idx, rawLine) in lines.enumerated() {
            let lineNum = idx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let upper = trimmed.uppercased()

            if upper.hasPrefix("WORKDIR ") {
                hasWorkdir = true
            }
            if upper.hasPrefix("EXPOSE ") {
                hasExpose = true
            }
            if upper.hasPrefix("ENV ") && upper.contains("PGDATA") {
                hasPGDataEnv = true
            }

            if upper.hasPrefix("FROM ") {
                let imagePart = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if imagePart.lowercased().contains("postgres") {
                    isPostgresImage = true
                }
                if imagePart.hasSuffix(":latest") || (!imagePart.contains(":") && !imagePart.contains("@") && !imagePart.lowercased().contains(" as ")) {
                    let baseName = imagePart.replacingOccurrences(of: ":latest", with: "")
                    let pinnedTag: String = {
                        switch baseName.lowercased() {
                        case "alpine": return "alpine:3.20"
                        case "ubuntu": return "ubuntu:24.04"
                        case "nginx": return "nginx:1.27-alpine"
                        case "postgres": return "postgres:16-alpine"
                        case "redis": return "redis:7-alpine"
                        case "node": return "node:22-alpine"
                        case "python": return "python:3.12-slim"
                        default: return "\(baseName):stable"
                        }
                    }()
                    var updatedLines = lines
                    updatedLines[idx] = "FROM \(pinnedTag)"
                    diagnostics.append(
                        DockerfileDiagnostic(
                            id: "unpinned-from-\(lineNum)",
                            line: lineNum,
                            severity: .bestPractice,
                            title: "Unpinned Base Image Tag (`\(imagePart)`)",
                            detail: "Using `:latest` or omitting a tag can lead to non-reproducible builds.",
                            quickFixTitle: "Pin to \(pinnedTag)",
                            fixedDockerfile: updatedLines.joined(separator: "\n")
                        )
                    )
                }
            }

            if (upper.hasPrefix("COPY ") || upper.hasPrefix("ADD ")) && !hasWorkdir {
                var updatedLines = lines
                updatedLines.insert("WORKDIR /app", at: idx)
                diagnostics.append(
                    DockerfileDiagnostic(
                        id: "missing-workdir-\(lineNum)",
                        line: lineNum,
                        severity: .bestPractice,
                        title: "COPY/ADD Before WORKDIR",
                        detail: "Copying files without setting `WORKDIR` places artifacts in the root directory `/`.",
                        quickFixTitle: "Insert WORKDIR /app",
                        fixedDockerfile: updatedLines.joined(separator: "\n")
                    )
                )
            }

            if upper.hasPrefix("RUN ") && trimmed.contains("apt-get install") && !trimmed.contains("-y") {
                var updatedLines = lines
                updatedLines[idx] = rawLine.replacingOccurrences(of: "apt-get install", with: "apt-get install -y --no-install-recommends")
                diagnostics.append(
                    DockerfileDiagnostic(
                        id: "apt-no-y-\(lineNum)",
                        line: lineNum,
                        severity: .warning,
                        title: "`apt-get install` Missing `-y` Flag",
                        detail: "Non-interactive container builds will hang or abort if `apt-get install` prompts for confirmation.",
                        quickFixTitle: "Add -y Flag",
                        fixedDockerfile: updatedLines.joined(separator: "\n")
                    )
                )
            }
        }

        if isPostgresImage && !hasPGDataEnv {
            let fixed = content.trimmingCharacters(in: .whitespacesAndNewlines) + "\nENV PGDATA=/var/lib/postgresql/data/pgdata\n"
            diagnostics.append(
                DockerfileDiagnostic(
                    id: "postgres-pgdata",
                    line: 1,
                    severity: .warning,
                    title: "PostgreSQL Missing `PGDATA` Subdirectory",
                    detail: "Apple's `container` runtime formats volumes as ext4 (containing `lost+found`), which causes `initdb` to fail unless `PGDATA` points to a subdirectory.",
                    quickFixTitle: "Add ENV PGDATA",
                    fixedDockerfile: fixed
                )
            )
        }

        if !hasExpose && !lines.isEmpty {
            let fixed = content.trimmingCharacters(in: .whitespacesAndNewlines) + "\nEXPOSE 8080/tcp\n"
            diagnostics.append(
                DockerfileDiagnostic(
                    id: "missing-expose",
                    line: max(1, lines.count),
                    severity: .bestPractice,
                    title: "No `EXPOSE` Port Declared",
                    detail: "Adding an `EXPOSE` instruction allows Låda to automatically map host ports when deploying.",
                    quickFixTitle: "Add EXPOSE 8080/tcp",
                    fixedDockerfile: fixed
                )
            )
        }

        return diagnostics
    }
}

// MARK: - Code Completion Item

public struct DockerfileCompletionItem: Identifiable, Equatable {
    public var id: String { insertText }
    public let label: String
    public let insertText: String
    public let category: String
    public let detail: String

    public static let allCatalog: [DockerfileCompletionItem] = [
        // Instructions
        DockerfileCompletionItem(label: "FROM", insertText: "FROM alpine:3.20", category: "Instruction", detail: "Set the base OCI image for subsequent instructions"),
        DockerfileCompletionItem(label: "WORKDIR", insertText: "WORKDIR /app", category: "Instruction", detail: "Set the working directory inside the container"),
        DockerfileCompletionItem(label: "RUN", insertText: "RUN ", category: "Instruction", detail: "Execute a command in a new image layer"),
        DockerfileCompletionItem(label: "COPY", insertText: "COPY . .", category: "Instruction", detail: "Copy files or directories from build context"),
        DockerfileCompletionItem(label: "ENV", insertText: "ENV APP_ENV=production", category: "Instruction", detail: "Set persistent environment variable"),
        DockerfileCompletionItem(label: "EXPOSE", insertText: "EXPOSE 8080/tcp", category: "Instruction", detail: "Declare container listening port"),
        DockerfileCompletionItem(label: "CMD", insertText: "CMD [\"/bin/sh\"]", category: "Instruction", detail: "Provide default executable/arguments for container"),
        DockerfileCompletionItem(label: "ENTRYPOINT", insertText: "ENTRYPOINT [\"/bin/sh\", \"-c\"]", category: "Instruction", detail: "Configure container to run as an executable"),
        DockerfileCompletionItem(label: "VOLUME", insertText: "VOLUME [\"/data\"]", category: "Instruction", detail: "Create a persistent mount point"),
        DockerfileCompletionItem(label: "USER", insertText: "USER 1000:1000", category: "Instruction", detail: "Set user and group ID for runtime"),
        DockerfileCompletionItem(label: "ARG", insertText: "ARG VERSION=1.0.0", category: "Instruction", detail: "Define build-time variable"),
        DockerfileCompletionItem(label: "LABEL", insertText: "LABEL org.opencontainers.image.title=\"app\"", category: "Instruction", detail: "Add metadata key-value label to image"),
        DockerfileCompletionItem(label: "HEALTHCHECK", insertText: "HEALTHCHECK --interval=30s CMD ", category: "Instruction", detail: "Check container health by running a command"),
        // Flags
        DockerfileCompletionItem(label: "--platform=linux/arm64", insertText: "--platform=linux/arm64", category: "Flag", detail: "Target Apple silicon ARM64 Linux platform"),
        DockerfileCompletionItem(label: "--from=builder", insertText: "--from=builder", category: "Flag", detail: "Copy artifacts from a previous build stage"),
        DockerfileCompletionItem(label: "--chown=1000:1000", insertText: "--chown=1000:1000", category: "Flag", detail: "Set file ownership during COPY/ADD"),
        // Base Images
        DockerfileCompletionItem(label: "alpine:3.20", insertText: "alpine:3.20", category: "Image", detail: "Minimal Alpine Linux base image"),
        DockerfileCompletionItem(label: "ubuntu:24.04", insertText: "ubuntu:24.04", category: "Image", detail: "Ubuntu 24.04 LTS Noble Numbat"),
        DockerfileCompletionItem(label: "nginx:1.27-alpine", insertText: "nginx:1.27-alpine", category: "Image", detail: "Official Nginx web server on Alpine"),
        DockerfileCompletionItem(label: "postgres:16-alpine", insertText: "postgres:16-alpine", category: "Image", detail: "Official PostgreSQL 16 database"),
        DockerfileCompletionItem(label: "redis:7-alpine", insertText: "redis:7-alpine", category: "Image", detail: "Official Redis 7 in-memory store"),
        DockerfileCompletionItem(label: "python:3.12-slim", insertText: "python:3.12-slim", category: "Image", detail: "Official Python 3.12 Debian slim"),
        DockerfileCompletionItem(label: "node:22-alpine", insertText: "node:22-alpine", category: "Image", detail: "Official Node.js 22 LTS on Alpine"),
        DockerfileCompletionItem(label: "swift:6.0-slim", insertText: "swift:6.0-slim", category: "Image", detail: "Official Swift 6.0 toolchain")
    ]
}

// MARK: - Main Dockerfile Editor View

public struct DockerfileEditorView: View {
    @ObservedObject var appState: AppState

    @State private var dockerfileText: String = DockerfileTemplate.allTemplates[0].content
    @State private var currentFileURL: URL? = nil
    @State private var cursorLine: Int = 1
    @State private var currentWordPrefix: String = ""
    @State private var completionSuggestions: [DockerfileCompletionItem] = []
    @State private var isBuildingAndRunning: Bool = false
    @State private var buildConsoleLines: [String] = []
    @State private var showConsolePane: Bool = false
    @State private var pendingInsertion: String? = nil

    // Editable Deployment Configuration (synced from Dockerfile, customizable by user)
    @State private var customContainerName: String = ""
    @State private var customPorts: [PortMapping] = []
    @State private var customEnvVars: [KeyValueEntry] = []
    @State private var customMounts: [MountAttachment] = []
    @State private var customCPUs: Int = 4
    @State private var customMemoryMB: Int = 1024
    @State private var replaceExistingIfConflict: Bool = false
    @State private var hasInitializedOverrides: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    private var parsedPreview: ParsedDockerfile {
        DockerfileParser.parse(content: dockerfileText, sourceFileURL: currentFileURL)
    }

    private var hasNameConflict: Bool {
        appState.hasContainerNameConflict(customContainerName)
    }

    private var conflictingHostPorts: Set<UInt16> {
        if replaceExistingIfConflict,
           let existing = appState.containers.first(where: { $0.id.lowercased() == customContainerName.trimmingCharacters(in: .whitespaces).lowercased() }) {
            let ownPorts = Set(existing.configuration.publishedPorts.map(\.hostPort))
            return appState.conflictingHostPorts(for: customPorts).subtracting(ownPorts)
        }
        return appState.conflictingHostPorts(for: customPorts)
    }

    public var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider().overlay(NordicTheme.borderSubtle)

            HSplitView {
                // Left: Code Editor + Completion Bar + Optional Console
                VStack(spacing: 0) {
                    DockerfileCodeEditorRepresentable(
                        text: $dockerfileText,
                        cursorLine: $cursorLine,
                        currentWordPrefix: $currentWordPrefix,
                        pendingInsertion: $pendingInsertion,
                        onFileDrop: { url in
                            if let content = try? String(contentsOf: url, encoding: .utf8) {
                                currentFileURL = url
                                dockerfileText = content
                                syncSettingsFromDockerfile(autoResolveConflicts: true)
                            }
                            _ = appState.handleDroppedDockerfile(url: url)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Interactive Code Completion Strip
                    completionStrip

                    if showConsolePane || !buildConsoleLines.isEmpty {
                        Divider().overlay(NordicTheme.borderSubtle)
                        buildConsoleView
                            .frame(height: 175)
                    }
                }
                .frame(minWidth: 440)

                // Right: Editable Deployment Settings & Conflict Resolver
                liveInspectorSidebar
                    .frame(minWidth: 330, idealWidth: 365, maxWidth: 430)
            }
        }
        .background(NordicTheme.windowBackground)
        .onChange(of: currentWordPrefix) { _, newPrefix in
            updateCompletions(for: newPrefix)
        }
        .onAppear {
            if let draft = appState.editorDraftDockerfileText, !draft.isEmpty {
                dockerfileText = draft
                currentFileURL = appState.editorDraftSourceURL
                syncSettingsFromDockerfile(autoResolveConflicts: true)
                hasInitializedOverrides = true
            } else if !hasInitializedOverrides {
                syncSettingsFromDockerfile(autoResolveConflicts: true)
                hasInitializedOverrides = true
            }
        }
    }

    private var activeDiagnostics: [DockerfileDiagnostic] {
        DockerfileLinter.analyze(dockerfileText)
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        let diags = activeDiagnostics
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Dockerfile & Containerfile Studio")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)

                    NordicStatusBadge(
                        label: diags.isEmpty ? "Lint Clean" : "\(diags.count) \(diags.count == 1 ? "Advisory" : "Advisories")",
                        tone: diags.isEmpty ? .positive : .warning
                    )

                    if let currentFileURL {
                        Text(currentFileURL.lastPathComponent)
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                }
                Text("Write or paste a Dockerfile with syntax highlighting, row numbers, live linting, and editable deployment settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }

            Spacer()

            Menu("Templates") {
                ForEach(DockerfileTemplate.allTemplates) { tpl in
                    Button("\(tpl.title) — \(tpl.subtitle)") {
                        dockerfileText = tpl.content
                        currentFileURL = nil
                        syncSettingsFromDockerfile(autoResolveConflicts: true)
                    }
                }
            }
            .controlSize(.small)
            .frame(width: 110)

            Button("Open File…") {
                openDockerfileFromDisk()
            }
            .controlSize(.small)

            Button("Save…") {
                saveDockerfileToDisk()
            }
            .controlSize(.small)

            Divider().frame(height: 18)

            Button {
                openInCreateContainerWizard()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Configure & Deploy…")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                buildAndRunImmediately()
            } label: {
                HStack(spacing: 5) {
                    if isBuildingAndRunning {
                        ProgressView().controlSize(.small)
                        Text("Deploying…")
                    } else {
                        Image(systemName: "play.fill")
                        Text("Build & Run Now")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            .controlSize(.small)
            .disabled(isBuildingAndRunning || dockerfileText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(NordicTheme.elevatedSurface)
    }

    // MARK: - Code Completion Strip

    private var completionStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                Text(verbatim: "Line \(cursorLine)")
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .frame(width: 72, alignment: .leading)

            Divider().frame(height: 14)

            Text("Completions:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NordicTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let items = completionSuggestions.isEmpty
                        ? Array(DockerfileCompletionItem.allCatalog.prefix(8))
                        : completionSuggestions
                    ForEach(items) { item in
                        Button {
                            pendingInsertion = item.insertText
                        } label: {
                            HStack(spacing: 4) {
                                Text(item.label)
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.primaryText)
                                Text(item.category)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(NordicTheme.contentSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(NordicTheme.borderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(item.detail)
                    }
                }
            }

            Spacer()

            Button {
                showConsolePane.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    Text(showConsolePane ? "Hide Output" : "Output")
                }
                .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NordicTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .top) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    // MARK: - Editable Deployment Configuration Sidebar

    private var liveInspectorSidebar: some View {
        let parsed = parsedPreview
        let diags = activeDiagnostics
        let conflictsExist = (hasNameConflict && !replaceExistingIfConflict) || !conflictingHostPorts.isEmpty

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NordicSectionHeader(
                        "Deployment Settings",
                        subtitle: "Customize name, ports, env, and mounts before deploying."
                    )
                    Spacer()
                    Button("Sync from Dockerfile") {
                        syncSettingsFromDockerfile(autoResolveConflicts: false)
                    }
                    .controlSize(.mini)
                    .help("Re-populate fields from the current Dockerfile instructions")
                }

                // Live Linter Diagnostics & Quick Fixes
                if !diags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                            Text(verbatim: "Dockerfile Linter (\(diags.count))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NordicTheme.primaryText)
                            Spacer()
                        }

                        ForEach(diags) { diag in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: diag.severity == .warning ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(diag.severity == .warning ? NordicTheme.statusAmber : NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: "L\(diag.line): \(diag.title)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(NordicTheme.primaryText)
                                    Text(diag.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(NordicTheme.secondaryText)
                                }

                                Spacer()

                                if let fixTitle = diag.quickFixTitle, let fixedText = diag.fixedDockerfile {
                                    Button(fixTitle) {
                                        dockerfileText = fixedText
                                        syncSettingsFromDockerfile(autoResolveConflicts: true)
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.borderedProminent)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(NordicTheme.surfaceBackground))
                        }
                    }
                    .padding(10)
                    .background(NordicTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
                }

                // Conflict Warning & One-Click Resolution Card
                if conflictsExist || hasNameConflict {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(NordicTheme.statusAmber)
                            Text("Name or Port Conflict Detected")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NordicTheme.primaryText)
                            Spacer()
                            Button("Auto-Resolve") {
                                resolveCurrentConflicts()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NordicTheme.statusAmber)
                            .controlSize(.mini)
                        }

                        if hasNameConflict {
                            Text("• Container '\(customContainerName)' already exists.")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        if !conflictingHostPorts.isEmpty {
                            let portList = conflictingHostPorts.sorted().map(String.init).joined(separator: ", ")
                            Text("• Host port(s) \(portList) already in use by a running container.")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        }

                        Toggle("Replace existing container with same name", isOn: $replaceExistingIfConflict)
                            .font(.system(size: 11))
                            .controlSize(.small)
                    }
                    .padding(10)
                    .background(NordicTheme.statusAmber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(NordicTheme.statusAmber.opacity(0.45), lineWidth: 1)
                    )
                }

                // Container Identity & Resources
                NordicCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CONTAINER NAME")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(NordicTheme.secondaryText)
                            Spacer()
                            Button("Unique Name") {
                                customContainerName = appState.nextAvailableContainerName(basedOn: parsed.suggestedContainerName)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        }

                        TextField("Container name (e.g. my-webapp)", text: $customContainerName)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontSmall)

                        Divider().overlay(NordicTheme.borderSubtle)

                        inspectorRow(label: "Base Image (FROM)", value: parsed.baseImage)
                        if !parsed.commandArguments.isEmpty {
                            inspectorRow(label: "Command (CMD)", value: parsed.commandArguments.joined(separator: " "))
                        }

                        Divider().overlay(NordicTheme.borderSubtle)

                        HStack(spacing: 12) {
                            Stepper(value: $customCPUs, in: 1...16) {
                                Text(verbatim: "CPUs: \(customCPUs)")
                            }
                            .font(.system(size: 11))
                            Spacer()
                            HStack(spacing: 4) {
                                Text("RAM (MB):")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                NordicIntegerTextField(
                                    "1024",
                                    value: $customMemoryMB,
                                    range: 128...65536
                                )
                                .frame(width: 68)
                            }
                        }
                    }
                }

                // Editable Port Mappings
                NordicCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: "PORT MAPPINGS (\(customPorts.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NordicTheme.secondaryText)
                            Spacer()
                            Button {
                                let nextHost = appState.nextAvailableHostPort(
                                    startingAt: 8080,
                                    additionallyReserved: Set(customPorts.map(\.hostPort))
                                )
                                customPorts.append(
                                    PortMapping(hostAddress: "127.0.0.1", hostPort: nextHost, containerPort: 80, proto: "tcp")
                                )
                            } label: {
                                Label("Add Port", systemImage: "plus.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        }

                        if customPorts.isEmpty {
                            Text("No ports published. Click 'Add Port' or add EXPOSE in Dockerfile.")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            ForEach($customPorts) { $port in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("Host")
                                            .font(.system(size: 10))
                                            .foregroundStyle(NordicTheme.secondaryText)
                                        NordicPortTextField("Host", port: $port.hostPort)
                                            .frame(width: 64)
                                        Text("→")
                                            .foregroundStyle(NordicTheme.secondaryText)
                                        NordicPortTextField("Container", port: $port.containerPort)
                                            .frame(width: 64)
                                        Picker("", selection: $port.proto) {
                                            Text("tcp").tag("tcp")
                                            Text("udp").tag("udp")
                                        }
                                        .labelsHidden()
                                        .frame(width: 58)
                                        .controlSize(.small)
                                        Spacer()
                                        Button {
                                            customPorts.removeAll { $0.id == port.id }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(NordicTheme.statusRed)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    if conflictingHostPorts.contains(port.hostPort) {
                                        HStack(spacing: 4) {
                                            Text(verbatim: "Port \(port.hostPort) is in use.")
                                                .font(.system(size: 10))
                                                .foregroundStyle(NordicTheme.statusAmber)
                                            Button("Use Next Free Port") {
                                                port.hostPort = appState.nextAvailableHostPort(
                                                    startingAt: port.hostPort + 1,
                                                    additionallyReserved: Set(customPorts.map(\.hostPort))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Editable Environment Variables
                NordicCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: "ENVIRONMENT VARIABLES (\(customEnvVars.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NordicTheme.secondaryText)
                            Spacer()
                            Button {
                                customEnvVars.append(KeyValueEntry(key: "NEW_VAR", value: "value"))
                            } label: {
                                Label("Add Env", systemImage: "plus.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        }

                        if customEnvVars.isEmpty {
                            Text("No environment variables configured.")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            ForEach($customEnvVars) { $env in
                                HStack(spacing: 4) {
                                    TextField("KEY", text: $env.key)
                                        .textFieldStyle(.roundedBorder)
                                        .font(NordicTheme.monoFontSmall)
                                        .frame(width: 110)
                                    Text("=")
                                        .foregroundStyle(NordicTheme.secondaryText)
                                    TextField("Value", text: $env.value)
                                        .textFieldStyle(.roundedBorder)
                                        .font(NordicTheme.monoFontSmall)
                                    Button {
                                        customEnvVars.removeAll { $0.id == env.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(NordicTheme.statusRed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Editable Mounts / Volumes
                NordicCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(verbatim: "VOLUMES & MOUNTS (\(customMounts.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NordicTheme.secondaryText)
                            Spacer()
                            Button {
                                customMounts.append(
                                    MountAttachment(kind: .bind, source: "", destination: "/data", readOnly: false)
                                )
                            } label: {
                                Label("Add Mount", systemImage: "plus.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        }

                        if customMounts.isEmpty {
                            Text("No volumes or bind mounts configured.")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            ForEach($customMounts) { $m in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        TextField("Host path or volume", text: $m.source)
                                            .textFieldStyle(.roundedBorder)
                                            .font(NordicTheme.monoFontSmall)
                                        Button("…") {
                                            let panel = NSOpenPanel()
                                            panel.canChooseDirectories = true
                                            panel.canChooseFiles = false
                                            if panel.runModal() == .OK, let url = panel.url {
                                                m.kind = .bind
                                                m.source = url.path
                                            }
                                        }
                                        .controlSize(.mini)
                                        .help("Browse host directory")
                                        Button {
                                            customMounts.removeAll { $0.id == m.id }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(NordicTheme.statusRed)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    HStack(spacing: 4) {
                                        Text("→ Container:")
                                            .font(.system(size: 10))
                                            .foregroundStyle(NordicTheme.secondaryText)
                                        TextField("/container/path", text: $m.destination)
                                            .textFieldStyle(.roundedBorder)
                                            .font(NordicTheme.monoFontSmall)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(NordicTheme.contentSurface)
    }

    private func inspectorRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(NordicTheme.secondaryText)
            Text(value)
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.primaryText)
                .textSelection(.enabled)
        }
    }

    private var buildConsoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BUILD & DEPLOYMENT CONSOLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                Button("Clear") {
                    buildConsoleLines.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(NordicTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(NordicTheme.elevatedSurface)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(buildConsoleLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .background(NordicTheme.codeSurface)
        }
    }

    // MARK: - Actions

    private func syncSettingsFromDockerfile(autoResolveConflicts: Bool) {
        let baseReq = DockerfileParser.buildContainerCreateRequest(
            content: dockerfileText,
            sourceFileURL: currentFileURL,
            defaultCPUs: appState.preferences.defaultContainerCPUs,
            defaultMemoryMB: appState.preferences.defaultContainerMemoryMB
        )
        let resolved = autoResolveConflicts ? appState.resolveCreateRequestConflicts(baseReq) : baseReq
        customContainerName = resolved.name
        customPorts = resolved.publishedPorts
        customEnvVars = resolved.environmentVariables
        customMounts = resolved.mounts
        customCPUs = resolved.cpus
        customMemoryMB = resolved.memoryMB
    }

    private func resolveCurrentConflicts() {
        if hasNameConflict {
            customContainerName = appState.nextAvailableContainerName(basedOn: customContainerName)
        }
        var reserved = Set<UInt16>()
        customPorts = customPorts.map { p in
            let nextPort = appState.nextAvailableHostPort(startingAt: p.hostPort, additionallyReserved: reserved)
            reserved.insert(nextPort)
            return PortMapping(
                id: p.id,
                hostAddress: p.hostAddress,
                hostPort: nextPort,
                containerPort: p.containerPort,
                proto: p.proto,
                count: p.count
            )
        }
    }

    private func buildConfiguredCreateRequest() -> ContainerCreateRequest {
        var req = DockerfileParser.buildContainerCreateRequest(
            content: dockerfileText,
            sourceFileURL: currentFileURL,
            defaultCPUs: customCPUs,
            defaultMemoryMB: customMemoryMB
        )
        let trimmedName = customContainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            req.name = trimmedName
        }
        req.publishedPorts = customPorts
        req.environmentVariables = customEnvVars
        req.mounts = customMounts
        req.cpus = customCPUs
        req.memoryMB = customMemoryMB
        return req
    }

    private func updateCompletions(for prefix: String) {
        let cleaned = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            completionSuggestions = []
            return
        }
        completionSuggestions = DockerfileCompletionItem.allCatalog.filter {
            $0.label.localizedCaseInsensitiveContains(cleaned) ||
            $0.insertText.localizedCaseInsensitiveContains(cleaned)
        }
    }

    private func openDockerfileFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Open Dockerfile or Containerfile"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            currentFileURL = url
            dockerfileText = content
            syncSettingsFromDockerfile(autoResolveConflicts: true)
        }
    }

    private func saveDockerfileToDisk() {
        let panel = NSSavePanel()
        panel.title = "Save Dockerfile"
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "Dockerfile"
        if panel.runModal() == .OK, let url = panel.url {
            try? dockerfileText.write(to: url, atomically: true, encoding: .utf8)
            currentFileURL = url
        }
    }

    private func openInCreateContainerWizard() {
        let req = buildConfiguredCreateRequest()
        appState.createContainerInitialRequest = req
        appState.showCreateContainerSheet = true
    }

    private func buildAndRunImmediately() {
        isBuildingAndRunning = true
        showConsolePane = true
        buildConsoleLines = ["==> Preparing Dockerfile deployment…"]

        var createReq = buildConfiguredCreateRequest()
        let shouldReplaceExisting = replaceExistingIfConflict

        Task {
            if shouldReplaceExisting && appState.hasContainerNameConflict(createReq.name) {
                let targetName = createReq.name
                await MainActor.run {
                    self.buildConsoleLines.append("==> Removing existing container '\(targetName)' before redeploying…")
                }
                try? await appState.runtimeService.deleteContainer(id: targetName, force: true)
                await appState.refreshAll(isUserInitiated: false)
            } else if appState.hasContainerNameConflict(createReq.name) || !appState.conflictingHostPorts(for: createReq.publishedPorts).isEmpty {
                let resolved = appState.resolveCreateRequestConflicts(createReq)
                await MainActor.run {
                    if resolved.name != createReq.name {
                        self.buildConsoleLines.append("==> Container name '\(createReq.name)' is already in use; deploying as '\(resolved.name)'.")
                        self.customContainerName = resolved.name
                    }
                    if resolved.publishedPorts != createReq.publishedPorts {
                        let portsDesc = resolved.publishedPorts.map { "\($0.hostPort)->\($0.containerPort)" }.joined(separator: ", ")
                        self.buildConsoleLines.append("==> Host port conflict detected; adjusted port mapping to \(portsDesc).")
                        self.customPorts = resolved.publishedPorts
                    }
                }
                createReq = resolved
            }

            await appState.buildAndDeployContainer(
                request: createReq,
                onProgressLine: { line in
                    Task { @MainActor in
                        self.buildConsoleLines.append(line)
                    }
                },
                onComplete: {
                    Task { @MainActor in
                        self.isBuildingAndRunning = false
                    }
                }
            )
        }
    }
}

// MARK: - AppKit Syntax-Highlighted & Line-Numbered Editor

public struct DockerfileCodeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var currentWordPrefix: String
    @Binding var pendingInsertion: String?
    var onFileDrop: ((URL) -> Void)? = nil

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = DockerfileNSTextView()
        textView.onFileDrop = onFileDrop
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // Attach custom line-number ruler view
        let ruler = DockerfileLineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasHorizontalRuler = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        textView.string = text
        context.coordinator.applySyntaxHighlighting(to: textView)
        ruler.needsDisplay = true

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DockerfileNSTextView else { return }
        textView.onFileDrop = onFileDrop

        if let insertion = pendingInsertion {
            DispatchQueue.main.async {
                self.pendingInsertion = nil
                context.coordinator.insertCompletion(insertion, in: textView)
            }
            return
        }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applySyntaxHighlighting(to: textView)
            textView.selectedRanges = selectedRanges
            scrollView.verticalRulerView?.needsDisplay = true
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DockerfileCodeEditorRepresentable
        private var isUpdatingAttributes = false

        init(_ parent: DockerfileCodeEditorRepresentable) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applySyntaxHighlighting(to: textView)
            updateCursorContext(in: textView)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCursorContext(in: textView)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        public func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let nsString = textView.string as NSString
            guard charRange.location != NSNotFound,
                  charRange.location + charRange.length <= nsString.length else {
                return []
            }
            let partial = nsString.substring(with: charRange).lowercased()
            return DockerfileCompletionItem.allCatalog
                .map(\.insertText)
                .filter { $0.lowercased().hasPrefix(partial) }
        }

        func insertCompletion(_ insertion: String, in textView: NSTextView) {
            let nsString = textView.string as NSString
            let cursor = textView.selectedRange().location
            var start = cursor
            while start > 0 {
                let ch = nsString.character(at: start - 1)
                if let scalar = UnicodeScalar(ch), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    break
                }
                start -= 1
            }
            let replaceRange = NSRange(location: start, length: max(0, cursor - start))
            if textView.shouldChangeText(in: replaceRange, replacementString: insertion) {
                textView.replaceCharacters(in: replaceRange, with: insertion)
                textView.didChangeText()
            }
        }

        private func updateCursorContext(in textView: NSTextView) {
            let nsString = textView.string as NSString
            let loc = min(textView.selectedRange().location, nsString.length)
            let prefixUpToCursor = nsString.substring(to: loc)
            let lineNum = prefixUpToCursor.components(separatedBy: .newlines).count
            parent.cursorLine = max(1, lineNum)

            var wordStart = loc
            while wordStart > 0 {
                let ch = nsString.character(at: wordStart - 1)
                if let scalar = UnicodeScalar(ch), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    break
                }
                wordStart -= 1
            }
            let currentWord = nsString.substring(with: NSRange(location: wordStart, length: max(0, loc - wordStart)))
            parent.currentWordPrefix = currentWord
        }

        func applySyntaxHighlighting(to textView: NSTextView) {
            guard !isUpdatingAttributes, let storage = textView.textStorage else { return }
            isUpdatingAttributes = true
            defer { isUpdatingAttributes = false }

            let fullText = storage.string
            let fullRange = NSRange(location: 0, length: (fullText as NSString).length)
            guard fullRange.length > 0 else { return }

            let baseFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let boldFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)

            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            // 1. Highlight Dockerfile instructions at start of line
            let instructionPattern = #"(?m)^\s*(FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b"#
            if let regex = try? NSRegularExpression(pattern: instructionPattern, options: [.caseInsensitive]) {
                for match in regex.matches(in: fullText, range: fullRange) {
                    storage.addAttributes([
                        .font: boldFont,
                        .foregroundColor: NSColor.systemBlue
                    ], range: match.range(at: 1))
                }
            }

            // 2. Highlight multi-stage `AS <name>` keyword
            let asPattern = #"(?i)\b(AS)\s+[A-Za-z0-9_.-]+"#
            if let regex = try? NSRegularExpression(pattern: asPattern) {
                for match in regex.matches(in: fullText, range: fullRange) {
                    storage.addAttributes([
                        .font: boldFont,
                        .foregroundColor: NSColor.systemPurple
                    ], range: match.range(at: 1))
                }
            }

            // 3. Highlight flags (`--platform=...`, `--from=...`, `--chown=...`, `--mount=...`)
            let flagPattern = #"--[A-Za-z0-9_-]+(?:=[^\s]+)?"#
            if let regex = try? NSRegularExpression(pattern: flagPattern) {
                for match in regex.matches(in: fullText, range: fullRange) {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: match.range)
                }
            }

            // 4. Highlight quoted strings (`"..."` or `'...'`)
            let stringPattern = #""[^"\n]*"|'[^'\n]*'"#
            if let regex = try? NSRegularExpression(pattern: stringPattern) {
                for match in regex.matches(in: fullText, range: fullRange) {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
                }
            }

            // 5. Highlight environment variables (`$VAR` or `${VAR}`) and port numbers
            let varPattern = #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\b\d{2,5}/(?:tcp|udp)\b"#
            if let regex = try? NSRegularExpression(pattern: varPattern) {
                for match in regex.matches(in: fullText, range: fullRange) {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
                }
            }

            // 6. Highlight comments (`# ...`) — applied last so comments override tokens inside comments
            let commentPattern = #"(?m)^\s*#.*$"#
            if let regex = try? NSRegularExpression(pattern: commentPattern) {
                for match in regex.matches(in: fullText, range: fullRange) {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
                }
            }

            storage.endEditing()
        }
    }
}

/// Custom `NSTextView` subclass that triggers code completion via `Opt+Esc` and routes dropped Dockerfile URLs to Låda's deployment workflow.
final class DockerfileNSTextView: NSTextView {
    var onFileDrop: ((URL) -> Void)?

    override func keyDown(with event: NSEvent) {
        // Trigger completion when pressing Option+Escape or F5
        if event.keyCode == 53 && event.modifierFlags.contains(.option) {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if extractDroppedFileURL(from: sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let url = extractDroppedFileURL(from: sender) {
            onFileDrop?(url)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func extractDroppedFileURL(from sender: any NSDraggingInfo) -> URL? {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            return first
        }
        return nil
    }
}

/// Custom line-number gutter (`NSRulerView`) displaying 1-indexed row numbers for `DockerfileNSTextView`.
final class DockerfileLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill()
        rect.fill()

        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        borderPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let textInset = textView.textContainerInset
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let fullString = textView.string as NSString

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        var lineNumber = 1
        if glyphRange.location > 0 {
            let charIdx = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            lineNumber = fullString.substring(to: charIdx).components(separatedBy: .newlines).count
        }

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = fullString.lineRange(for: NSRange(location: charIndex, length: 0))
            var lineGlyphRange = NSRange()
            layoutManager.characterRange(forGlyphRange: NSRange(location: glyphIndex, length: 1), actualGlyphRange: &lineGlyphRange)

            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let yPos = lineRect.minY + textInset.height - visibleRect.minY

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - labelSize.width - 8,
                y: yPos + (lineRect.height - labelSize.height) / 2.0
            )
            label.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            glyphIndex = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil).upperBound
        }

        // If empty text view, still draw line 1
        if fullString.length == 0 {
            let label = "1" as NSString
            let labelSize = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - labelSize.width - 8, y: textInset.height), withAttributes: attrs)
        }
    }
}
