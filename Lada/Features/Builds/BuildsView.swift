import AppKit
import SwiftUI

/// Builds: turn a project folder with a Dockerfile/Containerfile into an image you can run.
/// A guided flow (folder → name → build) with everything else under Advanced options.
public struct BuildsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var work: BuildWorkspace
    @State private var showAdvanced = false
    @State private var showCommand = false

    public init(appState: AppState) {
        self.appState = appState
        self.work = appState.builds
    }

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }

    public var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
                    intro
                    folderStep
                    nameStep
                    buildStep
                    advancedOptions
                }
                .padding(NordicTheme.Spacing.xl)
            }
            .frame(minWidth: 440, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                statusPanel
                NordicLogViewer(
                    rawLogText: work.log.isEmpty ? "Build output appears here while an image builds." : work.log,
                    searchText: $work.logSearch,
                    isPaused: $work.logPaused,
                    autoScroll: $work.logAutoScroll
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                historyPanel
            }
            .frame(minWidth: 420, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            .background(NordicTheme.contentSurface)
        }
        .background(NordicTheme.windowBackground)
    }

    // MARK: - Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.xs) {
            Text("Build an image")
                .font(NordicTheme.titleFont)
                .foregroundStyle(NordicTheme.primaryText)
            Text("A build reads the Dockerfile (or Containerfile) in a project folder and turns the folder into an image. You can then run that image as a container, push it to a registry, or use it in a stack.")
                .font(.system(size: 12.5))
                .foregroundStyle(NordicTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepCard<Content: View>(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
            HStack(spacing: NordicTheme.Spacing.s) {
                ZStack {
                    Circle().fill(done ? NordicTheme.statusGreen : accent.opacity(0.15)).frame(width: 22, height: 22)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                    }
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
            }
            content()
        }
        .nordicPanel()
    }

    private var folderStep: some View {
        stepCard(1, "Choose your project folder", done: !work.folder.isEmpty && work.buildFile != nil) {
            HStack(spacing: NordicTheme.Spacing.s) {
                Image(systemName: "folder")
                    .foregroundStyle(NordicTheme.secondaryText)
                Text(work.folder.isEmpty ? "No folder chosen" : (work.folder as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12.5))
                    .foregroundStyle(work.folder.isEmpty ? NordicTheme.secondaryText : NordicTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(work.folder.isEmpty ? "Choose Folder…" : "Change…") {
                    if let path = pick(directories: true) { work.choose(folder: path) }
                }
                .accessibilityIdentifier("lada.builds.chooseFolder")
            }
            if !work.folder.isEmpty {
                if let file = work.buildFile {
                    Label {
                        Text("Uses ") + Text((file as NSString).lastPathComponent).font(.system(size: 12, design: .monospaced)) + Text(" in this folder")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NordicTheme.statusGreen)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                } else {
                    HStack {
                        Label("No Dockerfile or Containerfile in this folder.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(NordicTheme.statusAmber)
                        Spacer()
                        Button("Choose File…") {
                            if let path = pick(directories: false) { work.buildFile = path }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var nameStep: some View {
        stepCard(2, "Name the image", done: !work.imageName.isEmpty && BuildPlanner.imageNameProblem(work.imageName) == nil) {
            TextField("local/my-app:latest", text: $work.imageName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5, design: .monospaced))
                .accessibilityIdentifier("lada.builds.imageName")
            if !work.imageName.isEmpty, let problem = BuildPlanner.imageNameProblem(work.imageName) {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NordicTheme.statusAmber)
            } else {
                Text("This is the name you'll pick when you create a container. The part after ':' is the version (tag).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
        }
    }

    private var buildStep: some View {
        stepCard(3, "Build", done: { if case .succeeded = work.phase { return true }; return false }()) {
            HStack(spacing: NordicTheme.Spacing.m) {
                Button {
                    work.build(appState: appState)
                } label: {
                    Label(work.isBuilding ? "Building…" : "Build Image", systemImage: "hammer")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .disabled(work.blocker != nil || work.isBuilding)
                .accessibilityIdentifier("lada.builds.build")

                if let blocker = work.blocker {
                    Text(blocker)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(builderSummary)
                .font(.system(size: 11.5))
                .foregroundStyle(NordicTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Show the command", isExpanded: $showCommand) {
                Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: work.effectiveRequest.buildCLIArguments()))
                    .font(NordicTheme.monoFontSmall)
                    .textSelection(.enabled)
                    .padding(NordicTheme.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NordicTheme.codeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous))
            }
            .font(.system(size: 11.5))
        }
    }

    /// The BuildKit helper VM, explained instead of managed up front.
    private var builderSummary: String {
        let b = appState.builderStatus
        if b.isRunning {
            return "Builds run in a small helper VM (BuildKit), running now with \(b.cpus) vCPU and \(b.memoryBytes / (1024 * 1024 * 1024)) GB."
        }
        return "Builds run in a small helper VM (BuildKit). It starts automatically when you build."
    }

    // MARK: - Advanced

    private var advancedOptions: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
                optionRow("Extra names", help: "More names (tags) for the same image, comma-separated. CLI: -t") {
                    TextField("e.g. local/my-app:1.0, ghcr.io/me/my-app:1.0", text: $work.additionalTags)
                        .textFieldStyle(.roundedBorder)
                }
                optionRow("Build only up to stage", help: "For multi-stage Dockerfiles: stop at this stage. CLI: --target") {
                    TextField("e.g. builder (optional)", text: $work.request.targetStage)
                        .textFieldStyle(.roundedBorder)
                }
                optionRow("Platform", help: "Build for another CPU architecture, e.g. linux/amd64. Empty means this Mac (linux/arm64). CLI: --platform") {
                    TextField("linux/arm64 (default)", text: $work.request.platform)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Build everything from scratch (ignore cached steps)", isOn: $work.request.noCache)
                    .help("CLI: --no-cache")
                Toggle("Download the newest base image first", isOn: $work.request.pullLatest)
                    .help("CLI: --pull")
                Toggle("Let the build use my SSH keys (for private git repos)", isOn: $work.request.forwardSSH)
                    .help("Forwards your SSH agent into the build. CLI: --ssh default")

                NordicKeyValueEditor(
                    title: "Build arguments (values for ARG lines)",
                    keyPlaceholder: "ARG_NAME",
                    valuePlaceholder: "value",
                    allowSecretMasking: true,
                    entries: $work.request.buildArgs
                )
                .help("CLI: --build-arg")

                secretsEditor

                optionRow("Helper VM size", help: "CPU and memory for the BuildKit helper VM. CLI: --cpus / --memory") {
                    HStack {
                        Stepper("\(work.request.cpus) vCPU", value: $work.request.cpus, in: 1...16)
                        Picker("", selection: $work.request.memoryMB) {
                            Text("1 GB").tag(1024)
                            Text("2 GB").tag(2048)
                            Text("4 GB").tag(4096)
                            Text("8 GB").tag(8192)
                        }
                        .labelsHidden()
                        .fixedSize()
                        if appState.builderStatus.isRunning {
                            Button("Stop Helper VM") {
                                Task {
                                    await appState.performOperation(category: "Builds", title: "Stop BuildKit Builder", redactedCommand: "container builder stop") {
                                        try await appState.runtimeService.stopBuilder()
                                        return "Stopped the BuildKit helper VM."
                                    }
                                }
                            }
                            .controlSize(.small)
                            .help("Frees its memory; it starts again on the next build.")
                        }
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.top, NordicTheme.Spacing.s)
        } label: {
            Text("Advanced options")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NordicTheme.primaryText)
        }
        .nordicPanel()
    }

    private func optionRow<Content: View>(_ title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NordicTheme.primaryText)
            content()
        }
        .help(help)
    }

    private var secretsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Secrets (available during the build, never stored in the image)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NordicTheme.primaryText)
                .help("CLI: --secret id=…,src=… or env=…")
            ForEach($work.request.secrets) { $secret in
                HStack(spacing: 6) {
                    TextField("id", text: $secret.secretID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Picker("", selection: $secret.sourceType) {
                        Text("File").tag(BuildSecretSpec.SourceType.file)
                        Text("Variable").tag(BuildSecretSpec.SourceType.environmentVariable)
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField(secret.sourceType == .file ? "file path" : "ENV_VAR", text: $secret.sourceValue)
                        .textFieldStyle(.roundedBorder)
                    if secret.sourceType == .file {
                        Button("…") { if let path = pick(directories: false) { secret.sourceValue = path } }
                            .controlSize(.small)
                    }
                    Button(role: .destructive) {
                        work.request.secrets.removeAll { $0.id == secret.id }
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(NordicTheme.statusRed)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                work.request.secrets.append(BuildSecretSpec())
            } label: {
                Label("Add Secret", systemImage: "plus")
            }
            .controlSize(.small)
        }
    }

    // MARK: - Status, output, history

    @ViewBuilder
    private var statusPanel: some View {
        HStack(alignment: .top, spacing: NordicTheme.Spacing.m) {
            switch work.phase {
            case .idle:
                Image(systemName: "hammer").foregroundStyle(NordicTheme.secondaryText)
                Text(work.blocker.map { "Not ready yet: \($0)" } ?? "Ready to build \(work.imageName) from \((work.folder as NSString).lastPathComponent).")
                    .foregroundStyle(NordicTheme.secondaryText)
            case .building:
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    if let p = BuildPlanner.progress(in: work.log) {
                        Text("Building — step \(p.step) of \(p.total)").fontWeight(.semibold)
                        Text(p.description)
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text("Building — preparing…").fontWeight(.semibold)
                    }
                }
            case .succeeded(let image, let seconds):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(NordicTheme.statusGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Built \(image) in \(seconds) s").fontWeight(.semibold)
                    Text("Run it as a container, or find it under Images.")
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                Spacer()
                Button("Run This Image…") {
                    appState.presentCreateContainer(with: ContainerCreateRequest(imageReference: image))
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .accessibilityIdentifier("lada.builds.runImage")
            case .failed(let reason):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(NordicTheme.statusRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The build failed").fontWeight(.semibold)
                    Text(reason)
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .padding(NordicTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .bottom) { Divider().overlay(NordicTheme.borderSubtle) }
        .animation(NordicTheme.Motion.standard, value: work.phase)
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.s) {
            HStack {
                Text("Recent builds")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Click one to build it again")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            if appState.buildHistory.isEmpty {
                Text("No builds yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NordicTheme.secondaryText)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(appState.buildHistory.prefix(30)) { record in
                            Button { work.reuse(record) } label: { historyRow(record) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(NordicTheme.Spacing.l)
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .top) { Divider().overlay(NordicTheme.borderSubtle) }
    }

    private func historyRow(_ record: BuildRecord) -> some View {
        HStack(spacing: NordicTheme.Spacing.s) {
            Image(systemName: record.status == .succeeded ? "checkmark.circle.fill" : record.status == .running ? "clock" : "xmark.circle.fill")
                .foregroundStyle(record.status == .succeeded ? NordicTheme.statusGreen : record.status == .running ? NordicTheme.statusAmber : NordicTheme.statusRed)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.tags.first ?? "image")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NordicTheme.primaryText)
                Text(Self.sourceDescription(record.contextDirectory))
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                if let end = record.finishedAt {
                    Text("\(Int(end.timeIntervalSince(record.startedAt).rounded())) s")
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(NordicTheme.secondaryText)
        }
        .padding(.horizontal, NordicTheme.Spacing.s)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    /// Builds started from the Dockerfile Editor run in a temporary folder; name the source instead.
    static func sourceDescription(_ folder: String) -> String {
        let name = (folder as NSString).lastPathComponent
        return name.hasPrefix("com.lada.dockerfile-build") ? "from Dockerfile Editor" : "from \(name)"
    }

    private func pick(directories: Bool) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        panel.allowsMultipleSelection = false
        if !work.folder.isEmpty { panel.directoryURL = URL(fileURLWithPath: work.folder) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
