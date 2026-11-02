import SwiftUI

/// Adds or edits one service of a stack. Saving writes the service's block into the compose file
/// (`ComposeDocument.upsert`), so the form and the Compose File tab stay in sync.
struct StackServiceEditorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var work: StackWorkspace
    /// Nil when adding a new service.
    let originalName: String?
    let onDone: () -> Void

    @State private var draft: ComposeServiceSpec

    init(appState: AppState, work: StackWorkspace, service: ComposeServiceSpec?, onDone: @escaping () -> Void) {
        self.appState = appState
        self.work = work
        self.originalName = service?.serviceName
        self.onDone = onDone
        _draft = State(initialValue: service ?? ComposeServiceSpec(serviceName: "", containerName: "", imageReference: ""))
    }

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }
    private var otherServices: [String] {
        work.parsed.services.map(\.serviceName).filter { $0 != originalName }
    }

    /// What blocks saving, in plain words.
    private var problem: String? {
        let name = draft.serviceName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Give the service a name, for example web or db." }
        if name.range(of: #"^[a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) == nil {
            return "Service names use lowercase letters, digits, '-' or '_'."
        }
        if otherServices.contains(name) { return "There is already a service called \(name)." }
        if draft.imageReference.trimmingCharacters(in: .whitespaces).isEmpty && (draft.buildContext ?? "").isEmpty {
            return "Choose the image the service runs."
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(originalName == nil ? "Add a service" : "Edit \(originalName!)")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Saving updates the compose file")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .padding(NordicTheme.Spacing.l)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
                    field("Service name", hint: "Other services reach it by this name.") {
                        TextField("web", text: $draft.serviceName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("lada.stacks.service.name")
                    }
                    field("Image", hint: "Type to search images on this Mac and in the Image Library, or start from a preset.") {
                        HStack(alignment: .top) {
                            ImageReferenceField(
                                text: $draft.imageReference,
                                placeholder: "nginx:1.31-alpine",
                                localReferences: appState.images.map(\.fullReference),
                                accent: accent
                            )
                            Menu("Presets") {
                                ForEach(DockerHubService.curatedCatalog) { item in
                                    Button("\(item.name) — \(item.category.rawValue)") { applyPreset(item) }
                                }
                            }
                            .fixedSize()
                        }
                    }
                    portsEditor
                    NordicKeyValueEditor(
                        title: "Settings (environment variables)",
                        keyPlaceholder: "NAME",
                        valuePlaceholder: "value",
                        allowSecretMasking: true,
                        entries: $draft.environment
                    )
                    volumesEditor
                    if !otherServices.isEmpty {
                        field("Waits for", hint: "Start these services first (for example the database before the app).") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(otherServices, id: \.self) { other in
                                    Toggle(other, isOn: Binding(
                                        get: { draft.dependsOn.contains(other) },
                                        set: { on in
                                            draft.dependsOn.removeAll { $0 == other }
                                            if on { draft.dependsOn.append(other) }
                                        }
                                    ))
                                }
                            }
                        }
                    }
                    field("Command (optional)", hint: "Replaces the image's default command.") {
                        TextField("e.g. npm start", text: $draft.commandOverride)
                            .textFieldStyle(.roundedBorder)
                    }
                    DisclosureGroup("Compose file preview") {
                        Text(ComposeDocument.serviceBlock(normalized, projectName: work.parsed.projectName))
                            .font(NordicTheme.monoFontSmall)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(NordicTheme.Spacing.s)
                            .background(NordicTheme.codeSurface)
                            .clipShape(RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous))
                    }
                    .font(.system(size: 12))
                }
                .padding(NordicTheme.Spacing.l)
            }

            Divider()
            HStack {
                if let problem {
                    Text(problem)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NordicTheme.statusAmber)
                }
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(originalName == nil ? "Add Service" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("lada.stacks.service.save")
            }
            .padding(NordicTheme.Spacing.l)
        }
        .frame(width: 620, height: 680)
        .background(NordicTheme.windowBackground)
    }

    private var normalized: ComposeServiceSpec {
        var svc = draft
        svc.serviceName = svc.serviceName.trimmingCharacters(in: .whitespaces)
        svc.imageReference = svc.imageReference.trimmingCharacters(in: .whitespaces)
        svc.publishedPorts = svc.publishedPorts.filter { $0.containerPort > 0 }
        svc.volumes = svc.volumes.filter { !$0.destination.isEmpty && !$0.source.isEmpty }
        return svc
    }

    private func save() {
        guard problem == nil else { return }
        work.yamlText = ComposeDocument.upsert(normalized, replacing: originalName, in: work.yamlText)
        onDone()
    }

    /// Fills image, ports, settings (with fresh random secrets) and storage from a library preset.
    private func applyPreset(_ item: DockerHubRepositoryItem) {
        let req = item.buildDeployRequest(selectedTag: item.availableTags.first ?? "latest")
        draft.imageReference = req.imageReference
        if draft.serviceName.isEmpty { draft.serviceName = item.name.lowercased().replacingOccurrences(of: "[^a-z0-9_-]", with: "-", options: .regularExpression) }
        if draft.publishedPorts.isEmpty { draft.publishedPorts = req.publishedPorts }
        if draft.environment.isEmpty { draft.environment = req.environmentVariables }
        if draft.volumes.isEmpty { draft.volumes = req.mounts }
        if draft.commandOverride.isEmpty { draft.commandOverride = req.commandArguments.joined(separator: " ") }
    }

    // MARK: - Sub-editors

    private var portsEditor: some View {
        field("Ports", hint: "Make a port in the container reachable on your Mac (localhost).") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft.publishedPorts) { $port in
                    HStack(spacing: 6) {
                        Text("localhost:").font(.system(size: 12)).foregroundStyle(NordicTheme.secondaryText)
                        NordicPortTextField("Mac port", port: $port.hostPort).frame(width: 80)
                        Image(systemName: "arrow.right").foregroundStyle(NordicTheme.secondaryText)
                        NordicPortTextField("Container port", port: $port.containerPort).frame(width: 80)
                        Picker("", selection: $port.proto) {
                            Text("TCP").tag("tcp")
                            Text("UDP").tag("udp")
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button(role: .destructive) {
                            draft.publishedPorts.removeAll { $0.id == port.id }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(NordicTheme.statusRed)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    draft.publishedPorts.append(PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp"))
                } label: {
                    Label("Add Port", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
    }

    private var volumesEditor: some View {
        field("Storage", hint: "Keep data outside the container: a named volume, or a folder on your Mac.") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft.volumes) { $mount in
                    HStack(spacing: 6) {
                        Picker("", selection: $mount.kind) {
                            Text("Volume").tag(MountKind.volume)
                            Text("Mac folder").tag(MountKind.bind)
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField(mount.kind == .volume ? "volume name" : "/Users/me/data", text: Binding(
                            get: { mount.source },
                            set: { mount.source = $0; if mount.kind == .volume { mount.volumeName = $0 } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(NordicTheme.secondaryText)
                        TextField("/path/in/container", text: $mount.destination)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Read-only", isOn: $mount.readOnly)
                            .toggleStyle(.checkbox)
                            .fixedSize()
                        Button(role: .destructive) {
                            draft.volumes.removeAll { $0.id == mount.id }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(NordicTheme.statusRed)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    draft.volumes.append(MountAttachment(kind: .volume, source: "", destination: "", readOnly: false))
                } label: {
                    Label("Add Storage", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
    }

    private func field<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NordicTheme.primaryText)
            content()
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(NordicTheme.secondaryText)
        }
    }
}
