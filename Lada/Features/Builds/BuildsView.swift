import AppKit
import SwiftUI

public struct BuildsView: View {
    @ObservedObject var appState: AppState
    @State private var buildRequest: ImageBuildRequest
    @State private var primaryTag = "local/lada-app:latest"
    @State private var additionalTagsText = ""
    @State private var builderCPUs = 2
    @State private var builderMemoryMB = 2048
    @State private var isBuilding = false
    @State private var activeBuildLogs = ""
    @State private var logSearchText = ""
    @State private var logIsPaused = false
    @State private var logAutoScroll = true

    public init(appState: AppState) {
        self.appState = appState
        _buildRequest = State(initialValue: ImageBuildRequest(
            contextDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            containerfilePath: "Containerfile",
            tags: ["local/lada-app:latest"],
            cpus: appState.preferences.defaultBuildCPUs,
            memoryMB: appState.preferences.defaultBuildMemoryMB
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            builderControlBar
            HSplitView {
                buildConfigurationPanel
                    .frame(minWidth: 420, idealWidth: 470, maxWidth: .infinity, maxHeight: .infinity)

                buildOutputAndHistoryPanel
                    .frame(minWidth: 420, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(NordicTheme.windowBackground)
    }

    private var builderControlBar: some View {
        HStack(spacing: 12) {
            LadaIcon(.builds, size: 18)
                .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("BuildKit Builder VM")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    NordicStatusBadge(
                        label: appState.builderStatus.state.capitalized,
                        tone: appState.builderStatus.isRunning ? .positive : .neutral
                    )
                }
                Text(verbatim: "Image: \(appState.builderStatus.imageReference ?? "ghcr.io/apple/container-builder-shim/builder") • \(appState.builderStatus.cpus) CPUs • \(appState.builderStatus.memoryBytes / (1024 * 1024)) MB RAM")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 8) {
                Stepper(value: $builderCPUs, in: 1...16) {
                    Text(verbatim: "CPUs: \(builderCPUs)")
                }
                .font(.system(size: 11))
                Picker("RAM", selection: $builderMemoryMB) {
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("8 GB").tag(8192)
                }
                .labelsHidden()
                .frame(width: 85)
                .controlSize(.small)

                if appState.builderStatus.isRunning {
                    Button("Stop Builder") {
                        Task {
                            await appState.performOperation(
                                category: "Builds",
                                title: "Stop BuildKit Builder",
                                redactedCommand: "container builder stop"
                            ) {
                                try await appState.runtimeService.stopBuilder()
                                return "Stopped BuildKit builder container."
                            }
                        }
                    }
                    .controlSize(.small)
                } else {
                    Button("Start Builder") {
                        Task {
                            await appState.performOperation(
                                category: "Builds",
                                title: "Start BuildKit Builder",
                                redactedCommand: "container builder start --cpus \(builderCPUs) --memory \(builderMemoryMB)M"
                            ) {
                                try await appState.runtimeService.startBuilder(cpus: builderCPUs, memoryMB: builderMemoryMB)
                                return "Started BuildKit builder container."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var buildConfigurationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NordicSectionHeader(
                    "Build Image from Containerfile / Dockerfile",
                    subtitle: "Invoke `container build` with BuildKit multi-platform and secret support"
                )

                Form {
                    Section("Build Context & File") {
                        HStack {
                            TextField("Context Directory", text: $buildRequest.contextDirectory)
                                .font(NordicTheme.monoFontSmall)
                            Button("Browse…") {
                                chooseDirectory { path in buildRequest.contextDirectory = path }
                            }
                        }
                        HStack {
                            TextField("Containerfile / Dockerfile Path", text: $buildRequest.containerfilePath)
                                .font(NordicTheme.monoFontSmall)
                            Button("Select File…") {
                                chooseFile { path in buildRequest.containerfilePath = path }
                            }
                        }
                    }

                    Section("Tags & Target Stage") {
                        TextField("Primary Tag (e.g. local/myapp:latest)", text: $primaryTag)
                            .font(NordicTheme.monoFontSmall)
                            .onChange(of: primaryTag) { _, _ in syncTags() }
                        TextField("Additional Tags (comma-separated)", text: $additionalTagsText)
                            .font(NordicTheme.monoFontSmall)
                            .onChange(of: additionalTagsText) { _, _ in syncTags() }
                        TextField("Target Stage (--target, optional)", text: $buildRequest.targetStage)
                            .font(NordicTheme.monoFontSmall)
                    }

                    Section("Platform, Resources & Cache") {
                        TextField("Platform (--platform, e.g. linux/arm64)", text: $buildRequest.platform)
                            .font(NordicTheme.monoFontSmall)
                        Stepper(value: $buildRequest.cpus, in: 1...32) {
                            Text(verbatim: "Build CPUs: \(buildRequest.cpus)")
                        }
                        Picker("Build Memory", selection: $buildRequest.memoryMB) {
                            Text("1 GB").tag(1024)
                            Text("2 GB").tag(2048)
                            Text("4 GB").tag(4096)
                            Text("8 GB").tag(8192)
                        }
                        Toggle("Disable Build Cache (--no-cache)", isOn: $buildRequest.noCache)
                        Toggle("Always Pull Base Images (--pull)", isOn: $buildRequest.pullLatest)
                        Toggle("Forward Host SSH Agent (--ssh default)", isOn: $buildRequest.forwardSSH)
                    }

                    Section("Build Arguments (--build-arg)") {
                        NordicKeyValueEditor(
                            title: "Build-Time Arguments",
                            keyPlaceholder: "ARG_NAME",
                            valuePlaceholder: "Value",
                            allowSecretMasking: true,
                            entries: $buildRequest.buildArgs
                        )
                    }

                    Section("Build Secrets (--secret)") {
                        Text("Secrets are mounted securely inside BuildKit without persisting in image layers.")
                            .font(.system(size: 11))
                            .foregroundStyle(NordicTheme.secondaryText)
                        ForEach($buildRequest.secrets) { $secret in
                            HStack(spacing: 6) {
                                TextField("Secret ID", text: $secret.secretID)
                                    .textFieldStyle(.roundedBorder)
                                    .font(NordicTheme.monoFontSmall)
                                    .frame(width: 110)
                                Picker("", selection: $secret.sourceType) {
                                    Text("File").tag(BuildSecretSpec.SourceType.file)
                                    Text("Env").tag(BuildSecretSpec.SourceType.environmentVariable)
                                }
                                .frame(width: 75)
                                TextField(secret.sourceType == .file ? "File path" : "ENV_VAR", text: $secret.sourceValue)
                                    .textFieldStyle(.roundedBorder)
                                    .font(NordicTheme.monoFontSmall)
                                if secret.sourceType == .file {
                                    Button("File…") {
                                        chooseFile { path in secret.sourceValue = path }
                                    }
                                    .controlSize(.small)
                                }
                                Button(role: .destructive) {
                                    buildRequest.secrets.removeAll { $0.id == secret.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(NordicTheme.statusRed)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button {
                            buildRequest.secrets.append(BuildSecretSpec())
                        } label: {
                            Label("Add Secret Mount", systemImage: "plus")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                    }
                }
                .formStyle(.grouped)

                Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: buildRequest.buildCLIArguments()))
                    .font(NordicTheme.monoFontSmall)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NordicTheme.codeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))

                HStack {
                    Spacer()
                    Button {
                        syncTags()
                        runBuild()
                    } label: {
                        Label(isBuilding ? "Building Image…" : "Start Build", systemImage: "hammer.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    .disabled(isBuilding || buildRequest.contextDirectory.isEmpty)
                }
            }
            .padding(16)
        }
    }

    private var buildOutputAndHistoryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            NordicLogViewer(
                rawLogText: activeBuildLogs.isEmpty ? "Ready to build. Streaming BuildKit output will appear here." : activeBuildLogs,
                searchText: $logSearchText,
                isPaused: $logIsPaused,
                autoScroll: $logAutoScroll
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(NordicTheme.borderSubtle)

            VStack(alignment: .leading, spacing: 8) {
                NordicSectionHeader("Build History (\(appState.buildHistory.count))")
                if appState.buildHistory.isEmpty {
                    Text("No builds executed yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .padding(.vertical, 6)
                } else {
                    List(appState.buildHistory) { record in
                        Button {
                            activeBuildLogs = record.logOutput
                        } label: {
                            HStack {
                                NordicStatusBadge(
                                    label: record.status.rawValue,
                                    tone: record.status == .succeeded ? .positive : (record.status == .running ? .warning : .critical)
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.tags.joined(separator: ", "))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(record.contextDirectory)
                                        .font(NordicTheme.monoFontSmall)
                                        .foregroundStyle(NordicTheme.secondaryText)
                                }
                                Spacer()
                                Text(record.startedAt.formatted(date: .omitted, time: .standard))
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .frame(height: 140)
                }
            }
            .padding(14)
            .background(NordicTheme.elevatedSurface)
        }
        .background(NordicTheme.contentSurface)
    }

    private func runBuild() {
        isBuilding = true
        activeBuildLogs = ""
        let req = buildRequest
        var record = BuildRecord(
            tags: req.tags,
            contextDirectory: req.contextDirectory,
            containerfilePath: req.containerfilePath,
            status: .running
        )
        appState.appendBuildRecord(record)

        Task {
            do {
                let result = try await appState.runtimeService.buildImage(request: req) { line in
                    Task { @MainActor in
                        activeBuildLogs += line + "\n"
                    }
                }
                record.finishedAt = Date()
                record.exitCode = result.exitStatus
                record.status = result.isSuccess ? .succeeded : .failed
                record.logOutput = activeBuildLogs.isEmpty ? result.combinedOutput : activeBuildLogs
                appState.appendBuildRecord(record)
                appState.recordActivity(
                    category: "Builds",
                    title: "Build \(req.tags.first ?? "Image")",
                    detail: "Completed with exit code \(result.exitStatus).",
                    redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments()),
                    outcome: result.isSuccess ? .success : .failure
                )
                await appState.refreshAll(isUserInitiated: false)
            } catch {
                record.finishedAt = Date()
                record.status = .failed
                record.logOutput = activeBuildLogs + "\n" + error.localizedDescription
                appState.appendBuildRecord(record)
            }
            isBuilding = false
        }
    }

    private func syncTags() {
        var tags: [String] = []
        let primary = primaryTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { tags.append(primary) }
        let extras = additionalTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        tags.append(contentsOf: extras)
        buildRequest.tags = tags.isEmpty ? ["local/lada-build:latest"] : tags
    }

    private func chooseDirectory(onPick: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url.path)
        }
    }

    private func chooseFile(onPick: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url.path)
        }
    }
}
