import SwiftUI
import Charts

public struct DashboardView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var runningContainers: [ContainerModel] {
        appState.containers.filter { $0.state == .running }
    }

    /// Running containers sorted by their latest measured CPU share, then the stopped ones.
    private var containersByLoad: [ContainerModel] {
        let cpu: (ContainerModel) -> Double = { appState.containerTelemetryHistory[$0.id]?.last?.cpuPercent ?? -1 }
        let running = appState.containers.filter { $0.state == .running }.sorted { cpu($0) > cpu($1) }
        return running + appState.containers.filter { $0.state != .running }
    }

    private var setupWarnings: [PrerequisiteItem] {
        appState.prerequisites.filter { $0.status != .ready }
    }

    private var failedEvents: [ActivityEvent] {
        appState.activityEvents.filter { $0.outcome == .failure }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Setup / Prerequisite Alert Strip if any prerequisite is not ready
                if !setupWarnings.isEmpty {
                    setupWarningStrip
                }

                // Primary Operational Metrics Grid
                NordicSectionHeader(
                    "System & Runtime Telemetry",
                    subtitle: "Live state reported by Apple's `container` runtime and `container-apiserver`.",
                    trailingText: appState.installation.cliVersion.map { "container v\($0.description)" } ?? "CLI Not Installed",
                    info: "Live state reported by the runtime: whether it's running, how many containers and images exist, and the image builder."
                )

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    metricTile(
                        title: "Runtime Health",
                        primaryValue: appState.systemStatus.state.displayTitle,
                        secondaryValue: appState.installation.executablePath ?? "Not installed",
                        icon: .runtimeHealth,
                        tone: appState.systemStatus.state == .running ? .positive : (appState.installation.isInstalled ? .warning : .critical)
                    )

                    metricTile(
                        title: "Containers",
                        primaryValue: "\(runningContainers.count) / \(appState.containers.count)",
                        secondaryValue: "\(runningContainers.count) running, \(max(0, appState.containers.count - runningContainers.count)) stopped",
                        icon: .containers,
                        tone: runningContainers.isEmpty ? .neutral : .positive
                    )

                    metricTile(
                        title: "OCI Images",
                        primaryValue: "\(appState.images.count)",
                        secondaryValue: NordicFormat.bytes(fromByteCount: Int64(appState.diskUsage.images.sizeInBytes), countStyle: .file) + " on disk",
                        icon: .images,
                        tone: .accent
                    )

                    metricTile(
                        title: "BuildKit Builder",
                        primaryValue: appState.builderStatus.isRunning ? "Active" : "Idle",
                        secondaryValue: appState.builderStatus.isRunning
                            ? "\(appState.builderStatus.cpus) CPUs • \(appState.builderStatus.memoryBytes / (1024 * 1024)) MiB"
                            : "Starts on demand",
                        icon: .builds,
                        tone: appState.builderStatus.isRunning ? .positive : .neutral
                    )
                }

                // Live Cluster Performance Graphs (CPU, RAM, Network, Block I/O)
                livePerformanceGraphsSection

                // Panels pack into the shortest column (masonry), so differing heights leave no gaps.
                MasonryLayout(minColumnWidth: 380, maxColumns: 2, spacing: 14) {
                    runningContainersPanel
                    diskUsagePanel
                    recentActivityPanel
                }
            }
            .padding(20)
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var livePerformanceGraphsSection: some View {
        let samples = appState.systemTelemetryHistory
        let latest = samples.last
        let totalAllocatedCPUs = runningContainers.reduce(0) { $0 + $1.configuration.cpus }
        let totalMemUsedBytes = latest?.memoryUsageBytes ?? runningContainers.reduce(UInt64(0)) { sum, c in
            sum + (appState.containerStats[c.id]?.memoryUsageBytes ?? 0)
        }
        let totalMemLimitBytes = max(1, latest?.memoryLimitBytes ?? runningContainers.reduce(UInt64(0)) { sum, c in
            sum + c.configuration.memoryInBytes
        })
        let totalProcs = latest?.numProcesses ?? runningContainers.reduce(0) { sum, c in
            sum + (appState.containerStats[c.id]?.numProcesses ?? 1)
        }

        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Live Workload Performance Graphs",
                subtitle: runningContainers.isEmpty
                    ? "Start a container to stream real-time CPU, Memory, Network, and Disk I/O telemetry."
                    : "Real-time aggregate telemetry across \(runningContainers.count) running container VM(s) (`container stats`).",
                trailingText: "\(runningContainers.count) running • \(totalProcs) PIDs",
                info: "CPU, memory, network and disk activity of all running containers together, sampled every 2 seconds for the last 5 minutes."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                NordicPerformanceChartCard(
                    title: "CPU",
                    iconName: "cpu",
                    primaryMetricText: String(format: "%.1f%%", latest?.cpuPercent ?? 0),
                    secondaryMetricText: String(format: "%.2f", latest?.cpuCoresUsed ?? 0) + " of \(totalAllocatedCPUs) vCPUs busy across \(runningContainers.count) VM(s)",
                    primarySeries: samples.map(\.cpuPercent),
                    fixedMaxY: 100.0,
                    primaryColor: NordicTheme.accent(for: appState.preferences.accentThemeChoice),
                    timestamps: samples.map(\.timestamp),
                    valueFormatter: NordicPerformanceChartCard.formatPercent
                )

                NordicPerformanceChartCard(
                    title: "Memory",
                    iconName: "memorychip",
                    primaryMetricText: NordicFormat.bytes(fromByteCount: Int64(totalMemUsedBytes), countStyle: .memory),
                    secondaryMetricText: String(
                        format: "%.1f%% of %@",
                        latest?.memoryPercent ?? 0,
                        NordicFormat.bytes(fromByteCount: Int64(totalMemLimitBytes), countStyle: .memory)
                    ),
                    primarySeries: samples.map(\.memoryPercent),
                    fixedMaxY: 100.0,
                    primaryColor: NordicTheme.statusGreen,
                    timestamps: samples.map(\.timestamp),
                    valueFormatter: NordicPerformanceChartCard.formatPercent
                )

                NordicPerformanceChartCard(
                    title: "Network",
                    iconName: "network",
                    primaryMetricText: "↓ \(formatTransferRate(latest?.networkRxRateBps ?? 0))  ↑ \(formatTransferRate(latest?.networkTxRateBps ?? 0))",
                    secondaryMetricText: "Total RX: \(NordicFormat.bytes(fromByteCount: Int64(latest?.totalNetworkRxBytes ?? 0), countStyle: .file)) • TX: \(NordicFormat.bytes(fromByteCount: Int64(latest?.totalNetworkTxBytes ?? 0), countStyle: .file))",
                    primarySeries: samples.map(\.networkRxRateBps),
                    secondarySeries: samples.map(\.networkTxRateBps),
                    primaryLegend: "RX",
                    secondaryLegend: "TX",
                    primaryColor: Color.cyan,
                    secondaryColor: NordicTheme.statusAmber,
                    timestamps: samples.map(\.timestamp),
                    valueFormatter: NordicPerformanceChartCard.formatRate
                )

                NordicPerformanceChartCard(
                    title: "Disk",
                    iconName: "internaldrive",
                    primaryMetricText: "R: \(formatTransferRate(latest?.diskReadRateBps ?? 0))  W: \(formatTransferRate(latest?.diskWriteRateBps ?? 0))",
                    secondaryMetricText: "Total Read: \(NordicFormat.bytes(fromByteCount: Int64(latest?.totalDiskReadBytes ?? 0), countStyle: .file)) • Write: \(NordicFormat.bytes(fromByteCount: Int64(latest?.totalDiskWriteBytes ?? 0), countStyle: .file))",
                    primarySeries: samples.map(\.diskReadRateBps),
                    secondarySeries: samples.map(\.diskWriteRateBps),
                    primaryLegend: "Read",
                    secondaryLegend: "Write",
                    primaryColor: Color.purple,
                    secondaryColor: NordicTheme.statusAmber,
                    timestamps: samples.map(\.timestamp),
                    valueFormatter: NordicPerformanceChartCard.formatRate
                )
            }
        }
    }

    private func formatTransferRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", max(0, bytesPerSecond))
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024.0)
        } else {
            return String(format: "%.2f MB/s", bytesPerSecond / (1024.0 * 1024.0))
        }
    }

    @ViewBuilder
    private var setupWarningStrip: some View {
        HStack(spacing: 12) {
            LadaIcon(.setupDiagnostics, size: 20)
                .foregroundStyle(NordicTheme.statusAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(setupWarnings.count) Prerequisite Item(s) Need Attention")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                Text(setupWarnings.map(\.name).joined(separator: " • "))
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }

            Spacer()

            if appState.installation.isInstalled && appState.systemStatus.state != .running {
                Button("Start Container System") {
                    Task {
                        await appState.performOperation(
                            category: "Runtime",
                            title: "Start Container System",
                            redactedCommand: "container system start"
                        ) {
                            try await appState.runtimeService.startSystemService(enableKernelInstall: true)
                            return "Container API server started."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if setupWarnings.contains(where: { $0.actionType == .restartSystemService }) {
                Button("Restart Services") {
                    Task { await appState.restartContainerServices() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Stops and starts the container services so the API server matches the installed CLI. Running containers are stopped.")
                .accessibilityIdentifier(AccessibilityID.restartServicesButton)
            }

            Button("Open Setup Wizard…") {
                appState.showSetupWizard = true
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(NordicTheme.statusAmber.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.statusAmber.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metricTile(
        title: String,
        primaryValue: String,
        secondaryValue: String,
        icon: LadaIconKind,
        tone: OperationalBadgeTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(NordicTheme.sectionHeaderFont)
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                LadaIcon(icon, size: 16)
                    .foregroundStyle(tone.color)
            }

            Text(primaryValue)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(NordicTheme.primaryText)
                .lineLimit(1)

            Text(secondaryValue)
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nordicSurface()
    }

    @ViewBuilder
    private var diskUsagePanel: some View {
        let total = max(1, Double(appState.diskUsage.totalBytes))
        let imgFraction = Double(appState.diskUsage.images.sizeInBytes) / total
        let ctrFraction = Double(appState.diskUsage.containers.sizeInBytes) / total
        let volFraction = Double(appState.diskUsage.volumes.sizeInBytes) / total

        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Runtime Disk Usage (`container system df`)",
                trailingText: NordicFormat.bytes(fromByteCount: Int64(appState.diskUsage.totalBytes), countStyle: .file),
                info: "Space used by images, containers and volumes (`container system df`), and how full this Mac's disk is."
            )

            if let disk = appState.hostDiskSpace {
                diskDonut(disk)
                Divider().overlay(NordicTheme.borderSubtle)
            }

            // Stacked Visual Storage Bar
            GeometryReader { geo in
                let w = max(10, geo.size.width)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        .frame(width: max(4, w * imgFraction))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NordicTheme.statusGreen)
                        .frame(width: max(4, w * ctrFraction))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NordicTheme.statusAmber)
                        .frame(width: max(4, w * volFraction))
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            VStack(spacing: 6) {
                diskRow(label: "Images", color: NordicTheme.accent(for: appState.preferences.accentThemeChoice), usage: appState.diskUsage.images)
                Divider().overlay(NordicTheme.borderSubtle)
                diskRow(label: "Containers", color: NordicTheme.statusGreen, usage: appState.diskUsage.containers)
                Divider().overlay(NordicTheme.borderSubtle)
                diskRow(label: "Local Volumes", color: NordicTheme.statusAmber, usage: appState.diskUsage.volumes)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nordicSurface()
    }

    private func segmentColor(_ kind: DiskBreakdown.Segment.Kind) -> Color {
        switch kind {
        case .images: return NordicTheme.accent(for: appState.preferences.accentThemeChoice)
        case .containers: return NordicTheme.statusGreen
        case .volumes: return NordicTheme.statusAmber
        case .other: return NordicTheme.secondaryText.opacity(0.45)
        case .free: return NordicTheme.secondaryText.opacity(0.14)
        }
    }

    /// Hollow pie of the drive holding the runtime's data: what the runtime uses, everything else,
    /// and free space, with the free amount in the middle.
    private func diskDonut(_ disk: DiskSpaceSnapshot) -> some View {
        let segments = DiskBreakdown.segments(runtime: appState.diskUsage, disk: disk)
        let freeFraction = Double(disk.availableBytes) / Double(max(1, disk.totalBytes))
        return HStack(alignment: .center, spacing: NordicTheme.Spacing.l) {
            Chart(segments) { segment in
                SectorMark(
                    angle: .value("Bytes", max(segment.bytes, 0)),
                    innerRadius: .ratio(0.68),
                    angularInset: 1.2
                )
                .cornerRadius(3)
                .foregroundStyle(segmentColor(segment.kind))
            }
            .chartLegend(.hidden)
            .frame(width: 128, height: 128)
            .overlay {
                VStack(spacing: 1) {
                    Text(NordicFormat.bytes(fromByteCount: disk.availableBytes, countStyle: .file))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NordicTheme.primaryText)
                    Text("free")
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Disk: \(NordicFormat.bytes(fromByteCount: disk.availableBytes, countStyle: .file)) free of \(NordicFormat.bytes(fromByteCount: disk.totalBytes, countStyle: .file))")

            VStack(alignment: .leading, spacing: 5) {
                Text("This Mac's disk · \(NordicFormat.bytes(fromByteCount: disk.totalBytes, countStyle: .file)) · \(Int((freeFraction * 100).rounded()))% free")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Circle().fill(segmentColor(segment.kind)).frame(width: 8, height: 8)
                        Text(segment.label)
                            .font(.system(size: 12))
                            .foregroundStyle(NordicTheme.primaryText)
                        Spacer()
                        Text(NordicFormat.bytes(fromByteCount: segment.bytes, countStyle: .file))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
            }
        }
    }

    private func diskRow(label: String, color: Color, usage: ResourceDiskUsage) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NordicTheme.primaryText)
                .frame(width: 95, alignment: .leading)
            Text("\(usage.active)/\(usage.total) active")
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.secondaryText)
            Spacer()
            Text(NordicFormat.bytes(fromByteCount: Int64(usage.sizeInBytes), countStyle: .file))
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.primaryText)
            Text("(\(NordicFormat.bytes(fromByteCount: Int64(usage.reclaimable), countStyle: .file)) reclaimable)")
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var runningContainersPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Active Containers",
                subtitle: "Running containers first, busiest CPU first.",
                trailingText: "\(runningContainers.count) running",
                info: "Containers sorted with running ones first and the busiest at the top. Inspect opens one in Containers."
            )

            if appState.containers.isEmpty {
                NordicEmptyState(
                    icon: .containers,
                    title: "No Containers Created Yet",
                    description: "Pull an OCI image or run your first lightweight Linux VM container.",
                    primaryActionTitle: "Run First Container…",
                    onPrimaryAction: {
                        appState.createContainerInitialRequest = nil
                        appState.showCreateContainerSheet = true
                    },
                    secondaryActionTitle: "Pull Image…",
                    onSecondaryAction: {
                        appState.showPullImageSheet = true
                    }
                )
                .frame(height: 190)
            } else {
                ForEach(containersByLoad.prefix(6)) { container in
                    HStack(spacing: 10) {
                        NordicStatusBadge(containerState: container.state)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(container.id)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NordicTheme.primaryText)
                            Text(container.imageReference)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let stats = appState.containerStats[container.id] {
                            VStack(alignment: .trailing, spacing: 3) {
                                if container.state == .running, let sample = appState.containerTelemetryHistory[container.id]?.last {
                                    Text(String(format: "CPU %.1f%%", sample.cpuPercent) + " • ↓ \(formatTransferRate(sample.networkRxRateBps)) ↑ \(formatTransferRate(sample.networkTxRateBps))")
                                        .font(NordicTheme.monoFontSmall)
                                        .foregroundStyle(NordicTheme.primaryText)
                                }
                                Text("\(NordicFormat.bytes(fromByteCount: Int64(stats.memoryUsageBytes), countStyle: .memory)) • \(stats.numProcesses) pids")
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                                ProgressView(value: min(100, max(0, stats.memoryPercentage)), total: 100)
                                    .progressViewStyle(.linear)
                                    .tint(NordicTheme.statusGreen)
                                    .frame(width: 72)
                            }
                        } else if let ip = container.primaryIPv4 {
                            Text(ip)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        if container.state == .running {
                            Button {
                                appState.openExternalTerminalForContainer(id: container.id)
                            } label: {
                                Image(systemName: "apple.terminal")
                            }
                            .controlSize(.small)
                            .help("Open Real Terminal Connected to \(container.id)")
                        }
                        Button("Inspect") {
                            appState.selectedContainerID = container.id
                            appState.selectedSection = .containers
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(NordicTheme.borderSubtle)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nordicSurface()
    }

    @ViewBuilder
    private var recentActivityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Recent Operations & Alerts",
                trailingText: failedEvents.isEmpty ? "0 failures" : "\(failedEvents.count) failed",
                info: "The latest operations Låda ran, and anything that failed."
            )

            if appState.activityEvents.isEmpty {
                Text("No operations recorded in this session yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(appState.activityEvents.prefix(6)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(event.outcome == .failure ? NordicTheme.statusRed : (event.outcome == .warning ? NordicTheme.statusAmber : NordicTheme.statusGreen))
                            .frame(width: 7, height: 7)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NordicTheme.primaryText)
                                Spacer()
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                            Text(event.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider().overlay(NordicTheme.borderSubtle)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nordicSurface()
    }
}
