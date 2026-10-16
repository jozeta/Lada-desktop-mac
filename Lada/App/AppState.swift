import Foundation
import SwiftUI
import AppKit
@preconcurrency import UserNotifications

@MainActor
public final class AppState: ObservableObject {
    // MARK: - Dependencies

    @Published public var preferences: AppPreferences
    public let healthService: RuntimeHealthService
    private let liveService: ContainerCLIClient
    private let mockService: MockContainerRuntimeService

    public var runtimeService: ContainerRuntimeService {
        if preferences.useSimulationWhenCLIMissing && !installation.isInstalled {
            return mockService
        }
        return currentInjectedService ?? liveService
    }

    private var currentInjectedService: ContainerRuntimeService?

    // MARK: - Navigation & Global UI State

    @Published public var selectedSection: NavigationSection = .overview
    @Published public var globalSearchQuery: String = ""
    @Published public var showSetupWizard: Bool = false
    @Published public var showCreateContainerSheet: Bool = false
    @Published public var createContainerInitialRequest: ContainerCreateRequest? = nil
    @Published public var editorDraftDockerfileText: String? = nil
    @Published public var editorDraftSourceURL: URL? = nil
    @Published public var editorDraftComposeYAML: String? = nil
    @Published public var editorDraftComposeURL: URL? = nil
    @Published public var showPullImageSheet: Bool = false
    @Published public var showBuildImageSheet: Bool = false
    @Published public var activeError: LadaError? = nil
    @Published public var statusFeedbackMessage: String? = nil
    @Published public var startingContainerIDs: Set<String> = []
    @Published public var isRefreshing: Bool = false

    // MARK: - Runtime & Prerequisite State

    @Published public var hostEnvironment: HostEnvironmentInfo
    @Published public var installation: RuntimeInstallation
    @Published public var capabilities: RuntimeCapabilities
    @Published public var systemStatus: RuntimeSystemStatus
    @Published public var prerequisites: [PrerequisiteItem] = []
    @Published public var diskUsage: DiskUsageSummary = .init()
    @Published public var systemProperties: SystemProperties = .init()
    @Published public var dnsDomains: [String] = []
    @Published public var latestReleaseInfo: ReleaseAssetInfo? = nil

    // MARK: - Resource Inventories

    @Published public var containers: [ContainerModel] = []
    @Published public var selectedContainerID: String? = nil
    @Published public var containerStats: [String: ContainerStatsModel] = [:]
    @Published public var containerTelemetryHistory: [String: [ContainerPerformanceSample]] = [:]
    @Published public var systemTelemetryHistory: [ContainerPerformanceSample] = []
    @Published public var portHealthMap: [UInt16: PortProbeResult] = [:]
    private var previousStatsTimestamp: [String: Date] = [:]

    @Published public var images: [ImageModel] = []
    @Published public var selectedImageID: String? = nil

    @Published public var builderStatus: BuilderStatusModel = BuilderStatusModel(isRunning: false)
    @Published public var buildHistory: [BuildRecord] = []

    @Published public var networks: [NetworkModel] = []
    @Published public var selectedNetworkID: String? = nil

    @Published public var volumes: [VolumeModel] = []
    @Published public var selectedVolumeID: String? = nil

    @Published public var machines: [MachineModel] = []
    @Published public var selectedMachineID: String? = nil

    @Published public var registries: [RegistryModel] = []
    @Published public var activityEvents: [ActivityEvent] = []

    private var pollingTask: Task<Void, Never>?
    private var appActivityObserversInstalled: Bool = false
    private var adaptivePollTickCount: Int = 0

    // MARK: - Initialization

    public init(
        preferences: AppPreferences? = nil,
        injectedService: ContainerRuntimeService? = nil,
        healthService: RuntimeHealthService = RuntimeHealthService()
    ) {
        let resolvedPreferences = preferences ?? AppPreferences()
        self.preferences = resolvedPreferences
        self.currentInjectedService = injectedService
        self.healthService = healthService
        self.liveService = ContainerCLIClient()
        self.mockService = MockContainerRuntimeService()

        let initialService = injectedService ?? liveService
        let detectedHost = initialService.detectHostEnvironment()
        let initialInstall = RuntimeInstallation(isInstalled: false, executablePath: nil)
        self.hostEnvironment = detectedHost
        self.installation = initialInstall
        self.capabilities = initialService.getCapabilities(installation: initialInstall, host: detectedHost)
        self.systemStatus = RuntimeSystemStatus(state: .missingCLI)
        self.selectedSection = resolvedPreferences.defaultLandingSection

        loadPersistedBuildHistory()
        self.prerequisites = healthService.evaluatePrerequisites(
            host: detectedHost,
            installation: initialInstall,
            systemStatus: self.systemStatus
        )
    }

    // MARK: - Lifecycle & Discovery

    public func performInitialBootstrap() async {
        await refreshAll(isUserInitiated: false)
        if !preferences.hasCompletedFirstLaunchSetup || !installation.isInstalled || !hostEnvironment.isAppleSilicon || !hostEnvironment.isSupportedMacOS {
            if !preferences.hasCompletedFirstLaunchSetup {
                showSetupWizard = true
            }
        }
        installAppActivityObserversIfNeeded()
        startBackgroundRefreshLoop()
    }

    private func installAppActivityObserversIfNeeded() {
        guard !appActivityObserversInstalled else { return }
        appActivityObserversInstalled = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshFastWorkloadState()
            }
        }
    }

    public func startBackgroundRefreshLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let fastInterval = 3
                try? await Task.sleep(for: .seconds(fastInterval))
                guard !Task.isCancelled, let self else { break }
                guard NSApplication.shared.isActive, !self.isRefreshing else { continue }
                self.adaptivePollTickCount += 1
                let fullRefreshCadenceTicks = max(2, (self.preferences.autoRefreshIntervalSeconds * 2) / fastInterval)
                if self.adaptivePollTickCount % fullRefreshCadenceTicks == 0 {
                    await self.refreshAll(isUserInitiated: false)
                } else {
                    await self.refreshFastWorkloadState()
                }
            }
        }
    }

    /// Lightweight adaptive poll that refreshes only containers, single-call batched stats, and live port health probes.
    public func refreshFastWorkloadState() async {
        guard !isRefreshing, installation.isInstalled, systemStatus.state == .running else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let active = runtimeService
        async let containersTask = try? active.listContainers(includeStopped: true)
        async let statsTask = try? active.getContainerStats(ids: [])

        if let c = await containersTask {
            self.containers = c
        }
        if let stats = await statsTask, !stats.isEmpty {
            ingestStatsSnapshot(stats)
        }
        await probeAllPublishedPorts()
    }

    public func probeAllPublishedPorts() async {
        let runningPorts: [(host: String, port: UInt16)] = containers
            .filter { $0.state == .running }
            .flatMap { $0.configuration.publishedPorts }
            .map { ($0.hostAddress, $0.hostPort) }

        guard !runningPorts.isEmpty else {
            if !portHealthMap.isEmpty {
                portHealthMap.removeAll()
            }
            return
        }

        var updated: [UInt16: PortProbeResult] = [:]
        await withTaskGroup(of: PortProbeResult.self) { group in
            for item in runningPorts {
                group.addTask {
                    await PortHealthProber.probe(host: item.host, port: item.port)
                }
            }
            for await result in group {
                updated[result.hostPort] = result
            }
        }
        self.portHealthMap = updated
    }

    public func refreshAll(isUserInitiated: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let customPath = preferences.customCLIExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        liveService.setCustomExecutablePath(customPath.isEmpty ? nil : customPath)

        // Always check real installation first unless an explicit mock was injected for tests
        let discoveryTarget: ContainerRuntimeService = currentInjectedService ?? liveService
        let detectedHost = discoveryTarget.detectHostEnvironment()
        self.hostEnvironment = detectedHost

        let discoveredInstall = (try? await discoveryTarget.discoverRuntime(
            customExecutablePath: customPath.isEmpty ? nil : customPath
        )) ?? RuntimeInstallation(isInstalled: false, executablePath: nil)

        if preferences.useSimulationWhenCLIMissing && !discoveredInstall.isInstalled && currentInjectedService == nil {
            self.installation = (try? await mockService.discoverRuntime()) ?? discoveredInstall
        } else {
            self.installation = discoveredInstall
        }

        let active = runtimeService
        self.capabilities = active.getCapabilities(installation: self.installation, host: detectedHost)

        let status = (try? await active.getSystemStatus()) ?? RuntimeSystemStatus(
            state: self.installation.isInstalled ? .stopped : .missingCLI
        )
        self.systemStatus = status
        self.prerequisites = healthService.evaluatePrerequisites(
            host: detectedHost,
            installation: self.installation,
            systemStatus: status
        )

        guard self.installation.isInstalled else {
            if isUserInitiated {
                recordActivity(
                    category: "Runtime",
                    title: "Runtime Discovery",
                    detail: "Apple `container` CLI is not installed on this system.",
                    outcome: .warning
                )
            }
            return
        }

        // Load inventories concurrently when CLI is installed
        if status.state == .running {
            async let containersTask = try? active.listContainers(includeStopped: true)
            async let imagesTask = try? active.listImages()
            async let networksTask = try? active.listNetworks()
            async let volumesTask = try? active.listVolumes()
            async let machinesTask = try? active.listMachines()
            async let registriesTask = try? active.listRegistries()
            async let dfTask = try? active.getSystemDiskUsage()
            async let propsTask = try? active.getSystemProperties()
            async let builderTask = try? active.getBuilderStatus()
            async let statsTask = try? active.getContainerStats(ids: [])
            async let dnsTask = try? active.listDNSDomains()

            if let c = await containersTask { self.containers = c }
            if let i = await imagesTask { self.images = i }
            if let n = await networksTask { self.networks = n }
            if let v = await volumesTask { self.volumes = v }
            if let m = await machinesTask { self.machines = m }
            if let r = await registriesTask { self.registries = r }
            if let df = await dfTask { self.diskUsage = df }
            if let p = await propsTask { self.systemProperties = p }
            if let b = await builderTask { self.builderStatus = b }
            if let dns = await dnsTask { self.dnsDomains = dns }
            if let stats = await statsTask {
                ingestStatsSnapshot(stats)
            }
            await probeAllPublishedPorts()
        } else {
            // Even when API server is stopped, registry list and system properties work offline
            if let r = try? await active.listRegistries() { self.registries = r }
            if let p = try? await active.getSystemProperties() { self.systemProperties = p }
        }
    }

    public func sampleContainerTelemetry(for containerID: String) async {
        guard systemStatus.state == .running else { return }
        if let stats = try? await runtimeService.getContainerStats(ids: [containerID]), !stats.isEmpty {
            ingestStatsSnapshot(stats, onlyUpdateIDs: Set([containerID]))
        }
        await probeAllPublishedPorts()
    }

    public func sampleAllRunningContainersTelemetry() async {
        guard systemStatus.state == .running else { return }
        let hasRunning = containers.contains { $0.state == .running }
        guard hasRunning else { return }
        // Single batched CLI call (`container stats --format json --no-stream`) for all running containers
        if let stats = try? await runtimeService.getContainerStats(ids: []), !stats.isEmpty {
            ingestStatsSnapshot(stats)
        }
        await probeAllPublishedPorts()
    }

    private func ingestStatsSnapshot(_ statsList: [ContainerStatsModel], onlyUpdateIDs: Set<String>? = nil) {
        let now = Date()
        var updatedStatsMap = onlyUpdateIDs == nil ? [String: ContainerStatsModel]() : self.containerStats

        for s in statsList {
            let prevStat = self.containerStats[s.id]
            let prevTime = self.previousStatsTimestamp[s.id]
            let dt = max(0.25, prevTime.map { now.timeIntervalSince($0) } ?? 2.0)

            let containerCPUs = max(1, containers.first(where: { $0.id == s.id })?.configuration.cpus ?? 4)
            let cpuPercent: Double
            if let prev = prevStat, s.cpuUsageUsec >= prev.cpuUsageUsec {
                let deltaUsec = Double(s.cpuUsageUsec - prev.cpuUsageUsec)
                let totalAvailableUsec = dt * 1_000_000.0 * Double(containerCPUs)
                cpuPercent = min(100.0, max(0.2, (deltaUsec / max(1.0, totalAvailableUsec)) * 100.0))
            } else {
                // Initial sample estimate from cumulative CPU time
                cpuPercent = min(100.0, max(0.5, Double(s.cpuUsageUsec % 1_000_000) / 10_000.0))
            }

            let rxRate: Double
            let txRate: Double
            if let prev = prevStat {
                rxRate = s.networkRxBytes >= prev.networkRxBytes ? Double(s.networkRxBytes - prev.networkRxBytes) / dt : 0
                txRate = s.networkTxBytes >= prev.networkTxBytes ? Double(s.networkTxBytes - prev.networkTxBytes) / dt : 0
            } else {
                rxRate = Double(s.networkRxBytes) / 30.0
                txRate = Double(s.networkTxBytes) / 30.0
            }

            let diskReadRate: Double
            let diskWriteRate: Double
            if let prev = prevStat {
                diskReadRate = s.blockReadBytes >= prev.blockReadBytes ? Double(s.blockReadBytes - prev.blockReadBytes) / dt : 0
                diskWriteRate = s.blockWriteBytes >= prev.blockWriteBytes ? Double(s.blockWriteBytes - prev.blockWriteBytes) / dt : 0
            } else {
                diskReadRate = Double(s.blockReadBytes) / 30.0
                diskWriteRate = Double(s.blockWriteBytes) / 30.0
            }

            let sample = ContainerPerformanceSample(
                timestamp: now,
                cpuPercent: cpuPercent,
                memoryUsageBytes: s.memoryUsageBytes,
                memoryLimitBytes: s.memoryLimitBytes,
                memoryPercent: s.memoryPercentage,
                networkRxRateBps: rxRate,
                networkTxRateBps: txRate,
                totalNetworkRxBytes: s.networkRxBytes,
                totalNetworkTxBytes: s.networkTxBytes,
                diskReadRateBps: diskReadRate,
                diskWriteRateBps: diskWriteRate,
                totalDiskReadBytes: s.blockReadBytes,
                totalDiskWriteBytes: s.blockWriteBytes,
                numProcesses: s.numProcesses
            )

            var history = self.containerTelemetryHistory[s.id] ?? []
            if history.isEmpty {
                // Seed initial baseline points so the area chart renders a full timeline immediately
                for offset in stride(from: 10, through: 1, by: -1) {
                    let seedFactor = 0.85 + (Double(offset % 3) * 0.05)
                    history.append(
                        ContainerPerformanceSample(
                            timestamp: now.addingTimeInterval(-Double(offset * 2)),
                            cpuPercent: cpuPercent * seedFactor,
                            memoryUsageBytes: s.memoryUsageBytes,
                            memoryLimitBytes: s.memoryLimitBytes,
                            memoryPercent: s.memoryPercentage,
                            networkRxRateBps: rxRate * seedFactor,
                            networkTxRateBps: txRate * seedFactor,
                            totalNetworkRxBytes: s.networkRxBytes,
                            totalNetworkTxBytes: s.networkTxBytes,
                            diskReadRateBps: diskReadRate * seedFactor,
                            diskWriteRateBps: diskWriteRate * seedFactor,
                            totalDiskReadBytes: s.blockReadBytes,
                            totalDiskWriteBytes: s.blockWriteBytes,
                            numProcesses: s.numProcesses
                        )
                    )
                }
            }
            history.append(sample)
            if history.count > 40 {
                history.removeFirst(history.count - 40)
            }
            self.containerTelemetryHistory[s.id] = history
            self.previousStatsTimestamp[s.id] = now
            updatedStatsMap[s.id] = s
        }

        self.containerStats = updatedStatsMap
        recordAggregateSystemTelemetrySample(at: now)
    }

    private func recordAggregateSystemTelemetrySample(at now: Date) {
        let runningIDs = containers.filter { $0.state == .running }.map(\.id)
        let activeSamples: [ContainerPerformanceSample] = runningIDs.compactMap { id in
            containerTelemetryHistory[id]?.last
        }

        let avgCPU: Double = activeSamples.isEmpty
            ? 0
            : min(100.0, activeSamples.reduce(0.0) { $0 + $1.cpuPercent } / Double(max(1, activeSamples.count)))
        let totalMemUsed = activeSamples.reduce(UInt64(0)) { $0 + $1.memoryUsageBytes }
        let totalMemLimit = max(1, activeSamples.reduce(UInt64(0)) { $0 + $1.memoryLimitBytes })
        let memPct = min(100.0, (Double(totalMemUsed) / Double(totalMemLimit)) * 100.0)
        let totalRxRate = activeSamples.reduce(0.0) { $0 + $1.networkRxRateBps }
        let totalTxRate = activeSamples.reduce(0.0) { $0 + $1.networkTxRateBps }
        let totalRxBytes = activeSamples.reduce(UInt64(0)) { $0 + $1.totalNetworkRxBytes }
        let totalTxBytes = activeSamples.reduce(UInt64(0)) { $0 + $1.totalNetworkTxBytes }
        let totalDiskRRate = activeSamples.reduce(0.0) { $0 + $1.diskReadRateBps }
        let totalDiskWRate = activeSamples.reduce(0.0) { $0 + $1.diskWriteRateBps }
        let totalDiskRBytes = activeSamples.reduce(UInt64(0)) { $0 + $1.totalDiskReadBytes }
        let totalDiskWBytes = activeSamples.reduce(UInt64(0)) { $0 + $1.totalDiskWriteBytes }
        let totalProcs = activeSamples.reduce(0) { $0 + $1.numProcesses }

        let aggregate = ContainerPerformanceSample(
            timestamp: now,
            cpuPercent: avgCPU,
            memoryUsageBytes: totalMemUsed,
            memoryLimitBytes: totalMemLimit,
            memoryPercent: memPct,
            networkRxRateBps: totalRxRate,
            networkTxRateBps: totalTxRate,
            totalNetworkRxBytes: totalRxBytes,
            totalNetworkTxBytes: totalTxBytes,
            diskReadRateBps: totalDiskRRate,
            diskWriteRateBps: totalDiskWRate,
            totalDiskReadBytes: totalDiskRBytes,
            totalDiskWriteBytes: totalDiskWBytes,
            numProcesses: totalProcs
        )

        var sysHistory = self.systemTelemetryHistory
        if sysHistory.isEmpty {
            for offset in stride(from: 10, through: 1, by: -1) {
                let seedFactor = 0.85 + (Double(offset % 3) * 0.05)
                sysHistory.append(
                    ContainerPerformanceSample(
                        timestamp: now.addingTimeInterval(-Double(offset * 2)),
                        cpuPercent: avgCPU * seedFactor,
                        memoryUsageBytes: totalMemUsed,
                        memoryLimitBytes: totalMemLimit,
                        memoryPercent: memPct,
                        networkRxRateBps: totalRxRate * seedFactor,
                        networkTxRateBps: totalTxRate * seedFactor,
                        totalNetworkRxBytes: totalRxBytes,
                        totalNetworkTxBytes: totalTxBytes,
                        diskReadRateBps: totalDiskRRate * seedFactor,
                        diskWriteRateBps: totalDiskWRate * seedFactor,
                        totalDiskReadBytes: totalDiskRBytes,
                        totalDiskWriteBytes: totalDiskWBytes,
                        numProcesses: totalProcs
                    )
                )
            }
        }
        sysHistory.append(aggregate)
        if sysHistory.count > 40 {
            sysHistory.removeFirst(sysHistory.count - 40)
        }
        self.systemTelemetryHistory = sysHistory
    }

    // MARK: - Activity & Notifications

    public func recordActivity(
        category: String,
        title: String,
        detail: String,
        redactedCommand: String? = nil,
        outcome: ActivityOutcome = .success,
        durationMs: Int? = nil
    ) {
        let event = ActivityEvent(
            category: category,
            title: title,
            detail: SecretRedactor.redact(detail),
            redactedCommand: redactedCommand.map { SecretRedactor.redact($0) },
            outcome: outcome,
            durationMs: durationMs
        )
        activityEvents.insert(event, at: 0)
        if activityEvents.count > 250 {
            activityEvents.removeLast(activityEvents.count - 250)
        }
        StructuredLogger.shared.log(
            outcome == .failure ? .error : (outcome == .warning ? .warning : .info),
            subsystem: category,
            correlationID: event.correlationID,
            "\(title): \(detail)"
        )
    }

    public func performOperation(
        category: String,
        title: String,
        redactedCommand: String? = nil,
        refreshAfter: Bool = true,
        operation: () async throws -> String
    ) async {
        let start = Date()
        do {
            let detail = try await operation()
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            recordActivity(
                category: category,
                title: title,
                detail: detail,
                redactedCommand: redactedCommand,
                outcome: .success,
                durationMs: elapsed
            )
            if refreshAfter {
                if isRefreshing {
                    if let freshContainers = try? await runtimeService.listContainers(includeStopped: true) {
                        self.containers = freshContainers
                    }
                } else {
                    await refreshAll(isUserInitiated: false)
                }
            }
        } catch let ladaErr as LadaError {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            activeError = ladaErr
            recordActivity(
                category: category,
                title: title,
                detail: ladaErr.explanation,
                redactedCommand: redactedCommand,
                outcome: .failure,
                durationMs: elapsed
            )
            if preferences.notifyContainerFailures {
                sendUserNotification(title: "\(title) Failed", body: ladaErr.explanation)
            }
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let wrapped = LadaError(
                category: .internalError,
                explanation: error.localizedDescription,
                suggestedRemediation: "Inspect the Diagnostics log for details.",
                isRetryable: true
            )
            activeError = wrapped
            recordActivity(
                category: category,
                title: title,
                detail: wrapped.explanation,
                redactedCommand: redactedCommand,
                outcome: .failure,
                durationMs: elapsed
            )
        }
    }

    public func sendUserNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = SecretRedactor.redact(body)
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
        }
    }

    // MARK: - Build History Persistence

    public func appendBuildRecord(_ record: BuildRecord) {
        if let idx = buildHistory.firstIndex(where: { $0.id == record.id }) {
            buildHistory[idx] = record
        } else {
            buildHistory.insert(record, at: 0)
        }
        if buildHistory.count > 50 {
            buildHistory.removeLast(buildHistory.count - 50)
        }
        savePersistedBuildHistory()
    }

    private var buildHistoryFileURL: URL {
        preferences.ladaDataDirectoryURL.appendingPathComponent("build-history.json")
    }

    private func loadPersistedBuildHistory() {
        let url = buildHistoryFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BuildRecord].self, from: data) else {
            return
        }
        self.buildHistory = decoded
    }

    private func savePersistedBuildHistory() {
        let dir = preferences.ladaDataDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(buildHistory) {
            try? data.write(to: buildHistoryFileURL, options: .atomic)
        }
    }

    // MARK: - Diagnostics Export

    public func generateRedactedDiagnosticReport() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var lines: [String] = []
        lines.append("=== LÅDA DIAGNOSTIC REPORT ===")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Host Architecture: \(hostEnvironment.cpuArchitecture) (\(hostEnvironment.cpuBrandString))")
        lines.append("macOS Version: \(hostEnvironment.macOSVersionString) [Build \(hostEnvironment.macOSBuildString)]")
        lines.append("Physical Memory: \(ByteCountFormatter.string(fromByteCount: Int64(hostEnvironment.physicalMemoryBytes), countStyle: .memory))")
        lines.append("Hypervisor Available: \(hostEnvironment.hypervisorFrameworkAvailable)")
        lines.append("")
        lines.append("=== RUNTIME INSTALLATION ===")
        lines.append("CLI Installed: \(installation.isInstalled)")
        lines.append("Executable Path: \((installation.executablePath ?? "none").replacingOccurrences(of: home, with: "~"))")
        lines.append("CLI Version: \(installation.cliVersion?.description ?? "none")")
        lines.append("API Server State: \(systemStatus.state.rawValue)")
        lines.append("Server Version: \(systemStatus.serverVersion?.version ?? "none")")
        lines.append("")
        lines.append("=== PREREQUISITES ===")
        for item in prerequisites {
            lines.append("- [\(item.status.rawValue)] \(item.name): \(item.detectedStatusText)")
        }
        lines.append("")
        lines.append("=== RECENT STRUCTURED LOGS ===")
        lines.append(StructuredLogger.shared.exportRedactedLogText())
        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }

    // MARK: - Conflict Resolution & External Terminal

    public func hasContainerNameConflict(_ candidateName: String) -> Bool {
        let trimmed = candidateName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return containers.contains { $0.id.lowercased() == trimmed }
    }

    public func nextAvailableContainerName(basedOn baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "container-app" : trimmed
        if !hasContainerNameConflict(base) {
            return base
        }
        var suffix = 2
        while hasContainerNameConflict("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    public var allocatedHostPortsInUse: Set<UInt16> {
        var used = Set<UInt16>()
        for c in containers {
            for p in c.configuration.publishedPorts {
                used.insert(p.hostPort)
            }
        }
        return used
    }

    public func conflictingHostPorts(for ports: [PortMapping]) -> Set<UInt16> {
        let inUse = allocatedHostPortsInUse
        var conflicts = Set<UInt16>()
        for p in ports where inUse.contains(p.hostPort) {
            conflicts.insert(p.hostPort)
        }
        return conflicts
    }

    public func nextAvailableHostPort(startingAt preferredPort: UInt16, additionallyReserved: Set<UInt16> = []) -> UInt16 {
        let inUse = allocatedHostPortsInUse.union(additionallyReserved)
        var candidate = max(1, preferredPort)
        while inUse.contains(candidate) && candidate < 65535 {
            candidate += 1
        }
        return candidate
    }

    public func resolveCreateRequestConflicts(_ request: ContainerCreateRequest) -> ContainerCreateRequest {
        var resolved = request
        if !resolved.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved.name = nextAvailableContainerName(basedOn: resolved.name)
        }
        var reservedPorts = Set<UInt16>()
        resolved.publishedPorts = resolved.publishedPorts.map { mapping in
            let freeHostPort = nextAvailableHostPort(startingAt: mapping.hostPort, additionallyReserved: reservedPorts)
            reservedPorts.insert(freeHostPort)
            return PortMapping(
                id: mapping.id,
                hostAddress: mapping.hostAddress,
                hostPort: freeHostPort,
                containerPort: mapping.containerPort,
                proto: mapping.proto,
                count: mapping.count
            )
        }
        return resolved
    }

    /// Launches a real native macOS `Terminal.app` window connected to `container exec -it <id>` via an interactive shell script.
    public func openExternalTerminalForContainer(id: String, preferredShell: String? = nil) {
        let execPath = installation.executablePath ?? "/usr/local/bin/container"
        let sanitizedID = id.replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "-", options: .regularExpression)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lada-shell-\(sanitizedID).command")

        let shellLogic: String
        if let preferredShell, !preferredShell.isEmpty {
            shellLogic = "exec \"\(execPath)\" exec -it \"\(id)\" \(preferredShell)"
        } else {
            shellLogic = """
            "\(execPath)" exec -it "\(id)" /bin/sh -c 'if [ -x /bin/bash ]; then exec /bin/bash; elif [ -x /bin/ash ]; then exec /bin/ash; else exec /bin/sh; fi'
            """
        }

        let scriptContent = """
        #!/bin/sh
        clear
        printf "\\033[1;36m==> Låda: Connected to Apple Container '%s'\\033[0m\\n" "\(id)"
        printf "\\033[0;90m    Command: %s exec -it %s\\033[0m\\n\\n" "\(execPath)" "\(id)"
        \(shellLogic)
        status=$?
        if [ $status -ne 0 ]; then
            printf "\\n\\033[1;31m[Låda] Container shell exited with status %d.\\033[0m\\n" "$status"
            read -r -p "Press Enter to close this terminal window..." _
        fi
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
            recordActivity(
                category: "Terminal",
                title: "Opened Terminal (\(id))",
                detail: "Launched macOS Terminal session connected to container '\(id)'."
            )
        } catch {
            activeError = LadaError(
                category: .internalError,
                explanation: "Failed to launch external macOS Terminal for container '\(id)': \(error.localizedDescription)",
                suggestedRemediation: "Ensure Terminal.app is available or use the built-in Terminal tab.",
                isRetryable: true
            )
        }
    }

    // MARK: - Dockerfile Drag-and-Drop & One-Click Build + Deploy

    public func presentCreateContainer(with request: ContainerCreateRequest? = nil) {
        self.createContainerInitialRequest = request
        self.showCreateContainerSheet = true
    }

    @discardableResult
    public func handleDroppedDockerfile(url: URL) -> Bool {
        var resolvedFileURL = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let composeCandidates = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]
            if let foundCompose = composeCandidates
                .map({ url.appendingPathComponent($0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                resolvedFileURL = foundCompose
            } else {
                let candidates = ["Dockerfile", "Containerfile", "dockerfile", "containerfile"]
                if let found = candidates
                    .map({ url.appendingPathComponent($0) })
                    .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    resolvedFileURL = found
                } else {
                    return false
                }
            }
        }

        guard let content = try? String(contentsOf: resolvedFileURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if ComposeParser.isComposeFile(url: resolvedFileURL) || ComposeParser.isComposeContent(content) {
            editorDraftComposeYAML = content
            editorDraftComposeURL = resolvedFileURL
            selectedSection = .stacks
            recordActivity(
                category: "Stacks",
                title: "Compose Stack Loaded",
                detail: "Loaded multi-container stack from \(resolvedFileURL.lastPathComponent)."
            )
            return true
        }

        editorDraftDockerfileText = content
        editorDraftSourceURL = resolvedFileURL

        let req = DockerfileParser.buildContainerCreateRequest(
            content: content,
            sourceFileURL: resolvedFileURL,
            defaultCPUs: preferences.defaultContainerCPUs,
            defaultMemoryMB: preferences.defaultContainerMemoryMB
        )
        recordActivity(
            category: "Containers",
            title: "Dockerfile Loaded",
            detail: "Pre-populated container configuration from \(resolvedFileURL.lastPathComponent)."
        )
        presentCreateContainer(with: req)
        return true
    }

    public func handleDroppedDockerfileText(_ text: String, sourceURL: URL? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if ComposeParser.isComposeContent(trimmed) {
            editorDraftComposeYAML = trimmed
            editorDraftComposeURL = sourceURL
            selectedSection = .stacks
            return
        }

        editorDraftDockerfileText = trimmed
        editorDraftSourceURL = sourceURL

        let req = DockerfileParser.buildContainerCreateRequest(
            content: trimmed,
            sourceFileURL: sourceURL,
            defaultCPUs: preferences.defaultContainerCPUs,
            defaultMemoryMB: preferences.defaultContainerMemoryMB
        )
        presentCreateContainer(with: req)
    }

    public func buildAndDeployContainer(
        request: ContainerCreateRequest,
        onProgressLine: @escaping @Sendable (String) -> Void,
        onComplete: (@Sendable () -> Void)? = nil
    ) async {
        var effectiveRequest = request

        // Step 1: If a Dockerfile is attached and buildFromDockerfileBeforeRun is enabled, build the image first
        if request.hasAttachedDockerfile && request.buildFromDockerfileBeforeRun {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.lada.dockerfile-build-\(UUID().uuidString.prefix(8))", isDirectory: true)

            let contextDir: String
            let containerfilePath: String

            if let existingPath = request.dockerfileSourcePath,
               FileManager.default.fileExists(atPath: existingPath) {
                let parentDir = URL(fileURLWithPath: existingPath).deletingLastPathComponent().path
                let desktopPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
                let rawText = (request.dockerfileContent ?? (try? String(contentsOfFile: existingPath, encoding: .utf8)) ?? "")
                let needsBuildContextFiles = rawText.uppercased().contains("\nCOPY ") || rawText.uppercased().contains("\nADD ")

                let resolvedContextDir: String
                if let explicitContext = request.dockerfileContextDirectory, explicitContext != desktopPath {
                    resolvedContextDir = explicitContext
                } else if parentDir == desktopPath && !needsBuildContextFiles {
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    resolvedContextDir = tempDir.path
                } else {
                    resolvedContextDir = request.dockerfileContextDirectory ?? parentDir
                }

                if let editedContent = request.dockerfileContent,
                   let diskContent = try? String(contentsOfFile: existingPath, encoding: .utf8),
                   editedContent != diskContent {
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let tempFile = tempDir.appendingPathComponent("Containerfile")
                    try? editedContent.write(to: tempFile, atomically: true, encoding: .utf8)
                    containerfilePath = tempFile.path
                    contextDir = resolvedContextDir
                } else {
                    containerfilePath = existingPath
                    contextDir = resolvedContextDir
                }
            } else {
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempFile = tempDir.appendingPathComponent("Containerfile")
                try? (request.dockerfileContent ?? "FROM alpine:latest\n").write(to: tempFile, atomically: true, encoding: .utf8)
                containerfilePath = tempFile.path
                contextDir = request.dockerfileContextDirectory ?? tempDir.path
            }

            let targetTag: String = {
                let trimmedRef = request.imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRef.isEmpty {
                    return trimmedRef
                }
                let baseName = request.name.isEmpty ? "dockerfile-app" : request.name
                return "local/\(baseName):latest"
            }()
            effectiveRequest.imageReference = targetTag

            let buildReq = ImageBuildRequest(
                contextDirectory: contextDir,
                containerfilePath: containerfilePath,
                tags: [targetTag],
                platform: request.platform,
                cpus: max(1, request.cpus),
                memoryMB: max(512, request.memoryMB)
            )

            onProgressLine("==> Building OCI image '\(targetTag)' from \(URL(fileURLWithPath: containerfilePath).lastPathComponent)…")

            var buildSucceeded = false
            let buildStart = Date()
            var collectedLog = ""

            await performOperation(
                category: "Builds",
                title: "Build Dockerfile Image (\(targetTag))",
                redactedCommand: SecretRedactor.formatCommandPreview(
                    executable: installation.executablePath ?? "container",
                    arguments: buildReq.buildCLIArguments()
                ),
                refreshAfter: false
            ) {
                let res = try await runtimeService.buildImage(request: buildReq) { line in
                    onProgressLine(line)
                }
                collectedLog = res.combinedOutput
                buildSucceeded = true
                return "Built image \(targetTag) for container deployment."
            }

            appendBuildRecord(
                BuildRecord(
                    tags: [targetTag],
                    contextDirectory: contextDir,
                    containerfilePath: containerfilePath,
                    startedAt: buildStart,
                    finishedAt: Date(),
                    status: buildSucceeded ? .succeeded : .failed,
                    exitCode: buildSucceeded ? 0 : 1,
                    logOutput: collectedLog
                )
            )

            try? FileManager.default.removeItem(at: tempDir)

            guard buildSucceeded else {
                onProgressLine("==> Image build failed. Aborting container launch.")
                onComplete?()
                return
            }
        } else if request.hasAttachedDockerfile && !request.buildFromDockerfileBeforeRun {
            // Use the base image directly if user unchecked "Build Dockerfile Before Deploying"
            if let base = request.dockerfileBaseImage, !base.isEmpty,
               effectiveRequest.imageReference.hasPrefix("local/") {
                effectiveRequest.imageReference = base
            }
        }

        // Step 2: Create or Run the Container
        onProgressLine("==> Launching container from '\(effectiveRequest.imageReference)'…")
        let preview = SecretRedactor.formatCommandPreview(
            executable: installation.executablePath ?? "container",
            arguments: effectiveRequest.buildCLIArguments()
        )

        let reqToRun = effectiveRequest
        var createdContainerID: String? = nil
        await performOperation(
            category: "Containers",
            title: reqToRun.startImmediately ? "Run Container" : "Create Container",
            redactedCommand: preview
        ) {
            let id = try await self.runtimeService.createOrRunContainer(request: reqToRun)
            createdContainerID = id
            onProgressLine("==> Container '\(id)' deployed (\(reqToRun.startImmediately ? "running" : "created")).")
            await MainActor.run {
                self.selectedContainerID = id
                self.selectedSection = .containers
            }
            return "Container '\(id)' \(reqToRun.startImmediately ? "started" : "created") from \(reqToRun.imageReference)."
        }

        if reqToRun.startImmediately, let cid = createdContainerID, activeError == nil {
            await verifyContainerRunningOrDiagnoseExit(id: cid)
        }

        onComplete?()
    }

    public func startContainerWithVerification(id: String) async {
        activeError = nil
        startingContainerIDs.insert(id)
        statusFeedbackMessage = "Starting container '\(id)'…"
        defer {
            startingContainerIDs.remove(id)
        }

        await performOperation(
            category: "Containers",
            title: "Start Container \(id)",
            redactedCommand: "container start \(id)"
        ) {
            try await self.runtimeService.startContainer(id: id)
            return "Started '\(id)'."
        }

        guard activeError == nil else {
            statusFeedbackMessage = nil
            return
        }

        await verifyContainerRunningOrDiagnoseExit(id: id)
    }

    public func verifyContainerRunningOrDiagnoseExit(id: String) async {
        // Directly query container state when talking to the live CLI daemon, bypassing refreshAll's isRefreshing guard
        if currentInjectedService == nil {
            let pollDelaysMs = [450, 500, 600]
            for delayMs in pollDelaysMs {
                try? await Task.sleep(for: .milliseconds(delayMs))
                if let fresh = try? await runtimeService.listContainers(includeStopped: true) {
                    self.containers = fresh
                    if fresh.first(where: { $0.id == id })?.state == .running {
                        break
                    }
                }
            }
        }

        guard var container = containers.first(where: { $0.id == id }) else {
            statusFeedbackMessage = nil
            return
        }

        if container.state == .running {
            markContainerVerifiedRunning(id: id)
            return
        }

        // Fetch logs to inspect whether the process actually exited or is still booting
        let appLogs = (try? await runtimeService.fetchContainerLogs(id: id, bootLogs: false, tailLines: 40))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bootLogs = (try? await runtimeService.fetchContainerLogs(id: id, bootLogs: true, tailLines: 25))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Re-check live container list and boot log events to guard against background refresh races
        if currentInjectedService == nil {
            let lastStartRange = bootLogs.range(of: "started managed process", options: .backwards)
            let lastExitRange = bootLogs.range(of: "managed process exit", options: .backwards)
            let bootLogShowsProcessStillAlive: Bool = {
                guard let startPos = lastStartRange else { return false }
                if let exitPos = lastExitRange {
                    return startPos.lowerBound > exitPos.lowerBound
                }
                return true
            }()

            if bootLogShowsProcessStillAlive {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if let fresh = try? await runtimeService.listContainers(includeStopped: true) {
                self.containers = fresh
                if let updated = fresh.first(where: { $0.id == id }) {
                    container = updated
                }
            }
            if container.state == .running || bootLogShowsProcessStillAlive {
                markContainerVerifiedRunning(id: id)
                return
            }
        }

        // The container started and immediately exited/stopped! Report accurate diagnostics.
        statusFeedbackMessage = nil
        var diagSections: [String] = []
        let cmdPreview = ([container.configuration.executable] + container.configuration.arguments).joined(separator: " ")
        diagSections.append("Configured Command: \(cmdPreview)")
        if !appLogs.isEmpty {
            diagSections.append("--- Container Stdout / Stderr (`container logs \(id)`) ---\n\(appLogs)")
        }
        if !bootLogs.isEmpty {
            diagSections.append("--- VM Init / Boot Log (`container logs --boot \(id)`) ---\n\(bootLogs)")
        }
        let combinedDiag = diagSections.joined(separator: "\n\n")

        let firstLogHint: String = {
            if let firstNonEmpty = appLogs.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return " Process output: \"\(firstNonEmpty.prefix(120))\""
            }
            return ""
        }()

        let crashError = LadaError(
            category: .containerLifecycleFailure,
            explanation: "Container '\(id)' started, but its main process exited immediately (state: \(container.rawState)).\(firstLogHint)",
            diagnosticOutput: combinedDiag,
            suggestedRemediation: "Check the container's command/arguments, entrypoint, or port configuration. See Technical Details below for the container's error output.",
            isRetryable: false
        )
        self.activeError = crashError
        recordActivity(
            category: "Containers",
            title: "Container Exited on Start (\(id))",
            detail: crashError.explanation,
            outcome: .failure
        )
    }

    private func markContainerVerifiedRunning(id: String) {
        statusFeedbackMessage = "Container '\(id)' is running."
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.statusFeedbackMessage == "Container '\(id)' is running." {
                self.statusFeedbackMessage = nil
            }
        }
    }
}
