import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct StacksView: View {
    @ObservedObject var appState: AppState

    @State private var yamlText: String = ComposeStackTemplate.allTemplates[0].yamlContent
    @State private var currentFileURL: URL? = nil
    @State private var isDeployingStack: Bool = false
    @State private var stackConsoleLines: [String] = []
    @State private var selectedInspectorTab: StackInspectorTab = .topology
    @State private var unifiedLogsText: String = ""
    @State private var isLoadingUnifiedLogs: Bool = false

    public enum StackInspectorTab: String, CaseIterable, Identifiable {
        case topology = "Services & Status"
        case logs = "Unified Stack Logs"

        public var id: String { rawValue }
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    private var parsedStack: ParsedComposeStack {
        ComposeParser.parse(yaml: yamlText)
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
            stacksToolbar
            Divider().overlay(NordicTheme.borderSubtle)

            HSplitView {
                // Left Pane: Compose YAML Editor + Console Output
                VStack(spacing: 0) {
                    composeEditorPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !stackConsoleLines.isEmpty || isDeployingStack {
                        Divider().overlay(NordicTheme.borderSubtle)
                        stackConsolePane
                            .frame(height: 170)
                    }
                }
                .frame(minWidth: 400, idealWidth: 470)

                // Right Pane: Service Topology, Live Controls & Unified Logs
                stackInspectorPane
                    .frame(minWidth: 420, idealWidth: 500)
            }
        }
        .background(NordicTheme.windowBackground)
        .onAppear {
            if let draftYAML = appState.editorDraftComposeYAML, !draftYAML.isEmpty {
                yamlText = draftYAML
                currentFileURL = appState.editorDraftComposeURL
            }
        }
        .onChange(of: appState.editorDraftComposeYAML) { _, newValue in
            if let newValue, !newValue.isEmpty {
                yamlText = newValue
                currentFileURL = appState.editorDraftComposeURL
            }
        }
    }

    // MARK: - Top Toolbar

    private var stacksToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Multi-Container Compose Stacks")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)

                    NordicStatusBadge(
                        label: "\(runningCountInStack)/\(parsedStack.services.count) Running",
                        tone: runningCountInStack == parsedStack.services.count && !parsedStack.services.isEmpty
                            ? .positive
                            : (runningCountInStack > 0 ? .warning : .neutral)
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
                Text("Import or author a docker-compose.yml stack and orchestrate multi-service workloads in dependency order.")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }

            Spacer()

            Menu {
                ForEach(ComposeStackTemplate.allTemplates) { template in
                    Button {
                        currentFileURL = nil
                        yamlText = template.yamlContent
                    } label: {
                        VStack(alignment: .leading) {
                            Text(template.title)
                            Text(template.subtitle)
                                .font(.caption)
                        }
                    }
                }
            } label: {
                Label("Stack Templates", systemImage: "square.stack.3d.up")
            }
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                openComposeFileFromDisk()
            } label: {
                Label("Load Compose…", systemImage: "folder")
            }
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                saveComposeFileToDisk()
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)

            if existingCountInStack > 0 {
                Button {
                    Task { await stopStackServices() }
                } label: {
                    Label("Stop Stack", systemImage: "stop.fill")
                }
                .controlSize(.small)
                .disabled(isDeployingStack || runningCountInStack == 0)
                .fixedSize(horizontal: true, vertical: false)

                Button(role: .destructive) {
                    Task { await deleteStackServices() }
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .disabled(isDeployingStack)
                .help("Delete all containers in stack '\(parsedStack.projectName)'")
            }

            Button {
                Task { await deployEntireStack() }
            } label: {
                if isDeployingStack {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Deploying…")
                    }
                } else {
                    Label("Deploy Stack", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            .controlSize(.small)
            .disabled(isDeployingStack || parsedStack.services.isEmpty)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(NordicTheme.elevatedSurface)
    }

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

            TextEditor(text: $yamlText)
                .font(NordicTheme.monoFontRegular)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NordicTheme.codeSurface)
        }
    }

    // MARK: - Right Stack Inspector & Unified Logs

    private var stackInspectorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedInspectorTab) {
                    ForEach(StackInspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if selectedInspectorTab == .logs {
                    Button {
                        Task { await refreshUnifiedLogs() }
                    } label: {
                        Label("Refresh Logs", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(NordicTheme.elevatedSurface)
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            switch selectedInspectorTab {
            case .topology:
                topologyScrollView
            case .logs:
                unifiedLogsPane
            }
        }
        .background(NordicTheme.surfaceBackground)
        .onChange(of: selectedInspectorTab) { _, tab in
            if tab == .logs {
                Task { await refreshUnifiedLogs() }
            }
        }
    }

    private var topologyScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Infrastructure Summary Card
                NordicCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            NordicSectionHeader(
                                "Stack Execution Plan (\(parsedStack.projectName))",
                                subtitle: "Services are started in topological dependency order"
                            )
                            Spacer()
                        }

                        let orderText = parsedStack.topologicalServices.map(\.serviceName).joined(separator: " → ")
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                            Text("Start Order: \(orderText.isEmpty ? "None" : orderText)")
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.primaryText)
                        }

                        if !parsedStack.declaredVolumes.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 11))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                Text("Named Volumes: \(parsedStack.declaredVolumes.joined(separator: ", "))")
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                        }
                    }
                }

                // Service Cards in Topological Order
                ForEach(Array(parsedStack.topologicalServices.enumerated()), id: \.element.id) { index, svc in
                    serviceCard(for: svc, stepNumber: index + 1)
                }
            }
            .padding(14)
        }
    }

    private func serviceCard(for svc: ComposeServiceSpec, stepNumber: Int) -> some View {
        let liveContainer = appState.containers.first(where: { $0.id == svc.containerName })
        return NordicCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(verbatim: "#\(stepNumber)")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))

                    Text(svc.serviceName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NordicTheme.primaryText)

                    Text(verbatim: "(\(svc.containerName))")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)

                    Spacer()

                    if let liveContainer {
                        NordicStatusBadge(containerState: liveContainer.state)
                    } else {
                        NordicStatusBadge(label: "Not Created", tone: .neutral)
                    }
                }

                Text(svc.imageReference)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
                    .textSelection(.enabled)

                if !svc.dependsOn.isEmpty {
                    HStack(spacing: 4) {
                        Text("Depends on:")
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
                                Text(verbatim: "127.0.0.1:\(pm.hostPort) → \(pm.containerPort)/\(pm.proto)")
                                    .font(NordicTheme.monoFontSmall)
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

    @State private var unifiedLogSearch: String = ""
    @State private var unifiedLogPaused: Bool = false
    @State private var unifiedLogAutoScroll: Bool = true

    private var unifiedLogsPane: some View {
        VStack(spacing: 0) {
            if unifiedLogsText.isEmpty && !isLoadingUnifiedLogs {
                NordicEmptyState(
                    icon: .activity,
                    title: "No Stack Logs Available",
                    description: "Deploy the stack first to view interleaved logs across all stack services."
                )
            } else {
                NordicLogViewer(
                    rawLogText: unifiedLogsText,
                    searchText: $unifiedLogSearch,
                    isPaused: $unifiedLogPaused,
                    autoScroll: $unifiedLogAutoScroll,
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
                    stackConsoleLines.removeAll()
                }
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(NordicTheme.elevatedSurface)

            ScrollView {
                Text(verbatim: stackConsoleLines.joined(separator: "\n"))
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
        isDeployingStack = true
        stackConsoleLines = ["==> Deploying stack '\(parsedStack.projectName)' (\(parsedStack.services.count) services)…"]
        defer { isDeployingStack = false }

        // 1. Ensure declared named volumes exist
        let existingVolNames = Set(appState.volumes.map(\.name))
        for vol in parsedStack.declaredVolumes where !existingVolNames.contains(vol) {
            stackConsoleLines.append("==> Creating named volume '\(vol)'…")
            try? await appState.runtimeService.createVolume(
                request: VolumeCreateRequest(name: vol, sizeSpec: "2G")
            )
        }

        // 2. Deploy each service in topological order
        for svc in parsedStack.topologicalServices {
            if let existing = appState.containers.first(where: { $0.id == svc.containerName }) {
                if existing.state == .running {
                    stackConsoleLines.append("==> Service '\(svc.serviceName)' (\(svc.containerName)) is already running.")
                    continue
                } else {
                    stackConsoleLines.append("==> Removing stopped container '\(svc.containerName)' before re-creating…")
                    try? await appState.runtimeService.deleteContainer(id: svc.containerName, force: true)
                }
            }

            let req = ComposeParser.buildContainerRequest(
                for: svc,
                projectName: parsedStack.projectName,
                networkName: "default",
                defaultCPUs: appState.preferences.defaultContainerCPUs,
                defaultMemoryMB: appState.preferences.defaultContainerMemoryMB
            )

            stackConsoleLines.append("==> Starting service '\(svc.serviceName)' (\(svc.imageReference))…")
            do {
                let id = try await appState.runtimeService.createOrRunContainer(request: req)
                stackConsoleLines.append("    ✓ Started '\(id)'")
            } catch {
                stackConsoleLines.append("    ✗ Failed to start '\(svc.serviceName)': \(error.localizedDescription)")
            }
        }

        await appState.refreshAll(isUserInitiated: false)
        stackConsoleLines.append("==> Stack '\(parsedStack.projectName)' orchestration finished.")
        await refreshUnifiedLogs()
    }

    private func stopStackServices() async {
        isDeployingStack = true
        stackConsoleLines.append("==> Stopping stack '\(parsedStack.projectName)'…")
        defer { isDeployingStack = false }

        // Stop in reverse dependency order
        for svc in parsedStack.topologicalServices.reversed() {
            if appState.containers.first(where: { $0.id == svc.containerName })?.state == .running {
                stackConsoleLines.append("==> Stopping '\(svc.containerName)'…")
                try? await appState.runtimeService.stopContainer(id: svc.containerName, timeoutSeconds: 5)
            }
        }
        await appState.refreshAll(isUserInitiated: false)
        stackConsoleLines.append("==> Stack stopped.")
    }

    private func deleteStackServices() async {
        isDeployingStack = true
        stackConsoleLines.append("==> Deleting all containers in stack '\(parsedStack.projectName)'…")
        defer { isDeployingStack = false }

        for svc in parsedStack.topologicalServices.reversed() {
            if appState.containers.contains(where: { $0.id == svc.containerName }) {
                stackConsoleLines.append("==> Deleting '\(svc.containerName)'…")
                try? await appState.runtimeService.deleteContainer(id: svc.containerName, force: true)
            }
        }
        await appState.refreshAll(isUserInitiated: false)
        stackConsoleLines.append("==> Stack containers deleted.")
    }

    private func refreshUnifiedLogs() async {
        isLoadingUnifiedLogs = true
        defer { isLoadingUnifiedLogs = false }
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
        unifiedLogsText = combined.joined(separator: "\n")
    }

    private func openComposeFileFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Open docker-compose.yml"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            currentFileURL = url
            yamlText = content
        }
    }

    private func saveComposeFileToDisk() {
        let panel = NSSavePanel()
        panel.title = "Save docker-compose.yml"
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "docker-compose.yml"
        if panel.runModal() == .OK, let url = panel.url {
            try? yamlText.write(to: url, atomically: true, encoding: .utf8)
            currentFileURL = url
        }
    }
}
