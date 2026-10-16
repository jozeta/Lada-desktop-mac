import SwiftUI
import AppKit

public struct CreateContainerWizardView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var request: ContainerCreateRequest
    @State private var commandArgsText: String = ""
    @State private var dnsServersText: String = ""
    @State private var capAddText: String = ""
    @State private var capDropText: String = ""
    @State private var restartPolicyChoice: String = "none"
    @State private var selectedTab: WizardSection = .basic
    @State private var isSimpleMode: Bool = true
    @State private var isSubmitting = false
    @State private var deployProgressMessage: String = ""
    @State private var isDropTargeted: Bool = false
    @State private var validationErrors: [String] = []

    public enum WizardSection: String, CaseIterable, Identifiable {
        case basic = "Basic"
        case networking = "Networking"
        case storage = "Storage"
        case environment = "Environment"
        case resources = "Resources"
        case security = "Security"
        case advanced = "Advanced & Summary"

        public var id: String { rawValue }
    }

    public init(appState: AppState, initialRequest: ContainerCreateRequest? = nil) {
        self.appState = appState
        let defaultReq = initialRequest ?? ContainerCreateRequest(
            cpus: appState.preferences.defaultContainerCPUs,
            memoryMB: appState.preferences.defaultContainerMemoryMB
        )
        _request = State(initialValue: defaultReq)
        _commandArgsText = State(initialValue: Self.formatShellArguments(defaultReq.commandArguments))
        _dnsServersText = State(initialValue: defaultReq.dnsNameservers.joined(separator: ", "))
        _capAddText = State(initialValue: defaultReq.capAdd.joined(separator: ", "))
        _capDropText = State(initialValue: defaultReq.capDrop.joined(separator: ", "))
    }

    private var redactedCommandPreview: String {
        var synced = synchronizedRequest()
        if synced.imageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            synced.imageReference = "<image:tag>"
        }
        return SecretRedactor.formatCommandPreview(
            executable: appState.installation.executablePath ?? "container",
            arguments: synced.buildCLIArguments()
        )
    }

    private var activeConflictWarnings: [String] {
        var warnings: [String] = []
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && appState.containers.contains(where: { $0.id == trimmedName }) {
            warnings.append("Container name '\(trimmedName)' is already in use by an existing container.")
        }
        let usedPorts = Set(appState.containers.flatMap { $0.configuration.publishedPorts.map(\.hostPort) })
        for port in request.publishedPorts where usedPorts.contains(port.hostPort) {
            warnings.append("Host port \(port.hostPort.formatted(.number.grouping(.never))) is already mapped to another container.")
        }
        return warnings
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(request.hasAttachedDockerfile ? "Deploy Dockerfile Container" : "Create or Run Container")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NordicTheme.primaryText)
                        if request.hasAttachedDockerfile {
                            Text("DOCKERFILE PRE-POPULATED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(NordicTheme.statusGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(NordicTheme.statusGreen.opacity(0.14)))
                        }
                    }
                    Text(
                        isSimpleMode
                            ? "Simple view enabled — showing essential container deployment settings. Disable Simple View for all settings."
                            : "Full advanced configuration — all VM, networking, security, and storage settings visible."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                }
                Spacer()

                Toggle("Simple View", isOn: $isSimpleMode)
                    .toggleStyle(.switch)
                    .font(.system(size: 12, weight: .semibold))
                    .help("When enabled, shows only the basic configuration needed to deploy the container. Disable to reveal all advanced settings.")

                Divider().frame(height: 18)

                Toggle("Start Immediately", isOn: $request.startImmediately)
                    .toggleStyle(.switch)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(NordicTheme.elevatedSurface)
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            // Section Picker (only visible when Simple View is disabled)
            if !isSimpleMode {
                Picker("", selection: $selectedTab) {
                    ForEach(WizardSection.allCases) { sec in
                        Text(sec.rawValue).tag(sec)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(NordicTheme.windowBackground)
            }

            // Validation Banner
            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationErrors, id: \.self) { issue in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(NordicTheme.statusRed)
                            Text(issue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NordicTheme.primaryText)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicTheme.statusRed.opacity(0.10))
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            // Live Name / Port Conflict Warning Banner
            let conflicts = activeConflictWarnings
            if !conflicts.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NordicTheme.statusAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(conflicts, id: \.self) { warning in
                            Text(warning)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NordicTheme.primaryText)
                        }
                    }
                    Spacer()
                    Button("Auto-Resolve Conflicts") {
                        request = appState.resolveCreateRequestConflicts(request)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicTheme.statusAmber)
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicTheme.statusAmber.opacity(0.12))
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            // Live Build/Deploy Progress Strip
            if isSubmitting && !deployProgressMessage.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(deployProgressMessage)
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.primaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(NordicTheme.elevatedSurface)
            }

            // Form Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if request.hasAttachedDockerfile {
                        attachedDockerfileBanner
                    }

                    if isSimpleMode {
                        simpleConfigurationSection
                    } else {
                        switch selectedTab {
                        case .basic:
                            basicSection
                        case .networking:
                            networkingSection
                        case .storage:
                            storageSection
                        case .environment:
                            environmentSection
                        case .resources:
                            resourcesSection
                        case .security:
                            securitySection
                        case .advanced:
                            advancedAndSummarySection
                        }
                    }
                }
                .padding(20)
            }
            .background(NordicTheme.contentSurface)

            // Redacted Command Preview Strip
            VStack(alignment: .leading, spacing: 4) {
                Text("GENERATED CLI COMMAND PREVIEW (SECRETS REDACTED)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)
                Text(redactedCommandPreview)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NordicTheme.codeSurface)
            .overlay(alignment: .top) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    isSimpleMode.toggle()
                } label: {
                    Text(isSimpleMode ? "Show All Settings…" : "Switch to Simple View")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    submitCreateContainer()
                } label: {
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(request.startImmediately ? "Deploying…" : "Creating…")
                        }
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: request.startImmediately ? "play.fill" : "plus.circle.fill")
                            Text(
                                request.hasAttachedDockerfile && request.buildFromDockerfileBeforeRun
                                    ? (request.startImmediately ? "Build & Run Container" : "Build & Create Container")
                                    : (request.startImmediately ? "Run Container" : "Create Container")
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(NordicTheme.elevatedSurface)
            .overlay(alignment: .top) {
                Divider().overlay(NordicTheme.borderSubtle)
            }
        }
        .frame(minWidth: 740, minHeight: 580)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    applyDroppedDockerfile(url: url)
                }
            }
            return true
        }
    }

    // MARK: - Attached Dockerfile Banner & Simple View

    @ViewBuilder
    private var attachedDockerfileBanner: some View {
        NordicCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Dockerfile Configuration Loaded")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NordicTheme.primaryText)
                        if let srcPath = request.dockerfileSourcePath {
                            Text(srcPath)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Text("Base image: \(request.dockerfileBaseImage ?? request.imageReference) • Ports: \(request.publishedPorts.count) • Env vars: \(request.environmentVariables.count) • Mounts: \(request.mounts.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)

                    Toggle(
                        "Build OCI image from this Dockerfile before deploying (`container build`)",
                        isOn: $request.buildFromDockerfileBeforeRun
                    )
                    .font(.system(size: 11, weight: .medium))
                    .padding(.top, 2)
                }

                Spacer()

                Button("Clear Dockerfile") {
                    if let base = request.dockerfileBaseImage, !base.isEmpty {
                        request.imageReference = base
                    }
                    request.dockerfileContent = nil
                    request.dockerfileSourcePath = nil
                    request.dockerfileContextDirectory = nil
                    request.buildFromDockerfileBeforeRun = false
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var simpleConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            NordicCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Container Identity & Image")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)

                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Text("Container Name:")
                                .font(.system(size: 12, weight: .medium))
                            TextField("Optional (e.g. my-web-app)", text: $request.name)
                                .textFieldStyle(.roundedBorder)
                                .font(NordicTheme.monoFontRegular)
                        }

                        GridRow {
                            Text("Image & Tag *:")
                                .font(.system(size: 12, weight: .medium))
                            HStack(spacing: 8) {
                                TextField("e.g. nginx:1.27-alpine, postgres:16-alpine, alpine:latest", text: $request.imageReference)
                                    .textFieldStyle(.roundedBorder)
                                    .font(NordicTheme.monoFontRegular)
                                Menu("Presets") {
                                    ForEach(DockerHubService.curatedCatalog.prefix(10)) { item in
                                        Button("\(item.slug) — \(item.description.prefix(45))…") {
                                            let preset = item.buildDeployRequest(
                                                selectedTag: item.availableTags.first ?? "latest",
                                                defaultCPUs: request.cpus,
                                                defaultMemoryMB: request.memoryMB
                                            )
                                            request.imageReference = preset.imageReference
                                            if request.name.isEmpty { request.name = preset.name }
                                            if request.publishedPorts.isEmpty { request.publishedPorts = preset.publishedPorts }
                                            if request.environmentVariables.isEmpty { request.environmentVariables = preset.environmentVariables }
                                            if request.mounts.isEmpty { request.mounts = preset.mounts }
                                        }
                                    }
                                }
                                .frame(width: 95)
                            }
                        }
                    }
                }
            }

            // 2. Essential Port Mappings
            NordicCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("2. Port Forwarding")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NordicTheme.primaryText)
                            Text("Expose container ports to your Mac (`127.0.0.1:hostPort -> containerPort`).")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        Spacer()
                        Button("+ Add Port") {
                            request.publishedPorts.append(
                                PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")
                            )
                        }
                        .controlSize(.small)
                    }

                    if request.publishedPorts.isEmpty {
                        Text("No ports published. Click '+ Add Port' if this container listens on a network port.")
                            .font(.system(size: 11))
                            .foregroundStyle(NordicTheme.secondaryText)
                    } else {
                        ForEach($request.publishedPorts) { $port in
                            HStack(spacing: 8) {
                                Text("Host Port:")
                                    .font(.system(size: 11))
                                NordicPortTextField("8080", port: $port.hostPort)
                                    .frame(width: 80)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(NordicTheme.secondaryText)
                                Text("Container Port:")
                                    .font(.system(size: 11))
                                NordicPortTextField("80", port: $port.containerPort)
                                    .frame(width: 80)
                                Picker("", selection: $port.proto) {
                                    Text("TCP").tag("tcp")
                                    Text("UDP").tag("udp")
                                }
                                .labelsHidden()
                                .frame(width: 75)
                                Spacer()
                                Button {
                                    request.publishedPorts.removeAll { $0.id == port.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(NordicTheme.statusRed)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // 3. Essential Environment Variables
            NordicCard {
                NordicKeyValueEditor(
                    title: "3. Environment Variables",
                    keyPlaceholder: "VARIABLE_NAME",
                    valuePlaceholder: "value",
                    allowSecretMasking: true,
                    entries: $request.environmentVariables
                )
            }

            // 4. Essential Volumes & Resources
            HStack(alignment: .top, spacing: 14) {
                NordicCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("4. Volumes & Folder Mounts")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("+ Add Mount") {
                                request.mounts.append(
                                    MountAttachment(kind: .volume, source: "app-data", destination: "/data", readOnly: false, volumeName: "app-data")
                                )
                            }
                            .controlSize(.small)
                        }
                        if request.mounts.isEmpty {
                            Text("Ephemeral root filesystem (no persistent volume attached).")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            ForEach($request.mounts) { $m in
                                HStack(spacing: 6) {
                                    TextField("Source / Volume", text: $m.source)
                                        .textFieldStyle(.roundedBorder)
                                        .font(NordicTheme.monoFontSmall)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10))
                                    TextField("/container/path", text: $m.destination)
                                        .textFieldStyle(.roundedBorder)
                                        .font(NordicTheme.monoFontSmall)
                                    Button {
                                        request.mounts.removeAll { $0.id == m.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(NordicTheme.statusRed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                NordicCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("5. VM Compute Allocation")
                            .font(.system(size: 13, weight: .semibold))
                        Stepper("CPU Cores: \(String(request.cpus)) vCPU", value: $request.cpus, in: 1...32)
                            .font(.system(size: 12))
                        Stepper("Memory: \(String(request.memoryMB)) MiB", value: $request.memoryMB, in: 256...65536, step: 256)
                            .font(.system(size: 12))
                    }
                }
                .frame(width: 245)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Basic Configuration", subtitle: "Identity, OCI image reference, and initial command execution.")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Container Name:")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Optional (e.g. web-api, redis-dev)", text: $request.name)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                }

                GridRow {
                    Text("Image & Tag *:")
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 8) {
                        TextField("e.g. alpine:latest, nginx:1.27-alpine", text: $request.imageReference)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontRegular)
                        if !appState.images.isEmpty {
                            Menu("Local Images") {
                                ForEach(appState.images) { img in
                                    Button(img.fullReference) {
                                        request.imageReference = img.fullReference
                                    }
                                }
                            }
                            .frame(width: 120)
                        }
                    }
                }

                GridRow {
                    Text("Entrypoint Override:")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Optional (--entrypoint)", text: $request.entrypointOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                }

                GridRow {
                    Text("Command & Args:")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Optional arguments passed to container init process", text: $commandArgsText)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                }

                GridRow {
                    Text("Working Directory:")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Optional (--workdir, e.g. /app)", text: $request.workingDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                }

                GridRow {
                    Text("User / Group:")
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 8) {
                        TextField("name or uid:gid (--user)", text: $request.userSpec)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontRegular)
                        TextField("UID", text: $request.uid)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        TextField("GID", text: $request.gid)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                GridRow {
                    Text("Restart Policy:")
                        .font(.system(size: 12, weight: .medium))
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $restartPolicyChoice) {
                            Text("None (Manual — Supported)").tag("none")
                            Text("always (Unsupported by Apple container)").tag("always")
                            Text("unless-stopped (Unsupported by Apple container)").tag("unless-stopped")
                        }
                        .labelsHidden()
                        if restartPolicyChoice != "none" {
                            Text("Apple's `container` runtime does not support automatic `--restart` flags. Selecting an unsupported policy will block creation until changed back to None.")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.statusRed)
                        }
                    }
                }
            }

            Toggle("Remove container automatically when it stops (`--rm`)", isOn: $request.removeWhenStopped)
                .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var networkingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Networking & Port Forwarding", subtitle: "Attach to an isolated vmnet network and forward host ports.")

            HStack(spacing: 12) {
                Text("Network:")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $request.networkName) {
                    Text("default").tag("default")
                    ForEach(appState.networks.filter { $0.id != "default" }) { net in
                        Text("\(net.id) (\(net.ipv4Subnet))").tag(net.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Text("Custom MAC:")
                    .font(.system(size: 12, weight: .medium))
                TextField("Optional (e.g. 02:42:ac:11:00:02)", text: $request.macAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(NordicTheme.monoFontSmall)
            }

            Divider().overlay(NordicTheme.borderSubtle)

            // Published Ports Editor
            HStack {
                Text("Published Host Ports (`-p [host-ip:]host-port:container-port/proto`)")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    request.publishedPorts.append(PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp"))
                } label: {
                    Label("Add Port Mapping", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            }

            ForEach($request.publishedPorts) { $port in
                HStack(spacing: 8) {
                    TextField("Host IP", text: $port.hostAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontSmall)
                        .frame(width: 120)
                    Text(":")
                    NordicPortTextField("Host Port", port: $port.hostPort)
                        .frame(width: 80)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(NordicTheme.secondaryText)
                    NordicPortTextField("Container Port", port: $port.containerPort)
                        .frame(width: 80)
                    Picker("", selection: $port.proto) {
                        Text("tcp").tag("tcp")
                        Text("udp").tag("udp")
                    }
                    .labelsHidden()
                    .frame(width: 75)
                    Button {
                        request.publishedPorts.removeAll { $0.id == port.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(NordicTheme.statusRed)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider().overlay(NordicTheme.borderSubtle)

            Toggle("Disable DNS configuration inside container (`--no-dns`)", isOn: $request.disableDNS)
                .font(.system(size: 12))

            if !request.disableDNS {
                HStack(spacing: 12) {
                    Text("DNS Nameservers:")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Comma-separated IPs (e.g. 1.1.1.1, 8.8.8.8)", text: $dnsServersText)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontSmall)

                    Text("DNS Domain:")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Optional (e.g. test)", text: $request.dnsDomain)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontSmall)
                        .frame(width: 185)
                }
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Storage Mounts", subtitle: "Attach host directories (virtiofs), persistent ext4 named volumes, or in-memory tmpfs mounts.")

            HStack(spacing: 8) {
                Button {
                    request.mounts.append(MountAttachment(kind: .bind, source: "", destination: "/mnt/data", readOnly: false))
                } label: {
                    Label("Add Bind Mount", systemImage: "folder.badge.plus")
                }
                .controlSize(.small)

                Button {
                    let defaultVol = appState.volumes.first?.id ?? "my-volume"
                    request.mounts.append(MountAttachment(kind: .volume, source: defaultVol, destination: "/data", readOnly: false, volumeName: defaultVol))
                } label: {
                    Label("Add Named Volume", systemImage: "internaldrive")
                }
                .controlSize(.small)

                Button {
                    request.mounts.append(MountAttachment(kind: .tmpfs, source: "tmpfs", destination: "/tmp/cache", readOnly: false, options: ["size=256M"]))
                } label: {
                    Label("Add Tmpfs Mount", systemImage: "memorychip")
                }
                .controlSize(.small)
            }

            if request.mounts.isEmpty {
                Text("No additional mounts configured. The container will use its isolated root filesystem sparse image.")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            } else {
                ForEach($request.mounts) { $mount in
                    HStack(spacing: 8) {
                        Picker("", selection: $mount.kind) {
                            ForEach([MountKind.bind, .volume, .tmpfs], id: \.self) { k in
                                Text(k.displayName).tag(k)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 155)

                        if mount.kind == .bind {
                            TextField("Host Path", text: $mount.source)
                                .textFieldStyle(.roundedBorder)
                                .font(NordicTheme.monoFontSmall)
                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    mount.source = url.path
                                }
                            }
                            .controlSize(.small)
                        } else if mount.kind == .volume {
                            TextField("Volume Name", text: $mount.source)
                                .textFieldStyle(.roundedBorder)
                                .font(NordicTheme.monoFontSmall)
                                .onChange(of: mount.source) { _, newVal in
                                    mount.volumeName = newVal
                                }
                        }

                        Image(systemName: "arrow.right")
                            .foregroundStyle(NordicTheme.secondaryText)

                        TextField("Container Path (/mnt/...)", text: $mount.destination)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontSmall)

                        Toggle("RO", isOn: $mount.readOnly)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))

                        Button {
                            request.mounts.removeAll { $0.id == mount.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(NordicTheme.statusRed)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Environment Variables", subtitle: "Sensitive keys (PASSWORD, TOKEN, SECRET, KEY) are automatically masked.")

            HStack(spacing: 8) {
                Text("Environment File (`--env-file`):")
                    .font(.system(size: 12, weight: .medium))
                TextField("Optional path to .env file", text: $request.envFilePath)
                    .textFieldStyle(.roundedBorder)
                    .font(NordicTheme.monoFontSmall)
                Button("Import .env…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        importEnvFile(from: url)
                    }
                }
                .controlSize(.small)
            }

            NordicKeyValueEditor(
                title: "Environment Variables (`-e KEY=VALUE`)",
                keyPlaceholder: "VARIABLE_NAME",
                valuePlaceholder: "Value",
                allowSecretMasking: true,
                entries: $request.environmentVariables
            )
        }
    }

    @ViewBuilder
    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("VM Resource Allocation", subtitle: "Each container executes in its own lightweight Linux VM.")

            HStack(spacing: 20) {
                Stepper(value: $request.cpus, in: 1...max(16, appState.hostEnvironment.processorCount)) {
                    Text(verbatim: "Allocated CPUs (--cpus): \(request.cpus) cores")
                        .font(.system(size: 12))
                }
                Text(verbatim: "(Host physical cores: \(appState.hostEnvironment.processorCount))")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }

            HStack(spacing: 12) {
                Text("Memory Allocation (`--memory`):")
                    .font(.system(size: 12, weight: .medium))
                NordicIntegerTextField("MiB", value: $request.memoryMB, range: 128...65536)
                    .frame(width: 90)
                Text("MiB")
                Picker("Presets", selection: $request.memoryMB) {
                    Text("512 MiB").tag(512)
                    Text("1 GiB").tag(1024)
                    Text("2 GiB").tag(2048)
                    Text("4 GiB").tag(4096)
                    Text("8 GiB").tag(8192)
                    Text("16 GiB").tag(16384)
                }
                .frame(width: 140)
            }

            HStack(spacing: 12) {
                Text("Shared Memory Size (`--shm-size`):")
                    .font(.system(size: 12, weight: .medium))
                TextField("Optional (e.g. 64M, 512M, 1G)", text: $request.shmSize)
                    .textFieldStyle(.roundedBorder)
                    .font(NordicTheme.monoFontRegular)
                    .frame(width: 200)
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Security & Execution Options", subtitle: "Configure rootfs protection, Linux capabilities, init reaping, and SSH forwarding.")

            Toggle("Mount root filesystem as read-only (`--read-only`)", isOn: $request.readOnlyRootfs)
                .font(.system(size: 12))
            Toggle("Run an init process inside the container to reap zombies (`--init`)", isOn: $request.useInitProcess)
                .font(.system(size: 12))
            Toggle("Keep STDIN open (`-i / --interactive`)", isOn: $request.interactive)
                .font(.system(size: 12))
            Toggle("Allocate a pseudo-TTY (`-t / --tty`)", isOn: $request.allocateTTY)
                .font(.system(size: 12))
            Toggle("Forward host SSH agent socket (`--ssh`)", isOn: $request.sshAgentForwarding)
                .font(.system(size: 12))
            Toggle("Enable Rosetta x86_64 translation (`--rosetta`)", isOn: $request.enableRosetta)
                .font(.system(size: 12))

            HStack(spacing: 8) {
                Toggle("Expose nested virtualization (`--virtualization`)", isOn: $request.exposeVirtualization)
                    .font(.system(size: 12))
                    .disabled(!appState.capabilities.nestedVirtualization.isEnabledByDefault)
                if !appState.capabilities.nestedVirtualization.isEnabledByDefault {
                    Text(appState.capabilities.nestedVirtualization.statusDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }

            Divider().overlay(NordicTheme.borderSubtle)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Add Capabilities (`--cap-add`):")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Comma-separated (e.g. NET_ADMIN, SYS_TIME)", text: $capAddText)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontSmall)
                }
                GridRow {
                    Text("Drop Capabilities (`--cap-drop`):")
                        .font(.system(size: 12, weight: .medium))
                    TextField("Comma-separated (e.g. ALL, NET_RAW)", text: $capDropText)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontSmall)
                }
            }
        }
    }

    @ViewBuilder
    private var advancedAndSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Platform, Labels & Summary", subtitle: "Target architecture, OCI labels, and pre-flight verification.")

            HStack(spacing: 12) {
                Text("Platform Override (`--platform`):")
                    .font(.system(size: 12, weight: .medium))
                TextField("Optional (e.g. linux/arm64, linux/amd64)", text: $request.platform)
                    .textFieldStyle(.roundedBorder)
                    .font(NordicTheme.monoFontSmall)
                    .frame(width: 240)
            }

            NordicKeyValueEditor(
                title: "Container Labels (`-l key=value`)",
                keyPlaceholder: "com.example.key",
                valuePlaceholder: "value",
                allowSecretMasking: false,
                entries: $request.labels
            )
        }
    }

    // MARK: - Helpers

    private static func formatShellArguments(_ args: [String]) -> String {
        args.map { arg in
            if arg.contains(where: \.isWhitespace) || arg.contains("\"") {
                let escaped = arg.replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            return arg
        }.joined(separator: " ")
    }

    private static func parseShellArguments(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false

        for ch in raw {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && !inSingle {
                escaped = true
                continue
            }
            if ch == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if ch == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if ch.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func synchronizedRequest() -> ContainerCreateRequest {
        var copy = request
        let formattedExisting = Self.formatShellArguments(request.commandArguments)
        if commandArgsText == formattedExisting {
            copy.commandArguments = request.commandArguments
        } else {
            copy.commandArguments = Self.parseShellArguments(commandArgsText)
        }
        copy.dnsNameservers = dnsServersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        copy.capAdd = capAddText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        copy.capDrop = capDropText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        copy.requestedUnsupportedRestartPolicy = restartPolicyChoice == "none" ? nil : restartPolicyChoice
        return copy
    }

    private func importEnvFile(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts.count > 1 ? parts[1] : ""
            request.environmentVariables.append(
                KeyValueEntry(key: key, value: val, isSecret: SecretRedactor.isSensitiveKey(key))
            )
        }
    }

    private func applyDroppedDockerfile(url: URL) {
        var resolvedURL = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let candidates = ["Dockerfile", "Containerfile", "dockerfile", "containerfile"]
            if let found = candidates
                .map({ url.appendingPathComponent($0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                resolvedURL = found
            } else {
                return
            }
        }
        guard let content = try? String(contentsOf: resolvedURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let populated = DockerfileParser.buildContainerCreateRequest(
            content: content,
            sourceFileURL: resolvedURL,
            defaultCPUs: request.cpus,
            defaultMemoryMB: request.memoryMB
        )
        request = populated
        commandArgsText = Self.formatShellArguments(populated.commandArguments)
    }

    private func submitCreateContainer() {
        let finalReq = synchronizedRequest()
        let issues = ValidationUtils.validateContainerCreateRequest(finalReq)
        validationErrors = issues
        guard issues.isEmpty else { return }

        isSubmitting = true
        deployProgressMessage = finalReq.hasAttachedDockerfile && finalReq.buildFromDockerfileBeforeRun
            ? "Building Dockerfile image and preparing container deployment…"
            : "Deploying container \(finalReq.name.isEmpty ? finalReq.imageReference : finalReq.name)…"

        Task {
            await appState.buildAndDeployContainer(
                request: finalReq,
                onProgressLine: { line in
                    Task { @MainActor in
                        self.deployProgressMessage = line
                    }
                },
                onComplete: {
                    Task { @MainActor in
                        self.isSubmitting = false
                        if self.appState.activeError == nil {
                            self.dismiss()
                        }
                    }
                }
            )
        }
    }
}
