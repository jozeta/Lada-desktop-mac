import SwiftUI

public struct DashboardView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var runningContainers: [ContainerModel] {
        appState.containers.filter { $0.state == .running }
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
                    trailingText: appState.installation.cliVersion.map { "container v\($0.description)" } ?? "CLI Not Installed"
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
                        secondaryValue: ByteCountFormatter.string(fromByteCount: Int64(appState.diskUsage.images.sizeInBytes), countStyle: .file) + " on disk",
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

                // Quick Actions & Disk Usage Row
                HStack(alignment: .top, spacing: 14) {
                    quickActionsPanel
                    diskUsagePanel
                }

                // Active Containers & Recent Operations
                HStack(alignment: .top, spacing: 14) {
                    runningContainersPanel
                    recentActivityPanel
                }
            }
            .padding(20)
        }
        .background(NordicTheme.contentSurface)
        .task {
            await appState.sampleAllRunningContainersTelemetry()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await appState.sampleAllRunningContainersTelemetry()
            }
        }
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
                trailingText: "\(runningContainers.count) running • \(totalProcs) PIDs"
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
                    title: "Cluster CPU Load",
                    iconName: "cpu",
                    primaryMetricText: String(format: "%.1f%%", latest?.cpuPercent ?? 0),
                    secondaryMetricText: "\(totalAllocatedCPUs) vCPUs across \(runningContainers.count) VM(s)",
                    primarySeries: samples.map(\.cpuPercent),
                    fixedMaxY: 100.0,
                    primaryColor: NordicTheme.accent(for: appState.preferences.accentThemeChoice)
                )

                NordicPerformanceChartCard(
                    title: "Memory Usage (RAM)",
                    iconName: "memorychip",
                    primaryMetricText: ByteCountFormatter.string(fromByteCount: Int64(totalMemUsedBytes), countStyle: .memory),
                    secondaryMetricText: String(
                        format: "%.1f%% of %@",
                        latest?.memoryPercent ?? 0,
                        ByteCountFormatter.string(fromByteCount: Int64(totalMemLimitBytes), countStyle: .memory)
                    ),
                    primarySeries: samples.map(\.memoryPercent),
                    fixedMaxY: 100.0,
                    primaryColor: NordicTheme.statusGreen
                )

                NordicPerformanceChartCard(
                    title: "Network I/O",
                    iconName: "network",
                    primaryMetricText: "↓ \(formatTransferRate(latest?.networkRxRateBps ?? 0))  ↑ \(formatTransferRate(latest?.networkTxRateBps ?? 0))",
                    secondaryMetricText: "Total RX: \(ByteCountFormatter.string(fromByteCount: Int64(latest?.totalNetworkRxBytes ?? 0), countStyle: .file)) • TX: \(ByteCountFormatter.string(fromByteCount: Int64(latest?.totalNetworkTxBytes ?? 0), countStyle: .file))",
                    primarySeries: samples.map { $0.networkRxRateBps / 1024.0 },
                    secondarySeries: samples.map { $0.networkTxRateBps / 1024.0 },
                    primaryLegend: "RX (KB/s)",
                    secondaryLegend: "TX (KB/s)",
                    primaryColor: Color.cyan,
                    secondaryColor: NordicTheme.statusAmber
                )

                NordicPerformanceChartCard(
                    title: "Storage / HD I/O",
                    iconName: "internaldrive",
                    primaryMetricText: "R: \(formatTransferRate(latest?.diskReadRateBps ?? 0))  W: \(formatTransferRate(latest?.diskWriteRateBps ?? 0))",
                    secondaryMetricText: "Total Read: \(ByteCountFormatter.string(fromByteCount: Int64(latest?.totalDiskReadBytes ?? 0), countStyle: .file)) • Write: \(ByteCountFormatter.string(fromByteCount: Int64(latest?.totalDiskWriteBytes ?? 0), countStyle: .file))",
                    primarySeries: samples.map { $0.diskReadRateBps / 1024.0 },
                    secondarySeries: samples.map { $0.diskWriteRateBps / 1024.0 },
                    primaryLegend: "Read (KB/s)",
                    secondaryLegend: "Write (KB/s)",
                    primaryColor: Color.purple,
                    secondaryColor: NordicTheme.statusAmber
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
        .background(NordicTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var quickActionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            NordicSectionHeader("Quick Actions", subtitle: "Common container & image workflows")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button {
                    appState.createContainerInitialRequest = nil
                    appState.showCreateContainerSheet = true
                } label: {
                    Label("Run / Create Container…", systemImage: "plus.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.regular)

                Button {
                    appState.showPullImageSheet = true
                } label: {
                    Label("Pull OCI Image…", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.regular)

                Button {
                    appState.selectedSection = .builds
                } label: {
                    Label("Build Image from Context…", systemImage: "hammer")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.regular)

                Button {
                    appState.selectedSection = .machines
                } label: {
                    Label("Manage Linux Machines…", systemImage: "terminal")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.regular)
            }

            Divider().overlay(NordicTheme.borderSubtle)

            HStack {
                Text("Default DNS Domain:")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                Text(appState.systemProperties.dns.domain.map { ".\($0)" } ?? "Unset")
                    .font(NordicTheme.monoFontRegular)
                    .foregroundStyle(NordicTheme.primaryText)
                Spacer()
                Text("Default Registry:")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                Text(appState.systemProperties.registry.domain)
                    .font(NordicTheme.monoFontRegular)
                    .foregroundStyle(NordicTheme.primaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NordicTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
        )
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
                trailingText: ByteCountFormatter.string(fromByteCount: Int64(appState.diskUsage.totalBytes), countStyle: .file)
            )

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
        .background(NordicTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
        )
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
            Text(ByteCountFormatter.string(fromByteCount: Int64(usage.sizeInBytes), countStyle: .file))
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.primaryText)
            Text("(\(ByteCountFormatter.string(fromByteCount: Int64(usage.reclaimable), countStyle: .file)) reclaimable)")
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var runningContainersPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Active Containers",
                trailingText: "\(runningContainers.count) running"
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
                ForEach(appState.containers.prefix(6)) { container in
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
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(stats.memoryUsageBytes), countStyle: .memory)) • \(stats.numProcesses) pids")
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
        .background(NordicTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var recentActivityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Recent Operations & Alerts",
                trailingText: failedEvents.isEmpty ? "0 failures" : "\(failedEvents.count) failed"
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
        .background(NordicTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
        )
    }
}
