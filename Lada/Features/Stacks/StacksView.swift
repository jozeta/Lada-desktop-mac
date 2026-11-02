import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct StacksView: View {
    @ObservedObject var appState: AppState


    @ObservedObject private var work: StackWorkspace

    public init(appState: AppState) {
        self.appState = appState
        self.work = appState.stacks
    }

    private var parsedStack: ParsedComposeStack {
        ComposeParser.parse(yaml: work.yamlText)
    }

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
                if work.tab == .logs {
                    Button {
                        Task { await refreshUnifiedLogs() }
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
            .background(NordicTheme.elevatedSurface)
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
        .background(NordicTheme.windowBackground)
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
        .onChange(of: work.tab) { _, tab in
            if tab == .logs { Task { await refreshUnifiedLogs() } }
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: NordicTheme.Spacing.s) {
                        Text(parsedStack.projectName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NordicTheme.primaryText)
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
                Spacer()
                Menu {
                    Section("Start from a template") {
                        ForEach(ComposeStackTemplate.allTemplates) { template in
                            Button("\(template.title) — \(template.subtitle)") {
                                work.currentFileURL = nil
                                work.yamlText = template.yamlContent
                                work.tab = .services
                            }
                        }
                    }
                    Divider()
                    Button("Open docker-compose.yml…") { openComposeFileFromDisk() }
                    Button("Save Compose File…") { saveComposeFileToDisk() }
                } label: {
                    Label("Templates & Files", systemImage: "doc.on.doc")
                }
                .fixedSize()
                .controlSize(.small)

                if existingCountInStack > 0 {
                    Button {
                        Task { await stopStackServices() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.small)
                    .disabled(work.isDeploying || runningCountInStack == 0)
                    .help("Stop all services; they keep their data and can be started again")

                    Button(role: .destructive) {
                        Task { await deleteStackServices() }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .disabled(work.isDeploying)
                    .help("Delete the stack's containers (named volumes are kept)")
                }

                Button {
                    Task { await deployEntireStack() }
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
                .disabled(work.isDeploying || parsedStack.services.isEmpty || (runningCountInStack == parsedStack.services.count && !parsedStack.services.isEmpty))
                .accessibilityIdentifier("lada.stacks.start")
            }
        }
        .padding(.horizontal, NordicTheme.Spacing.l)
        .padding(.vertical, NordicTheme.Spacing.m)
        .background(NordicTheme.elevatedSurface)
    }

    /// Services with live state, plus a short guide while nothing has been started and the
    /// activity of the last start/stop.
    private var servicesTab: some View {
        ScrollView {
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
                if !work.consoleLines.isEmpty || work.isDeploying {
                    stackConsolePane
                        .frame(height: 180)
                        .nordicSurface()
                }
            }
            .padding(NordicTheme.Spacing.l)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.s) {
            Text("How it works")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                guideLine("1", "Pick a template under Templates & Files, or open your own docker-compose.yml.")
                guideLine("2", "Check the services below. Edit the Compose File tab to change images, ports or settings.")
                guideLine("3", "Press Start Stack. Services start in order (a database before the app that needs it).")
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
            .background(NordicTheme.surfaceBackground)
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
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(NordicTheme.elevatedSurface)
                            )
                            .help(probe?.tooltipDescription ?? "Published port \(pm.hostPort)")
                        }
                    }
                }

                if let liveContainer {
                    Divider().overlay(NordicTheme.borderSubtle)
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
                        Task { await refreshUnifiedLogs() }
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
            .background(NordicTheme.elevatedSurface)

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

    private func deployEntireStack() async {
        work.isDeploying = true
        work.consoleLines = ["==> Deploying stack '\(parsedStack.projectName)' (\(parsedStack.services.count) services)…"]
        defer { work.isDeploying = false }

        // 1. Ensure declared named volumes exist
        let existingVolNames = Set(appState.volumes.map(\.name))
        for vol in parsedStack.declaredVolumes where !existingVolNames.contains(vol) {
            work.consoleLines.append("==> Creating named volume '\(vol)'…")
            try? await appState.runtimeService.createVolume(
                request: VolumeCreateRequest(name: vol, sizeSpec: "2G")
            )
        }

        // 2. Deploy each service in topological order
        for svc in parsedStack.topologicalServices {
            if let existing = appState.containers.first(where: { $0.id == svc.containerName }) {
                if existing.state == .running {
                    work.consoleLines.append("==> Service '\(svc.serviceName)' (\(svc.containerName)) is already running.")
                    continue
                } else {
                    work.consoleLines.append("==> Removing stopped container '\(svc.containerName)' before re-creating…")
                    try? await appState.runtimeService.deleteContainer(id: svc.containerName, force: true)
                }
            }

            // Give each service its name (plus Compose `aliases:`) as DNS aliases so peers can
            // reach it as e.g. `db`, the way Compose does.
            let dnsDomain = appState.systemProperties.dns.domain
            let resolved = ComposeParser.serviceDNSAliases(
                for: svc,
                defaultDNSDomain: dnsDomain,
                claimedNames: ComposeParser.claimedDNSNames(in: appState.containers, network: "default", defaultDNSDomain: dnsDomain, excluding: svc.containerName)
            )
            for note in resolved.notes {
                work.consoleLines.append("    ! \(note)")
            }
            let req = ComposeParser.buildContainerRequest(
                for: svc,
                projectName: parsedStack.projectName,
                networkName: "default",
                defaultCPUs: appState.preferences.defaultContainerCPUs,
                defaultMemoryMB: appState.preferences.defaultContainerMemoryMB,
                dnsAliases: resolved.aliases
            )
            if !resolved.aliases.isEmpty {
                work.consoleLines.append("    DNS aliases: \(resolved.aliases.joined(separator: ", "))")
            }

            work.consoleLines.append("==> Starting service '\(svc.serviceName)' (\(svc.imageReference))…")
            do {
                let id = try await appState.runtimeService.createOrRunContainer(request: req)
                work.consoleLines.append("    ✓ Started '\(id)'")
            } catch {
                work.consoleLines.append("    ✗ Failed to start '\(svc.serviceName)': \(error.localizedDescription)")
            }
        }

        await appState.refreshAll(isUserInitiated: false)
        work.consoleLines.append("==> Stack '\(parsedStack.projectName)' orchestration finished.")
        await refreshUnifiedLogs()
    }

    private func stopStackServices() async {
        work.isDeploying = true
        work.consoleLines.append("==> Stopping stack '\(parsedStack.projectName)'…")
        defer { work.isDeploying = false }

        // Stop in reverse dependency order
        for svc in parsedStack.topologicalServices.reversed() {
            if appState.containers.first(where: { $0.id == svc.containerName })?.state == .running {
                work.consoleLines.append("==> Stopping '\(svc.containerName)'…")
                try? await appState.runtimeService.stopContainer(id: svc.containerName, timeoutSeconds: 5)
            }
        }
        await appState.refreshAll(isUserInitiated: false)
        work.consoleLines.append("==> Stack stopped.")
    }

    private func deleteStackServices() async {
        work.isDeploying = true
        work.consoleLines.append("==> Deleting all containers in stack '\(parsedStack.projectName)'…")
        defer { work.isDeploying = false }

        for svc in parsedStack.topologicalServices.reversed() {
            if appState.containers.contains(where: { $0.id == svc.containerName }) {
                work.consoleLines.append("==> Deleting '\(svc.containerName)'…")
                try? await appState.runtimeService.deleteContainer(id: svc.containerName, force: true)
            }
        }
        await appState.refreshAll(isUserInitiated: false)
        work.consoleLines.append("==> Stack containers deleted.")
    }

    private func refreshUnifiedLogs() async {
        work.isLoadingLogs = true
        defer { work.isLoadingLogs = false }
        var combined: [String] = []
        for svc in parsedStack.topologicalServices {
            guard appState.containers.contains(where: { $0.id == svc.containerName }) else { continue }
            if let log = try? await appState.runtimeService.fetchContainerLogs(
                id: svc.containerName,
                bootLogs: false,
                tailLines: 60
            ) {
                let prefixed = log
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { "[\(svc.serviceName)] \($0)" }
                    .joined(separator: "\n")
                if !prefixed.isEmpty {
                    combined.append(prefixed)
                }
            }
        }
        work.logsText = combined.joined(separator: "\n")
    }

    private func openComposeFileFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Open docker-compose.yml"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            work.currentFileURL = url
            work.yamlText = content
        }
    }

    private func saveComposeFileToDisk() {
        let panel = NSSavePanel()
        panel.title = "Save docker-compose.yml"
        panel.nameFieldStringValue = work.currentFileURL?.lastPathComponent ?? "docker-compose.yml"
        if panel.runModal() == .OK, let url = panel.url {
            try? work.yamlText.write(to: url, atomically: true, encoding: .utf8)
            work.currentFileURL = url
        }
    }
}
