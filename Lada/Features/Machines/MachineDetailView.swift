import SwiftUI
import AppKit

/// The inspector for one container machine, laid out like the container inspector: a header with
/// actions, then Overview (details, live charts, run a command), Terminal (the machine's login
/// shell), Files, Logs, Settings and Inspect. State lives in the machine's workspace.
struct MachineDetailView: View {
    @ObservedObject var appState: AppState
    let machine: MachineModel
    @ObservedObject var workspace: MachineWorkspace
    let onDelete: () -> Void

    @State private var commandInput = "uname -a"
    @State private var commandOutput = ""
    @State private var isRunningCommand = false
    @State private var showBootLogs = false
    @State private var editCPUs = 4
    @State private var editMemoryGB = 8
    @State private var editHomeMount: HomeMountMode = .rw
    @State private var editVirtualization = false

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }
    private var isRunning: Bool { machine.status == .running }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Tab", selection: Binding(
                get: { workspace.tab },
                set: { appState.machineWorkspaces.select($0, for: machine.id) }
            )) {
                ForEach(MachineWorkspace.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .nordicBar()
            .overlay(alignment: .bottom) { Divider().overlay(NordicTheme.borderSubtle) }
            .accessibilityIdentifier("lada.machine.tabs")

            switch workspace.tab {
            case .overview: overviewTab
            case .terminal: terminalTab
            case .files: filesTab
            case .logs: logsTab
            case .settings: settingsTab
            case .inspect: inspectTab
            }
        }
        .onAppear(perform: loadEditableSettings)
        .onChange(of: appState.refreshGeneration) { _, _ in
            if workspace.tab == .logs { Task { await loadLogs() } }
        }
        .onChange(of: machine) { _, _ in loadEditableSettings() }
    }

    // MARK: - Header

    private var header: some View {
        NordicDetailHeader(
            title: machine.name,
            subtitle: [machine.imageReference.map(DockerfileCompletionEngine.shortImage), machine.cpus > 0 ? "\(machine.cpus) vCPU" : nil,
                       machine.memoryBytes > 0 ? NordicFormat.bytes(fromByteCount: Int64(machine.memoryBytes), countStyle: .memory) : nil,
                       machine.ipAddress].compactMap { $0 }.joined(separator: " · "),
            badge: NordicStatusBadge(containerState: machine.status)
        ) {
            if isRunning {
                Button { Task { await stop() } } label: { Image(systemName: "stop.fill") }
                    .help("Stop the machine (container machine stop)")
            } else {
                Button { Task { await start() } } label: { Image(systemName: "play.fill") }
                    .help("Boot the machine (container machine run … true)")
            }
            Button { appState.openExternalTerminalForMachine(id: machine.id) } label: { Image(systemName: "apple.terminal") }
                .help("Open the machine's login shell in Terminal.app")
                .accessibilityIdentifier("lada.machine.openTerminalApp")
            Button { Task { await setDefault() } } label: { Image(systemName: machine.isDefault ? "star.fill" : "star") }
                .disabled(machine.isDefault)
                .help(machine.isDefault ? "This is the default machine" : "Make this the default machine (used when no name is given)")
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .help("Delete the machine and its disk")
        }
    }

    // MARK: - Overview

    private var overviewTab: some View {
        let samples = machine.containerID.flatMap { appState.containerTelemetryHistory[$0] } ?? []
        let latest = samples.last
        let stats = machine.containerID.flatMap { appState.containerStats[$0] }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NordicSectionHeader("Details", info: "What `container machine inspect` reports for this machine.")
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    detailRow("Name", machine.name)
                    detailRow("Image", machine.imageReference ?? "—")
                    detailRow("State", machine.status.displayTitle)
                    if let ip = machine.ipAddress { detailRow("IP address", ip) }
                    if let user = machine.username {
                        detailRow("User", user, info: "Commands and the login shell run as this user, matching your Mac account. Run as root from Settings → Run a command.")
                    }
                    if let home = machine.homeDirectory { detailRow("Home", home) }
                    detailRow("Home mount", machine.homeMount.displayTitle,
                              info: "How your Mac home folder is shared into the machine: read-write, read-only or not at all. Change it in Settings.")
                    detailRow("Resources", "\(machine.cpus > 0 ? "\(machine.cpus) vCPUs" : "—") • \(machine.memoryBytes > 0 ? NordicFormat.bytes(fromByteCount: Int64(machine.memoryBytes), countStyle: .memory) : "—") RAM")
                    if let disk = machine.diskSizeBytes {
                        detailRow("Disk size", NordicFormat.bytes(fromByteCount: Int64(disk), countStyle: .file), info: "The machine's disk size as reported by the runtime.")
                    }
                    detailRow("Default", machine.isDefault ? "Yes" : "No",
                              info: "The default machine is used by `container machine` commands that don't name one.")
                    detailRow("Nested virtualization", machine.virtualizationEnabled ? "On" : "Off",
                              info: "Lets the machine run its own VMs (KVM). Needs an M3 or newer chip.")
                    if let created = machine.createdDate { detailRow("Created", created.formatted(date: .abbreviated, time: .standard)) }
                    if let started = machine.startedDate, isRunning { detailRow("Started", started.formatted(date: .abbreviated, time: .standard)) }
                    if let cid = machine.containerID {
                        detailRow("Container ID", cid, info: "The container that runs this machine. Stats, files and copies go through it.")
                    }
                }
                .font(.system(size: 12))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nordicSurface()

                NordicSectionHeader(
                    "Performance",
                    subtitle: isRunning ? nil : "Start the machine to see live CPU, memory, network and disk activity.",
                    trailingText: isRunning ? stats.map { "\($0.numProcesses) processes" } : nil,
                    info: "Measured every 2 seconds with `container stats` on the machine's container."
                )
                LazyVGrid(columns: [GridItem(.flexible(minimum: 220), spacing: 12), GridItem(.flexible(minimum: 220), spacing: 12)], spacing: 12) {
                    NordicPerformanceChartCard(
                        title: "CPU", iconName: "cpu",
                        primaryMetricText: isRunning ? String(format: "%.1f%%", latest?.cpuPercent ?? 0) : "0.0%",
                        secondaryMetricText: String(format: "%.2f", isRunning ? (latest?.cpuCoresUsed ?? 0) : 0) + " of \(machine.cpus) vCPU busy",
                        primarySeries: isRunning ? samples.map(\.cpuPercent) : [],
                        primaryLegend: "Utilization", fixedMaxY: 100,
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: accent,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatPercent
                    )
                    NordicPerformanceChartCard(
                        title: "Memory", iconName: "memorychip",
                        primaryMetricText: isRunning ? NordicFormat.bytes(fromByteCount: Int64(stats?.memoryUsageBytes ?? latest?.memoryUsageBytes ?? 0), countStyle: .memory) : "0 MB",
                        secondaryMetricText: "Limit: \(NordicFormat.bytes(fromByteCount: Int64(stats?.memoryLimitBytes ?? machine.memoryBytes), countStyle: .memory))",
                        primarySeries: isRunning ? samples.map(\.memoryPercent) : [],
                        primaryLegend: "Used %", fixedMaxY: 100,
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: NordicTheme.statusGreen,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatPercent
                    )
                    NordicPerformanceChartCard(
                        title: "Network", iconName: "network",
                        primaryMetricText: isRunning ? "↓ \(NordicPerformanceChartCard.formatRate(latest?.networkRxRateBps ?? 0))  ↑ \(NordicPerformanceChartCard.formatRate(latest?.networkTxRateBps ?? 0))" : "↓ 0 B/s  ↑ 0 B/s",
                        secondaryMetricText: "Total RX \(NordicFormat.bytes(fromByteCount: Int64(stats?.networkRxBytes ?? 0), countStyle: .file)) • TX \(NordicFormat.bytes(fromByteCount: Int64(stats?.networkTxBytes ?? 0), countStyle: .file))",
                        primarySeries: isRunning ? samples.map(\.networkRxRateBps) : [],
                        secondarySeries: isRunning ? samples.map(\.networkTxRateBps) : [],
                        primaryLegend: "RX", secondaryLegend: "TX",
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: accent, secondaryColor: NordicTheme.statusAmber,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatRate
                    )
                    NordicPerformanceChartCard(
                        title: "Disk", iconName: "internaldrive",
                        primaryMetricText: isRunning ? "R \(NordicPerformanceChartCard.formatRate(latest?.diskReadRateBps ?? 0))  W \(NordicPerformanceChartCard.formatRate(latest?.diskWriteRateBps ?? 0))" : "R 0 B/s  W 0 B/s",
                        secondaryMetricText: "Total Read \(NordicFormat.bytes(fromByteCount: Int64(stats?.blockReadBytes ?? 0), countStyle: .file)) • Write \(NordicFormat.bytes(fromByteCount: Int64(stats?.blockWriteBytes ?? 0), countStyle: .file))",
                        primarySeries: isRunning ? samples.map(\.diskReadRateBps) : [],
                        secondarySeries: isRunning ? samples.map(\.diskWriteRateBps) : [],
                        primaryLegend: "Read", secondaryLegend: "Write",
                        placeholder: isRunning ? "Collecting…" : "Not running",
                        primaryColor: NordicTheme.statusGreen, secondaryColor: NordicTheme.statusAmber,
                        timestamps: isRunning ? samples.map(\.timestamp) : [],
                        valueFormatter: NordicPerformanceChartCard.formatRate
                    )
                }

                commandRunner
            }
            .padding(16)
        }
    }

    private var commandRunner: some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader("Run a Command",
                                info: "Runs one command with `container machine run -n \(machine.id) -- …` and shows its output. The machine boots if it is stopped. For an interactive shell use the Terminal tab.")
            HStack {
                TextField("Command (e.g. uname -a)", text: $commandInput)
                    .textFieldStyle(.roundedBorder)
                    .font(NordicTheme.monoFontRegular)
                    .onSubmit { runCommand() }
                Button(isRunningCommand ? "Running…" : "Run", action: runCommand)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(isRunningCommand || commandInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(commandOutput.isEmpty ? "Output appears here." : commandOutput)
                .font(NordicTheme.monoFontRegular)
                .foregroundStyle(commandOutput.isEmpty ? NordicTheme.secondaryText : NordicTheme.primaryText)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .nordicChip()
        }
        .padding(14)
        .nordicSurface()
    }

    // MARK: - Terminal & Files

    private var terminalTab: some View {
        InteractiveTerminalView(
            target: .machine(machine),
            executablePath: appState.installation.executablePath,
            session: workspace.terminal,
            onOpenExternalTerminal: { _ in appState.openExternalTerminalForMachine(id: machine.id) }
        )
    }

    @ViewBuilder
    private var filesTab: some View {
        if let cid = machine.containerID {
            ContainerFileBrowserView(
                appState: appState,
                target: FileBrowserTarget(execID: cid, name: machine.id, isRunning: isRunning),
                state: workspace.files
            )
            .onAppear {
                // Start in the user's home the first time.
                if workspace.files.entries.isEmpty, workspace.files.currentPath == "/", let home = machine.homeDirectory {
                    workspace.files.currentPath = home
                }
            }
        } else {
            NordicEmptyState(
                icon: .volumes,
                title: "Files Aren't Available",
                description: "The runtime didn't report this machine's container ID, which browsing files needs."
            )
        }
    }

    // MARK: - Logs

    private var logsTab: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Boot log", isOn: $showBootLogs)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .nordicInfo("The VM's boot console instead of the machine's own log.")
                Spacer()
                Button { Task { await loadLogs() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .nordicBar()
            ScrollView {
                Text(workspace.logsText.isEmpty ? "No logs yet." : workspace.logsText)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(workspace.logsText.isEmpty ? NordicTheme.secondaryText : NordicTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
        }
        .task(id: "\(machine.id)-\(showBootLogs)") { await loadLogs() }
    }

    // MARK: - Settings

    private var settingsTab: some View {
        let request = MachineUpdateRequest(name: machine.name, cpus: editCPUs, memoryGB: editMemoryGB, homeMount: editHomeMount, enableVirtualization: editVirtualization)
        let changed = editCPUs != machine.cpus || UInt64(editMemoryGB) * 1_073_741_824 != machine.memoryBytes
            || editHomeMount != machine.homeMount || editVirtualization != machine.virtualizationEnabled
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NordicSectionHeader("Hardware & Sharing",
                                    subtitle: "Changes take effect the next time the machine boots.",
                                    info: "Saved with `container machine set`. A running machine keeps its current settings until it is stopped and booted again.")
                VStack(alignment: .leading, spacing: 12) {
                    Stepper(value: $editCPUs, in: 1...32) { Text(verbatim: "CPUs: \(editCPUs)") }
                        .nordicInfo("Virtual CPUs the machine may use. They are shared with your Mac, not reserved.")
                    Stepper(value: $editMemoryGB, in: 1...64) { Text(verbatim: "Memory: \(editMemoryGB) GB") }
                        .nordicInfo("The most memory the machine can use. Memory is only taken from your Mac as the machine needs it.")
                    Picker("Home folder", selection: $editHomeMount) {
                        ForEach(HomeMountMode.allCases, id: \.rawValue) { Text($0.displayTitle).tag($0) }
                    }
                    .fixedSize()
                    .nordicInfo("Share your Mac home folder into the machine read-write, read-only, or not at all.")
                    Toggle("Nested virtualization", isOn: $editVirtualization)
                        .nordicInfo("Lets the machine run its own virtual machines (KVM). Needs an M3 chip or newer.")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nordicSurface()

                Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: request.buildCLIArguments()))
                    .font(NordicTheme.monoFontSmall)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nordicChip()

                HStack {
                    Button("Revert", action: loadEditableSettings)
                        .disabled(!changed)
                    Spacer()
                    if isRunning {
                        Button("Save, Then Restart") { Task { await apply(request, restart: true) } }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(!changed)
                            .help("Saves the settings, stops the machine and boots it again so they take effect")
                    } else {
                        Button("Save") { Task { await apply(request, restart: false) } }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(!changed)
                    }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
    }

    // MARK: - Inspect

    private var inspectTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("container machine inspect \(machine.id)")
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(machine.rawInspectJSON ?? "", forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .nordicBar()
            ScrollView {
                Text(machine.rawInspectJSON ?? "Not reported.")
                    .font(NordicTheme.monoFontSmall)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
        }
    }

    // MARK: - Helpers & actions

    private func detailRow(_ label: String, _ value: String, info: String? = nil) -> some View {
        GridRow {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(NordicTheme.secondaryText)
                if let info { NordicInfoTip(info, title: label) }
            }
            Text(value).font(NordicTheme.monoFontRegular).textSelection(.enabled)
        }
    }

    private func loadEditableSettings() {
        editCPUs = max(1, machine.cpus)
        editMemoryGB = max(1, Int(machine.memoryBytes / 1_073_741_824))
        editHomeMount = machine.homeMount
        editVirtualization = machine.virtualizationEnabled
    }

    private func loadLogs() async {
        workspace.logsText = (try? await appState.runtimeService.fetchMachineLogs(id: machine.id, bootLogs: showBootLogs, tailLines: 500)) ?? ""
    }

    private func runCommand() {
        let parts = commandInput.split(separator: " ").map(String.init)
        guard !parts.isEmpty, !isRunningCommand else { return }
        isRunningCommand = true
        Task {
            let result = try? await appState.runtimeService.runInMachine(id: machine.id, command: parts, asRoot: false)
            commandOutput = result.map { SecretRedactor.redact($0.combinedOutput) } ?? "The command could not be run."
            isRunningCommand = false
        }
    }

    private func start() async {
        await appState.performOperation(category: "Machines", title: "Start Machine \(machine.name)", redactedCommand: "container machine run -n \(machine.name) true") {
            try await appState.runtimeService.startMachine(id: machine.id)
            return "Started machine '\(machine.name)'."
        }
    }

    private func stop() async {
        await appState.performOperation(category: "Machines", title: "Stop Machine \(machine.name)", redactedCommand: "container machine stop \(machine.name)") {
            try await appState.runtimeService.stopMachine(id: machine.id)
            return "Stopped machine '\(machine.name)'."
        }
    }

    private func setDefault() async {
        await appState.performOperation(category: "Machines", title: "Set Default Machine \(machine.name)", redactedCommand: "container machine set-default \(machine.name)") {
            try await appState.runtimeService.setDefaultMachine(id: machine.id)
            return "'\(machine.name)' is now the default machine."
        }
    }

    private func apply(_ request: MachineUpdateRequest, restart: Bool) async {
        await appState.performOperation(
            category: "Machines",
            title: "Reconfigure Machine \(machine.name)",
            redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: request.buildCLIArguments())
        ) {
            try await appState.runtimeService.updateMachineConfig(request: request)
            if restart {
                try await appState.runtimeService.stopMachine(id: machine.id)
                try await appState.runtimeService.startMachine(id: machine.id)
                return "Saved settings and restarted '\(machine.name)'."
            }
            return "Saved settings for '\(machine.name)'; they apply at the next boot."
        }
    }
}
