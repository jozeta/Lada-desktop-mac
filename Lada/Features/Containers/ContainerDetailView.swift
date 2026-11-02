import SwiftUI
import AppKit

public struct ContainerDetailView: View {
    @ObservedObject var appState: AppState
    public let container: ContainerModel

    /// This container's persistent inspector state (tab, shell, files, logs).
    @ObservedObject private var workspace: ContainerWorkspace
    @ObservedObject private var logs: ContainerLogsState
    @State private var revealedEnvKeys: Set<String> = []
    @State private var confirmDelete: Bool = false

    public enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case logs = "Logs"
        case terminal = "Terminal"
        case files = "Files"
        case configuration = "Config"
        case networking = "Network"
        case storage = "Storage"
        case environment = "Env"

        public var id: String { rawValue }
    }

    public init(appState: AppState, container: ContainerModel) {
        self.appState = appState
        self.container = container
        let ws = appState.workspaces.workspace(for: container.id)
        self.workspace = ws
        self.logs = ws.logs
    }

    private var tabBinding: Binding<DetailTab> {
        Binding(
            get: { workspace.tab },
            set: { appState.workspaces.select($0, for: container.id) }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with Lifecycle Controls
            NordicDetailHeader(
                title: container.id,
                subtitle: "\(container.shortImageReference) · \(container.configuration.os)/\(container.configuration.arch) · \(container.configuration.cpus) vCPU · \(container.memoryFormatted)",
                badge: NordicStatusBadge(containerState: container.state)
            ) {
                if container.state == .running {
                    Button {
                        Task {
                            await appState.performOperation(
                                category: "Containers",
                                title: "Stop Container \(container.id)",
                                redactedCommand: "container stop \(container.id)"
                            ) {
                                try await appState.runtimeService.stopContainer(id: container.id, timeoutSeconds: 5)
                                return "Stopped container '\(container.id)'."
                            }
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.performOperation(
                                category: "Containers",
                                title: "Restart Container \(container.id)",
                                redactedCommand: "container stop \(container.id) && container start \(container.id)"
                            ) {
                                try await appState.runtimeService.restartContainer(id: container.id)
                                return "Restarted container '\(container.id)'."
                            }
                        }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        Task {
                            await appState.startContainerWithVerification(id: container.id)
                        }
                    } label: {
                        if appState.startingContainerIDs.contains(container.id) {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.small)
                                Text("Starting…")
                            }
                        } else {
                            Label("Start", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicTheme.statusGreen)
                    .controlSize(.small)
                    .disabled(appState.startingContainerIDs.contains(container.id))
                }

                Button {
                    if container.state == .running {
                        appState.openExternalTerminalForContainer(id: container.id)
                    } else {
                        Task {
                            await appState.startContainerWithVerification(id: container.id)
                            if appState.containers.first(where: { $0.id == container.id })?.state == .running {
                                appState.openExternalTerminalForContainer(id: container.id)
                            }
                        }
                    }
                } label: {
                    Label("Terminal", systemImage: "apple.terminal")
                }
                .controlSize(.small)
                .help("Open a real macOS Terminal.app window connected to this container (`container exec -it \(container.id)`)")

                Button {
                    appState.createContainerInitialRequest = ContainerCreateRequest.duplicating(container)
                    appState.showCreateContainerSheet = true
                } label: {
                    Label("Duplicate…", systemImage: "plus.square.on.square")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Delete Container '\(container.id)'")
            }

            // Segmented Tab Bar
            Picker("", selection: tabBinding) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .nordicPageBackground()
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            // Tab Content
            Group {
                switch workspace.tab {
                case .overview:
                    overviewTab
                case .logs:
                    logsTab
                case .terminal:
                    InteractiveTerminalView(
                        container: container,
                        executablePath: appState.installation.executablePath,
                        session: workspace.terminal,
                        onOpenExternalTerminal: { shell in
                            appState.openExternalTerminalForContainer(id: container.id, preferredShell: shell)
                        }
                    )
                case .files:
                    ContainerFileBrowserView(appState: appState, container: container, state: workspace.files)
                case .configuration:
                    configurationTab
                case .networking:
                    networkingTab
                case .storage:
                    storageTab
                case .environment:
                    environmentTab
                }
            }
            // A new identity per container: the Terminal, Files and other tabs rebuild (and the
            // terminal reconnects) when another container is selected, while the tab stays.
            .id(container.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Delete Container '\(container.id)'?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(container.state == .running ? "Force Delete Running Container" : "Delete Container", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Containers",
                        title: "Delete Container \(container.id)",
                        redactedCommand: "container delete \(container.state == .running ? "--force " : "")\(container.id)"
                    ) {
                        try await appState.runtimeService.deleteContainer(id: container.id, force: container.state == .running)
                        await MainActor.run {
                            if appState.selectedContainerID == container.id {
                                appState.selectedContainerID = nil
                            }
                        }
                        return "Deleted container '\(container.id)'."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting '\(container.id)' permanently removes its writable root filesystem image. Named volumes and host bind-mounted directories are preserved.")
        }
        .task(id: container.id) {
            // Cached logs of this container show at once; then refresh.
            await loadLogs()
            await appState.sampleContainerTelemetry(for: container.id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                if container.state == .running {
                    await appState.sampleContainerTelemetry(for: container.id)
                    // Live tail while the Logs tab is open, unless paused.
                    if workspace.tab == .logs && !logs.isPaused {
                        await loadLogs()
                    }
                }
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        let samples = appState.containerTelemetryHistory[container.id] ?? []
        let latestSample = samples.last
        let stats = appState.containerStats[container.id]
        let isRunning = container.state == .running

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NordicSectionHeader("Details")

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Name").foregroundStyle(NordicTheme.secondaryText)
                        Text(container.id).font(NordicTheme.monoFontRegular).textSelection(.enabled)
                    }
                    GridRow {
                        Text("Image").foregroundStyle(NordicTheme.secondaryText)
                        Text(container.imageReference).font(NordicTheme.monoFontRegular).textSelection(.enabled)
                    }
                    GridRow {
                        Text("State").foregroundStyle(NordicTheme.secondaryText)
                        Text(container.rawState).font(NordicTheme.monoFontRegular)
                    }
                    GridRow {
                        Text("Created").foregroundStyle(NordicTheme.secondaryText)
                        Text(container.creationDate.formatted(date: .abbreviated, time: .standard)).font(NordicTheme.monoFontRegular)
                    }
                    if let started = container.startedDate {
                        GridRow {
                            Text("Started").foregroundStyle(NordicTheme.secondaryText)
                            Text(started.formatted(date: .abbreviated, time: .standard)).font(NordicTheme.monoFontRegular)
                        }
                    }
                    GridRow {
                        Text("Command").foregroundStyle(NordicTheme.secondaryText)
                        Text(([container.configuration.executable] + container.configuration.arguments).joined(separator: " "))
                            .font(NordicTheme.monoFontRegular)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Resources").foregroundStyle(NordicTheme.secondaryText)
                        Text("\(container.configuration.cpus) vCPUs • \(container.memoryFormatted) RAM • Rootfs \(container.configuration.readOnlyRootfs ? "Read-Only" : "Read-Write")")
                            .font(NordicTheme.monoFontRegular)
                    }
                    if !container.configuration.publishedPorts.isEmpty {
                        GridRow {
                            Text("Ports").foregroundStyle(NordicTheme.secondaryText)
                            HStack(spacing: 8) {
                                ForEach(container.configuration.publishedPorts) { p in
                                    let probe = appState.portHealthMap[p.hostPort]
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(portHealthColor(probe: probe, isRunning: isRunning))
                                            .frame(width: 7, height: 7)
                                        Text(verbatim: "\(p.hostAddress):\(p.hostPort) → \(p.containerPort)/\(p.proto)")
                                            .font(NordicTheme.monoFontSmall)
                                        if isRunning, let probe {
                                            Text(verbatim: probe.state.displayBadge)
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(portHealthColor(probe: probe, isRunning: isRunning))
                                        }
                                        if isRunning && p.proto == "tcp" {
                                            Button("Open") {
                                                if let url = URL(string: "http://127.0.0.1:\(p.hostPort)") {
                                                    NSWorkspace.shared.open(url)
                                                }
                                            }
                                            .controlSize(.mini)
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(NordicTheme.surfaceBackground))
                                    .help(probe?.tooltipDescription ?? "Published port \(p.hostPort)")
                                }
                            }
                        }
                    }
                }
                .font(.system(size: 12))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nordicSurface()

                // Performance Graphs (CPU, RAM, Network, HD / Disk I/O)
                NordicSectionHeader(
                    "Performance",
                    subtitle: isRunning ? nil : "Start the container to see live CPU, memory, network and disk activity.",
                    trailingText: isRunning ? (stats?.numProcesses ?? latestSample?.numProcesses).map { "\($0) processes" } : nil
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 220), spacing: 12),
                        GridItem(.flexible(minimum: 220), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    // 1. CPU Usage Graph
                    NordicPerformanceChartCard(
                        title: "CPU",
                        iconName: "cpu",
                        primaryMetricText: isRunning
                            ? String(format: "%.1f%%", latestSample?.cpuPercent ?? 0.0)
                            : "0.0%",
                        secondaryMetricText: String(format: "%.2f", isRunning ? (latestSample?.cpuCoresUsed ?? 0) : 0) + " of \(container.configuration.cpus) vCPU busy",
                        primarySeries: isRunning ? samples.map(\.cpuPercent) : [],
                        primaryLegend: "Utilization",
                        fixedMaxY: 100.0,
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: NordicTheme.accent(for: appState.preferences.accentThemeChoice),
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatPercent
                    )

                    // 2. RAM / Memory Usage Graph
                    let memUsed = stats?.memoryUsageBytes ?? latestSample?.memoryUsageBytes ?? 0
                    let memLimit = stats?.memoryLimitBytes ?? latestSample?.memoryLimitBytes ?? container.configuration.memoryInBytes
                    let memPct = stats?.memoryPercentage ?? latestSample?.memoryPercent ?? 0
                    NordicPerformanceChartCard(
                        title: "Memory",
                        iconName: "memorychip",
                        primaryMetricText: isRunning
                            ? "\(NordicFormat.bytes(fromByteCount: Int64(memUsed), countStyle: .memory)) (\(String(format: "%.1f%%", memPct)))"
                            : "0 MB (0.0%)",
                        secondaryMetricText: "Limit: \(NordicFormat.bytes(fromByteCount: Int64(memLimit), countStyle: .memory))",
                        primarySeries: isRunning ? samples.map(\.memoryPercent) : [],
                        primaryLegend: "Used %",
                        fixedMaxY: 100.0,
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: NordicTheme.statusGreen,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatPercent
                    )

                    // 3. Network I/O Graph (RX & TX)
                    let rxRate = latestSample?.networkRxRateBps ?? 0
                    let txRate = latestSample?.networkTxRateBps ?? 0
                    let totalRx = stats?.networkRxBytes ?? latestSample?.totalNetworkRxBytes ?? 0
                    let totalTx = stats?.networkTxBytes ?? latestSample?.totalNetworkTxBytes ?? 0
                    NordicPerformanceChartCard(
                        title: "Network",
                        iconName: "network",
                        primaryMetricText: isRunning
                            ? "↓ \(formatRate(rxRate))  ↑ \(formatRate(txRate))"
                            : "↓ 0 B/s  ↑ 0 B/s",
                        secondaryMetricText: "Total RX \(NordicFormat.bytes(fromByteCount: Int64(totalRx), countStyle: .file)) • TX \(NordicFormat.bytes(fromByteCount: Int64(totalTx), countStyle: .file))",
                        primarySeries: isRunning ? samples.map(\.networkRxRateBps) : [],
                        secondarySeries: isRunning ? samples.map(\.networkTxRateBps) : [],
                        primaryLegend: "RX",
                        secondaryLegend: "TX",
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: NordicTheme.accent(for: appState.preferences.accentThemeChoice),
                        secondaryColor: NordicTheme.statusAmber,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatRate
                    )

                    // 4. HD / Block Disk I/O Graph (Read & Write)
                    let readRate = latestSample?.diskReadRateBps ?? 0
                    let writeRate = latestSample?.diskWriteRateBps ?? 0
                    let totalRead = stats?.blockReadBytes ?? latestSample?.totalDiskReadBytes ?? 0
                    let totalWrite = stats?.blockWriteBytes ?? latestSample?.totalDiskWriteBytes ?? 0
                    NordicPerformanceChartCard(
                        title: "Disk",
                        iconName: "internaldrive",
                        primaryMetricText: isRunning
                            ? "R \(formatRate(readRate))  W \(formatRate(writeRate))"
                            : "R 0 B/s  W 0 B/s",
                        secondaryMetricText: "Total Read \(NordicFormat.bytes(fromByteCount: Int64(totalRead), countStyle: .file)) • Write \(NordicFormat.bytes(fromByteCount: Int64(totalWrite), countStyle: .file))",
                        primarySeries: isRunning ? samples.map(\.diskReadRateBps) : [],
                        secondarySeries: isRunning ? samples.map(\.diskWriteRateBps) : [],
                        primaryLegend: "Read",
                        secondaryLegend: "Write",
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: NordicTheme.statusGreen,
                        secondaryColor: NordicTheme.statusAmber,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatRate
                    )
                }

                // Maintenance Actions
                NordicSectionHeader("Maintenance")
                HStack(spacing: 10) {
                    if container.state == .running {
                        Button("Reclaim Space") {
                            Task {
                                await appState.performOperation(
                                    category: "Containers",
                                    title: "Clean Container \(container.id)",
                                    redactedCommand: "container clean \(container.id)"
                                ) {
                                    try await appState.runtimeService.cleanContainer(id: container.id)
                                    return "Cleaned unused blocks on '\(container.id)'."
                                }
                            }
                        }
                        .controlSize(.small)
                    }

                    Button("Export Filesystem…") {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "\(container.id)-rootfs.tar"
                        if panel.runModal() == .OK, let url = panel.url {
                            Task {
                                await appState.performOperation(
                                    category: "Containers",
                                    title: "Export Container \(container.id)",
                                    redactedCommand: "container export -o \(url.path) \(container.id)"
                                ) {
                                    try await appState.runtimeService.exportContainer(id: container.id, outputPath: url.path)
                                    return "Exported container filesystem to \(url.lastPathComponent)."
                                }
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(16)
        }
        .background(Color.clear)
    }

    private func formatRate(_ bytesPerSec: Double) -> String {
        let clamped = max(0, Int64(bytesPerSec.rounded()))
        if clamped < 1024 {
            return "\(clamped) B/s"
        }
        return "\(NordicFormat.bytes(fromByteCount: clamped, countStyle: .file))/s"
    }

    // MARK: - Logs Tab

    @ViewBuilder
    private var logsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Log Source", selection: $logs.showBootLogs) {
                    Text("App Logs (`container logs`)").tag(false)
                    Text("VM Boot Log (`--boot`)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 340)
                .onChange(of: logs.showBootLogs) { _, _ in
                    Task { await loadLogs() }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .nordicPageBackground()

            NordicLogViewer(
                rawLogText: logs.text,
                searchText: $logs.searchText,
                isPaused: $logs.isPaused,
                autoScroll: $logs.autoScroll,
                onRefresh: {
                    Task { await loadLogs() }
                }
            )
        }
    }

    // MARK: - Configuration Tab

    @ViewBuilder
    private var configurationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(NordicTheme.accent())
                    Text("Container creation parameters in Apple's `container` runtime are immutable after creation. To modify CPUs, memory, mounts, or ports, click 'Duplicate…' in the header to pre-populate a new container with this configuration.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nordicSurface()

                NordicSectionHeader("Effective Configuration (`container inspect \(container.id)`)")

                Text(SecretRedactor.redact(container.rawInspectJSON ?? encodeConfigurationPreview()))
                    .font(NordicTheme.monoFontRegular)
                    .foregroundStyle(NordicTheme.primaryText)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NordicTheme.codeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
            }
            .padding(16)
        }
        .background(Color.clear)
    }

    // MARK: - Networking Tab

    @ViewBuilder
    private var networkingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NordicSectionHeader("Active Network Attachments")
                if container.networks.isEmpty {
                    Text("No active network attachments (container is stopped). Configured networks: \(container.configuration.configuredNetworks.map { net in container.configuration.networkAliases[net].map { "\(net) (aliases: \($0.joined(separator: ", ")))" } ?? net }.joined(separator: ", "))")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                } else {
                    ForEach(container.networks) { net in
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Network: \(net.network)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Hostname: \(net.hostname)")
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                                if let aliases = container.configuration.networkAliases[net.network], !aliases.isEmpty {
                                    Text("DNS aliases: \(aliases.joined(separator: ", "))")
                                        .font(NordicTheme.monoFontSmall)
                                        .foregroundStyle(NordicTheme.secondaryText)
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("IPv4: \(net.ipv4Address)")
                                    .font(NordicTheme.monoFontRegular)
                                    .textSelection(.enabled)
                                Text("Gateway: \(net.ipv4Gateway) \(net.macAddress.map { "• MAC \($0)" } ?? "")")
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                        }
                        .padding(12)
                        .nordicSurface()
                    }
                }

                NordicSectionHeader("Published Host Ports (`-p`)")
                if container.configuration.publishedPorts.isEmpty {
                    Text("No host ports published.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                } else {
                    ForEach(container.configuration.publishedPorts) { p in
                        let probe = appState.portHealthMap[p.hostPort]
                        let isRunning = container.state == .running
                        HStack(spacing: 8) {
                            Circle()
                                .fill(portHealthColor(probe: probe, isRunning: isRunning))
                                .frame(width: 8, height: 8)
                            Text(verbatim: "\(p.hostAddress):\(p.hostPort)")
                                .font(NordicTheme.monoFontMedium)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(NordicTheme.secondaryText)
                            Text(verbatim: "Container Port \(p.containerPort)/\(p.proto)")
                                .font(NordicTheme.monoFontRegular)
                            if isRunning, let probe {
                                NordicStatusBadge(
                                    label: probe.statusCode.map { "HTTP \($0)" } ?? probe.state.displayBadge,
                                    tone: (probe.state == .healthyHTTP || probe.state == .listeningTCP) ? .positive : .warning
                                )
                            }
                            Spacer()
                            if p.proto == "tcp" {
                                Button("Open in Browser") {
                                    if let url = URL(string: "http://127.0.0.1:\(p.hostPort)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .nordicSurface()
                        .help(probe?.tooltipDescription ?? "Published port \(p.hostPort)")
                    }
                }
            }
            .padding(16)
        }
        .background(Color.clear)
    }

    private func portHealthColor(probe: PortProbeResult?, isRunning: Bool) -> Color {
        guard isRunning else { return NordicTheme.secondaryText.opacity(0.45) }
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

    // MARK: - Storage Tab

    @ViewBuilder
    private var storageTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NordicSectionHeader("Configured Mounts & Volumes")
                if container.configuration.mounts.isEmpty {
                    Text("No external bind mounts, volumes, or tmpfs mounts attached.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                } else {
                    ForEach(container.configuration.mounts) { m in
                        HStack {
                            NordicStatusBadge(label: m.kind.displayName, tone: .accent, showDot: false)
                            Text(m.source.isEmpty ? "(in-memory)" : m.source)
                                .font(NordicTheme.monoFontSmall)
                                .textSelection(.enabled)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(NordicTheme.secondaryText)
                            Text(m.destination)
                                .font(NordicTheme.monoFontRegular)
                                .textSelection(.enabled)
                            Spacer()
                            NordicStatusBadge(
                                label: m.readOnly ? "Read-Only" : "Read-Write",
                                tone: m.readOnly ? .warning : .positive,
                                showDot: false
                            )
                        }
                        .padding(10)
                        .nordicSurface()
                    }
                }
            }
            .padding(16)
        }
        .background(Color.clear)
    }

    // MARK: - Environment Tab

    @ViewBuilder
    private var environmentTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NordicSectionHeader(
                    "Process Environment Variables",
                    subtitle: "Sensitive values are masked by default."
                )

                if container.configuration.environment.isEmpty {
                    Text("No environment variables configured.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                } else {
                    ForEach(container.configuration.environment, id: \.self) { raw in
                        let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
                        let key = parts.first ?? raw
                        let value = parts.count > 1 ? parts[1] : ""
                        let isSensitive = SecretRedactor.isSensitiveKey(key)
                        let isRevealed = revealedEnvKeys.contains(key)

                        HStack {
                            Text(key)
                                .font(NordicTheme.monoFontMedium)
                                .foregroundStyle(NordicTheme.primaryText)
                                .frame(width: 220, alignment: .leading)

                            Text(isSensitive && !isRevealed ? "••••••••••••" : value)
                                .font(NordicTheme.monoFontRegular)
                                .foregroundStyle(isSensitive && !isRevealed ? NordicTheme.secondaryText : NordicTheme.primaryText)
                                .textSelection(.enabled)

                            Spacer()

                            if isSensitive {
                                Button(isRevealed ? "Hide" : "Reveal") {
                                    if isRevealed {
                                        revealedEnvKeys.remove(key)
                                    } else {
                                        revealedEnvKeys.insert(key)
                                    }
                                }
                                .controlSize(.mini)
                            }
                        }
                        .padding(8)
                        .nordicBar()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.clear)
    }

    private func loadLogs() async {
        let id = container.id
        do {
            let fetched = try await appState.runtimeService.fetchContainerLogs(id: id, bootLogs: logs.showBootLogs, tailLines: 500)
            guard id == container.id else { return }
            logs.text = fetched
        } catch {
            guard id == container.id else { return }
            let message = (error as? LadaError)?.explanation ?? error.localizedDescription
            logs.text = "Could not load logs for \(id): \(message)"
        }
    }

    private func encodeConfigurationPreview() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(container.configuration),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
