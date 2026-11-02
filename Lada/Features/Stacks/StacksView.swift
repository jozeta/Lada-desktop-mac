import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct StacksView: View {
    @ObservedObject var appState: AppState


    @ObservedObject private var work: StackWorkspace
    @State private var editTarget: ServiceEditTarget?
    @State private var nameDraft = ""
    @State private var newStackName = ""

    enum ServiceEditTarget: Identifiable {
        case add
        case edit(ComposeServiceSpec)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let svc): return "edit-\(svc.serviceName)"
            }
        }
    }

    public init(appState: AppState) {
        self.appState = appState
        self.work = appState.stacks
    }

    private var parsedStack: ParsedComposeStack { work.parsed }

    private var runningCountInStack: Int {
        parsedStack.services.filter { svc in
            appState.containers.first(where: { $0.id == svc.containerName })?.state == .running
        }.count
    }

    private var existingCountInStack: Int {
        parsedStack.services.filter { svc in
            appState.containers.contains(where: { $0.id == svc.containerName })
        }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            stacksHeader
            Divider().overlay(NordicTheme.borderSubtle)
            HStack {
                Picker("", selection: $work.tab) {
                    ForEach(StackWorkspace.Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if work.tab == .services {
                    Button {
                        if work.isEmpty { work.newStack(named: "my-stack") }
                        editTarget = .add
                    } label: {
                        Label("Add Service", systemImage: "plus")
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("lada.stacks.addService")
                    .help("Add a container to this stack with a form; the compose file is updated")
                }
                if work.tab == .logs {
                    Button {
                        Task { await work.refreshLogs(appState: appState) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
                if work.tab == .file {
                    Text("\(parsedStack.services.count) services · project \(parsedStack.projectName)")
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            .padding(.horizontal, NordicTheme.Spacing.l)
            .padding(.vertical, NordicTheme.Spacing.s)
            .nordicBar()
            .overlay(alignment: .bottom) { Divider().overlay(NordicTheme.borderSubtle) }

            switch work.tab {
            case .services:
                servicesTab
            case .file:
                composeEditorPane
            case .logs:
                unifiedLogsPane
            }
        }
        .nordicPageBackground()
        .onAppear {
            if let draftYAML = appState.editorDraftComposeYAML, !draftYAML.isEmpty {
                work.yamlText = draftYAML
                work.currentFileURL = appState.editorDraftComposeURL
                appState.editorDraftComposeYAML = nil
            }
        }
        .onChange(of: appState.editorDraftComposeYAML) { _, newValue in
            if let newValue, !newValue.isEmpty {
                work.yamlText = newValue
                work.currentFileURL = appState.editorDraftComposeURL
                appState.editorDraftComposeYAML = nil
            }
        }
        .sheet(item: $editTarget) { target in
            switch target {
            case .add:
                StackServiceEditorView(appState: appState, work: work, service: nil) { editTarget = nil }
            case .edit(let svc):
                StackServiceEditorView(appState: appState, work: work, service: svc) { editTarget = nil }
            }
        }
        .onChange(of: work.tab) { _, tab in
            if tab == .logs { Task { await work.refreshLogs(appState: appState) } }
        }
    }

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }

    /// One line about the stack's state, in words.
    private var statusText: String {
        let total = parsedStack.services.count
        if total == 0 { return "No services in the compose file" }
        if existingCountInStack == 0 { return "Not started · \(total) service\(total == 1 ? "" : "s")" }
        if runningCountInStack == total { return "Running · all \(total) services" }
        return "\(runningCountInStack) of \(total) services running"
    }

    private var stacksHeader: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: NordicTheme.Spacing.s) {
                Text("Stacks")
                    .font(NordicTheme.titleFont)
                    .foregroundStyle(NordicTheme.primaryText)
                Text("Start several containers that work together, such as a website and its database, from one docker-compose.yml file.")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(2)
            }
            HStack(spacing: NordicTheme.Spacing.m) {
                if work.isEmpty {
                    Text("No stack open. Build one yourself or start from a template below.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: NordicTheme.Spacing.s) {
                        TextField("stack name", text: $nameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NordicTheme.primaryText)
                            .fixedSize()
                            .onSubmit { work.rename(to: nameDraft) }
                            .onAppear { nameDraft = parsedStack.projectName }
                            .onChange(of: parsedStack.projectName) { _, new in nameDraft = new }
                            .help("Stack name (press Return to apply)")
                            .accessibilityIdentifier("lada.stacks.name")
                        Text(work.currentFileURL?.lastPathComponent ?? "unsaved")
                            .font(.system(size: 11))
                            .foregroundStyle(NordicTheme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(runningCountInStack > 0 ? NordicTheme.statusGreen : NordicTheme.secondaryText)
                }
                }
                Spacer()
                Menu {
                    Button("New Empty Stack") { work.newStack(named: "my-stack") }
                    Menu("Start from a Template") {
                        ForEach(ComposeStackTemplate.allTemplates) { template in
                            Button("\(template.title) — \(template.subtitle)") { work.useTemplate(template) }
                        }
                    }
                    Divider()
                    Button("Open Compose File…") { openComposeFileFromDisk() }
                    if !work.recentFiles.isEmpty {
                        Menu("Open Recent") {
                            ForEach(work.recentFiles, id: \.self) { url in
                                Button((url.path as NSString).abbreviatingWithTildeInPath) {
                                    work.open(url)
                                    work.tab = .services
                                }
                            }
                        }
                    }
                    Divider()
                    Button(work.currentFileURL == nil ? "Save…" : "Save") { saveComposeFile(forceChoose: false) }
                    Button("Save As…") { saveComposeFile(forceChoose: true) }
                } label: {
                    Label("Templates & Files", systemImage: "doc.on.doc")
                }
                .fixedSize()
                .controlSize(.small)

                if existingCountInStack > 0 {
                    Button {
                        Task { await work.stop(appState: appState) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.small)
                    .disabled(work.isDeploying || runningCountInStack == 0)
                    .help("Stop all services; they keep their data and can be started again")

                    Button(role: .destructive) {
                        Task { await work.remove(appState: appState) }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .disabled(work.isDeploying)
                    .help("Delete the stack's containers (named volumes are kept)")
                }

                Button {
                    Task { await work.start(appState: appState) }
                } label: {
                    if work.isDeploying {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                    } else {
                        Label(runningCountInStack > 0 ? "Start Missing Services" : "Start Stack", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(work.isEmpty || work.isDeploying || parsedStack.services.isEmpty || (runningCountInStack == parsedStack.services.count && !parsedStack.services.isEmpty))
                .accessibilityIdentifier("lada.stacks.start")
            }
        }
        .padding(.horizontal, NordicTheme.Spacing.l)
        .padding(.vertical, NordicTheme.Spacing.m)
        .nordicBar()
    }

    /// Services with live state, plus a short guide while nothing has been started and the
    /// activity of the last start/stop.
    private var servicesTab: some View {
        ScrollView {
            if work.isEmpty {
                emptyStart
            } else {
            VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
                if existingCountInStack == 0 && !work.isDeploying {
                    howItWorks
                }
                if !parsedStack.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(parsedStack.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11.5))
                                .foregroundStyle(NordicTheme.statusAmber)
                        }
                    }
                }
                ForEach(Array(parsedStack.topologicalServices.enumerated()), id: \.element.id) { index, svc in
                    serviceCard(for: svc, stepNumber: index + 1)
                }
                Button {
                    editTarget = .add
                } label: {
                    Label(parsedStack.services.isEmpty ? "Add the first service" : "Add another service", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NordicTheme.Spacing.s)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .background(
                    RoundedRectangle(cornerRadius: NordicTheme.Radius.card, style: .continuous)
                        .strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                if !work.consoleLines.isEmpty || work.isDeploying {
                    stackConsolePane
                        .frame(height: 180)
                        .nordicSurface()
                }
            }
            .padding(NordicTheme.Spacing.l)
            }
        }
    }

    /// The empty start: a confirmation after a successful start, then the two ways to begin.
    private var emptyStart: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
            if let started = work.lastStarted {
                HStack(spacing: NordicTheme.Spacing.m) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(NordicTheme.statusGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stack \(started.name) is running")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("All \(started.serviceCount) service\(started.serviceCount == 1 ? "" : "s") started. You'll find them grouped under \(started.name) in Containers.")
                            .font(.system(size: 12))
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                    Spacer()
                    Button("Show in Containers") {
                        appState.selectedContainerID = "stack:\(started.name)"
                        appState.selectedSection = .containers
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    Button {
                        work.lastStarted = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }
                .nordicPanel()
            }

            // 1. Build your own
            VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
                Label("Build your own stack", systemImage: "square.stack.3d.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("Name it, then add services one by one with a form (or type them in the Compose File tab).")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                HStack {
                    TextField("my-stack", text: $newStackName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit { createOwnStack() }
                        .accessibilityIdentifier("lada.stacks.newName")
                    Button("Create Stack") { createOwnStack() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("lada.stacks.create")
                }
            }
            .nordicPanel()

            // 2. Templates
            VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
                Label("Or start from a template", systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                Text("A ready-made stack you can adjust before starting. Passwords are generated for you.")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: NordicTheme.Spacing.m)], spacing: NordicTheme.Spacing.m) {
                    ForEach(ComposeStackTemplate.allTemplates) { template in
                        templateCard(template)
                    }
                }
            }
            .nordicPanel()
        }
        .padding(NordicTheme.Spacing.l)
    }

    private func templateCard(_ template: ComposeStackTemplate) -> some View {
        let services = ComposeParser.parse(yaml: template.yamlContent).services
        return Button {
            work.useTemplate(template)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(template.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                Text(template.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(services.map(\.serviceName).joined(separator: " · "))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
            .padding(NordicTheme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .nordicSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nordicHoverHighlight(accent: accent)
        .help("Use this template")
    }

    private func createOwnStack() {
        work.newStack(named: newStackName.isEmpty ? "my-stack" : newStackName)
        newStackName = ""
        editTarget = .add
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.s) {
            Text("How it works")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                guideLine("1", "Start from a template or your own compose file (Templates & Files), or from scratch with Add Service.")
                guideLine("2", "Add, edit or remove services with the form, or type in the Compose File tab. Both stay in sync.")
                guideLine("3", "Press Start Stack. Services start in order (a database before the app that needs it), and appear grouped under the stack's name in Containers.")
            }
            Text(dnsHint)
                .font(.system(size: 11.5))
                .foregroundStyle(NordicTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nordicPanel()
    }

    private var dnsHint: String {
        if let domain = appState.systemProperties.dns.domain, !domain.isEmpty {
            return "Services reach each other by service name (for example db), because the default DNS domain .\(domain) is set."
        }
        return "To let services reach each other by name (for example db), set a default DNS domain once: container system dns create test, then container system property set dns.domain test."
    }

    private func guideLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(accent.opacity(0.14)))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(NordicTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Top Toolbar

    // MARK: - Left YAML Editor

    private var composeEditorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("docker-compose.yml", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                Text(verbatim: "Project: \(parsedStack.projectName) • \(parsedStack.services.count) services")
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.clear)
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            TextEditor(text: $work.yamlText)
                .font(NordicTheme.monoFontRegular)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NordicTheme.codeSurface)
        }
    }

    // MARK: - Right Stack Inspector & Unified Logs

    private func serviceCard(for svc: ComposeServiceSpec, stepNumber: Int) -> some View {
        let liveContainer = appState.containers.first(where: { $0.id == svc.containerName })
        return NordicCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(svc.serviceName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text(ContainerModel(id: svc.containerName, imageReference: svc.imageReference, state: .unknown).shortImageReference)
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .help(svc.imageReference)
                    Spacer()
                    if let liveContainer {
                        NordicStatusBadge(containerState: liveContainer.state)
                    } else {
                        NordicStatusBadge(label: "Not started", tone: .neutral)
                    }
                }

                Text("Starts \(stepNumber == 1 ? "first" : "as number \(stepNumber)") · container \(svc.containerName)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NordicTheme.secondaryText)

                if !svc.dependsOn.isEmpty {
                    HStack(spacing: 4) {
                        Text("Waits for:")
                            .font(.system(size: 11))
                            .foregroundStyle(NordicTheme.secondaryText)
                        ForEach(svc.dependsOn, id: \.self) { dep in
                            Text(dep)
                                .font(NordicTheme.monoFontSmall)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                }

                if !svc.publishedPorts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(svc.publishedPorts) { pm in
                            let probe = appState.portHealthMap[pm.hostPort]
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(portIndicatorColor(for: probe, isRunning: liveContainer?.state == .running))
                                    .frame(width: 7, height: 7)
                                Text(verbatim: "localhost:\(pm.hostPort) → \(pm.containerPort)\(pm.proto == "udp" ? "/udp" : "")")
                                    .font(.system(size: 12).monospacedDigit())
                                    .help("On your Mac, port \(pm.hostPort) reaches port \(pm.containerPort) in the container")
                                if liveContainer?.state == .running {
                                    Button("Open") {
                                        if let url = URL(string: "http://localhost:\(pm.hostPort)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .nordicChip()
                            .help(probe?.tooltipDescription ?? "Published port \(pm.hostPort)")
                        }
                    }
                }

                Divider().overlay(NordicTheme.borderSubtle)
                HStack(spacing: 8) {
                    Button {
                        editTarget = .edit(svc)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .controlSize(.small)
                    .help("Change this service in a form; the compose file is updated")
                    Button(role: .destructive) {
                        work.yamlText = ComposeDocument.remove(service: svc.serviceName, from: work.yamlText)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .controlSize(.small)
                    .disabled(liveContainer != nil)
                    .help(liveContainer != nil ? "Remove the stack's containers first" : "Remove this service from the compose file")
                    Spacer()
                if let liveContainer {
                    HStack(spacing: 8) {
                        Button("Inspect in Containers") {
                            appState.selectedContainerID = liveContainer.id
                            appState.selectedSection = .containers
                        }
                        .controlSize(.small)

                        if liveContainer.state == .running {
                            Button("Terminal") {
                                appState.openExternalTerminalForContainer(id: liveContainer.id)
                            }
                            .controlSize(.small)

                            Button("Stop") {
                                Task {
                                    try? await appState.runtimeService.stopContainer(id: liveContainer.id, timeoutSeconds: 5)
                                    await appState.refreshAll(isUserInitiated: false)
                                }
                            }
                            .controlSize(.small)
                        } else {
                            Button("Start") {
                                Task {
                                    await appState.startContainerWithVerification(id: liveContainer.id)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                }
            }
        }
    }

    private func portIndicatorColor(for probe: PortProbeResult?, isRunning: Bool) -> Color {
        guard isRunning else { return NordicTheme.secondaryText.opacity(0.5) }
        guard let probe else { return NordicTheme.statusAmber }
        switch probe.state {
        case .healthyHTTP, .listeningTCP:
            return NordicTheme.statusGreen
        case .unreachable:
            return NordicTheme.statusAmber
        case .unknown:
            return NordicTheme.secondaryText
        }
    }


    private var unifiedLogsPane: some View {
        VStack(spacing: 0) {
            if work.logsText.isEmpty && !work.isLoadingLogs {
                NordicEmptyState(
                    icon: .activity,
                    title: "No Stack Logs Available",
                    description: "Deploy the stack first to view interleaved logs across all stack services."
                )
            } else {
                NordicLogViewer(
                    rawLogText: work.logsText,
                    searchText: $work.logSearch,
                    isPaused: $work.logPaused,
                    autoScroll: $work.logAutoScroll,
                    onRefresh: {
                        Task { await work.refreshLogs(appState: appState) }
                    }
                )
            }
        }
    }

    private var stackConsolePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Stack Orchestration Console", systemImage: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                Button("Clear") {
                    work.consoleLines.removeAll()
                }
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .nordicBar()

            ScrollView {
                Text(verbatim: work.consoleLines.joined(separator: "\n"))
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
            .background(NordicTheme.codeSurface)
        }
    }

    // MARK: - Orchestration Actions

    private func openComposeFileFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Open a compose file"
        panel.message = "docker-compose.yml, compose.yaml or any .yml/.yaml compose file"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "yml"), UTType(filenameExtension: "yaml")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            work.open(url)
            work.tab = .services
        }
    }

    /// Saves to the open file, or asks where (always for Save As).
    private func saveComposeFile(forceChoose: Bool) {
        if !forceChoose, let url = work.currentFileURL {
            try? work.yamlText.write(to: url, atomically: true, encoding: .utf8)
            work.noteRecent(url)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save compose file"
        panel.nameFieldStringValue = work.currentFileURL?.lastPathComponent ?? "compose.yaml"
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            try? work.yamlText.write(to: url, atomically: true, encoding: .utf8)
            work.currentFileURL = url
            work.noteRecent(url)
        }
    }
}
