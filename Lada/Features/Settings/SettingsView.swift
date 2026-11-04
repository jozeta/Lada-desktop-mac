import AppKit
import SwiftUI

public struct ActivityView: View {
    @ObservedObject var appState: AppState
    @State private var selectedCategory = "All"

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredEvents: [ActivityEvent] {
        appState.activityEvents.filter { ev in
            selectedCategory == "All" || ev.category.lowercased().contains(selectedCategory.lowercased())
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Activity & Command Audit Log (\(filteredEvents.count))")
                    .font(NordicTheme.subtitleFont)
                    .foregroundStyle(NordicTheme.primaryText)
                Spacer()
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag("All")
                    Text("Runtime").tag("Runtime")
                    Text("Containers").tag("Containers")
                    Text("Images").tag("Images")
                    Text("Builds").tag("Builds")
                    Text("Networks").tag("Networks")
                    Text("Volumes").tag("Volumes")
                    Text("Machines").tag("Machines")
                    Text("Registries").tag("Registries")
                }
                .frame(width: 160)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .nordicBar()
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            if filteredEvents.isEmpty {
                NordicEmptyState(
                    icon: .activity,
                    title: "No Activity Recorded",
                    description: "Operations performed in Låda are logged here with redacted CLI invocations, durations, and timestamps."
                )
            } else {
                List(filteredEvents) { ev in
                    HStack(alignment: .top, spacing: 12) {
                        NordicStatusBadge(
                            label: ev.outcome.rawValue,
                            tone: ev.outcome == .success ? .positive : (ev.outcome == .failure ? .critical : .warning)
                        )
                        .frame(width: 95, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(ev.category)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                Text("•")
                                    .foregroundStyle(NordicTheme.secondaryText)
                                Text(ev.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NordicTheme.primaryText)
                            }
                            if !ev.detail.isEmpty {
                                Text(ev.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                            if let cmd = ev.redactedCommand {
                                Text(cmd)
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ev.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                            if let ms = ev.durationMs {
                                Text(verbatim: "\(ms) ms")
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct SettingsNavRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? accent : NordicTheme.secondaryText)
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(NordicTheme.primaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accent.opacity(0.14) : (isHovered ? NordicTheme.borderSubtle.opacity(0.5) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var prefs: AppPreferences
    @State private var selectedTab = "runtime"
    @State private var systemLogsText = ""
    @State private var diagnosticSummaryCopied = false

    private static let tabs: [(id: String, title: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("runtime", "System & Runtime", "cpu"),
        ("resources", "Resources & DNS", "memorychip"),
        ("registries", "Registries", "key"),
        ("appearance", "Appearance", "paintbrush"),
        ("notifications", "Notifications", "bell"),
        ("diagnostics", "Diagnostics", "stethoscope"),
        ("advanced", "Advanced", "wrench.and.screwdriver"),
        ("about", "About", "info.circle")
    ]

    public init(appState: AppState, initialTab: String = "runtime") {
        self.appState = appState
        self.prefs = appState.preferences
        _selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        HSplitView {
            // Section navigation drawn with Nordic surfaces rather than a second system sidebar,
            // whose translucent material clashed with the solid panels around it.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.tabs, id: \.id) { tab in
                    SettingsNavRow(
                        title: tab.title,
                        systemImage: tab.icon,
                        isSelected: selectedTab == tab.id,
                        accent: NordicTheme.accent(for: prefs.accentThemeChoice)
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab.id }
                    }
                    .accessibilityIdentifier("lada.settings.tab.\(tab.id)")
                }
                Spacer()
            }
            .padding(10)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 230, maxHeight: .infinity, alignment: .top)
            .background(NordicSidebarMaterial().ignoresSafeArea())
            .overlay(alignment: .trailing) { Rectangle().fill(NordicTheme.borderSubtle).frame(width: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case "general":
                        generalSection
                    case "runtime":
                        runtimeSection
                    case "resources":
                        resourcesSection
                    case "registries":
                        RegistriesView(appState: appState)
                            .frame(minHeight: 420)
                    case "appearance":
                        appearanceSection
                    case "notifications":
                        notificationsSection
                    case "diagnostics":
                        diagnosticsSection
                    case "advanced":
                        advancedSection
                    case "about":
                        AboutSection(appState: appState)
                    default:
                        runtimeSection
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NordicSectionHeader("General Preferences", subtitle: "Startup landing section, refresh interval, and confirmation prompts", info: "How Låda starts and behaves: the page it opens on, how often the full inventory refreshes, and which actions ask for confirmation.")
            Form {
                Picker("Default Landing Screen", selection: $prefs.defaultLandingSectionRaw) {
                    ForEach(NavigationSection.allCases) { sec in
                        Text(sec.rawValue).tag(sec.rawValue)
                    }
                }
                .nordicInfo("The page Låda opens on when it starts.")
                Stepper(value: $prefs.autoRefreshIntervalSeconds, in: 5...120, step: 5) {
                    Text(verbatim: "Auto-Refresh Interval: \(prefs.autoRefreshIntervalSeconds)s")
                }
                .nordicInfo("How often Låda reloads everything from the runtime (images, volumes, networks…). Containers and live stats refresh every 2 seconds regardless.")
                Toggle("Confirm Destructive Actions (Delete / Prune)", isOn: $prefs.confirmDestructiveActions)
                    .nordicInfo("Ask before deleting or pruning containers, images, volumes and networks.")
                Toggle("Confirm Before Stopping Running Containers", isOn: $prefs.confirmStopContainer)
                    .nordicInfo("Ask before stopping a running container.")
            }
            .nordicFormPanel()
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader(
                "System & Runtime Dependency Management",
                subtitle: "Inspect, start/stop, verify, and repair Apple's official `container` runtime",
                info: "Where the runtime is installed, its version and whether its services are running."
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Container Runtime")
                            .font(.system(size: 14, weight: .semibold))
                        Text(appState.installation.executablePath ?? "Not found in /usr/local/bin or /opt/homebrew/bin")
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    NordicStatusBadge(
                        label: appState.systemStatus.state.displayTitle,
                        tone: appState.systemStatus.state.isHealthy ? .positive : .warning
                    )
                }

                Divider()

                LabeledContent("Installed CLI Version", value: appState.installation.cliVersion?.description ?? "Not Installed")
                LabeledContent("Daemon / API Server Version", value: appState.systemStatus.serverVersion?.version ?? "Not Running")
                LabeledContent("Helper Plugins Present", value: appState.installation.helperPluginsPresent ? "Yes" : "No")
                LabeledContent("Default Linux Kernel Installed", value: appState.installation.defaultKernelInstalled ? "Yes" : "No")
                LabeledContent("Host Architecture", value: "\(appState.hostEnvironment.cpuArchitecture) (\(appState.hostEnvironment.cpuBrandString))")
                LabeledContent("macOS Version", value: "\(appState.hostEnvironment.macOSVersionString) (\(appState.hostEnvironment.macOSBuildString))")

                HStack(spacing: 10) {
                    if appState.systemStatus.state == .running {
                        Button("Stop Container System") {
                            Task {
                                await appState.performOperation(
                                    category: "Runtime",
                                    title: "Stop Container System",
                                    redactedCommand: "container system stop"
                                ) {
                                    try await appState.runtimeService.stopSystemService()
                                    return "Stopped Apple container API server."
                                }
                            }
                        }
                    } else {
                        Button("Start Container System") {
                            Task {
                                await appState.performOperation(
                                    category: "Runtime",
                                    title: "Start Container System",
                                    redactedCommand: "container system start --enable-kernel-install"
                                ) {
                                    try await appState.runtimeService.startSystemService(enableKernelInstall: true)
                                    return "Started Apple container API server."
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NordicTheme.accent(for: prefs.accentThemeChoice))
                    }

                    Button("Re-run Prerequisite Checks") {
                        Task { await appState.refreshAll() }
                    }

                    Button("Open Setup & Repair Wizard…") {
                        appState.showSetupWizard = true
                    }

                    Button("Official Documentation") {
                        if let url = URL(string: "https://apple.github.io/container/documentation/") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(14)
            .nordicSurface()

            VStack(alignment: .leading, spacing: 8) {
                NordicSectionHeader("Prerequisite Verification Summary", info: "Checks that this Mac can run Apple's container runtime: Apple silicon, macOS version, the CLI and its services.")
                ForEach(appState.prerequisites) { item in
                    HStack {
                        NordicStatusBadge(prerequisiteStatus: item.status)
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(item.detectedStatusText)
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
            }
            .padding(14)
            .nordicSurface()
        }
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader(
                "Default Container Resources & Runtime Properties",
                subtitle: "Configure default CPU/RAM allocations and inspect `container system property list`",
                info: "The runtime's services (`container system start/stop`). Restart them after upgrading the CLI so versions match."
            )

            Form {
                Stepper(value: $prefs.defaultContainerCPUs, in: 1...32) {
                    Text(verbatim: "Default Container CPUs: \(prefs.defaultContainerCPUs) cores")
                }
                .nordicInfo("CPUs a new container gets unless you choose otherwise in the Create Container wizard.")
                Picker("Default Container Memory", selection: $prefs.defaultContainerMemoryMB) {
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("8 GB").tag(8192)
                }
                .nordicInfo("Memory a new container gets unless you choose otherwise.")
                Stepper(value: $prefs.defaultBuildCPUs, in: 1...32) {
                    Text(verbatim: "Default BuildKit CPUs: \(prefs.defaultBuildCPUs) cores")
                }
                .nordicInfo("CPUs for the BuildKit builder that builds images from Dockerfiles.")
                Picker("Default BuildKit Memory", selection: $prefs.defaultBuildMemoryMB) {
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("8 GB").tag(8192)
                }
                .nordicInfo("Memory for the BuildKit builder. Large builds may need more.")
            }
            .nordicFormPanel()

            VStack(alignment: .leading, spacing: 8) {
                NordicSectionHeader("Runtime System Properties (`container system property list`)", info: "Defaults the runtime applies to new containers and machines, read from `container system property list`. Change them with `container system property set`.")
                LabeledContent("container.cpus", value: "\(appState.systemProperties.container.cpus)")
                    .font(NordicTheme.monoFontSmall)
                LabeledContent("container.memory", value: appState.systemProperties.container.memory)
                    .font(NordicTheme.monoFontSmall)
                LabeledContent("build.cpus", value: "\(appState.systemProperties.build.cpus)")
                    .font(NordicTheme.monoFontSmall)
                LabeledContent("build.memory", value: appState.systemProperties.build.memory)
                    .font(NordicTheme.monoFontSmall)
                LabeledContent("build.image", value: appState.systemProperties.build.image)
                    .font(NordicTheme.monoFontSmall)
                LabeledContent("registry.domain", value: appState.systemProperties.registry.domain)
                    .font(NordicTheme.monoFontSmall)
                LabeledContent("vminit.image", value: appState.systemProperties.vminit.image)
                    .font(NordicTheme.monoFontSmall)
                if let cpus = appState.systemProperties.machine.cpus {
                    LabeledContent("machine.cpus", value: "\(cpus)")
                        .font(NordicTheme.monoFontSmall)
                }
                if let memory = appState.systemProperties.machine.memory {
                    LabeledContent("machine.memory", value: memory)
                        .font(NordicTheme.monoFontSmall)
                }
                if let homeMount = appState.systemProperties.machine.homeMount {
                    LabeledContent("machine.homeMount", value: homeMount.rawValue)
                        .font(NordicTheme.monoFontSmall)
                }
                if let virtualization = appState.systemProperties.machine.virtualization {
                    LabeledContent("machine.virtualization", value: virtualization ? "true" : "false")
                        .font(NordicTheme.monoFontSmall)
                }
                if let dnsDomain = appState.systemProperties.dns.domain {
                    LabeledContent("dns.domain", value: dnsDomain)
                        .font(NordicTheme.monoFontSmall)
                }
                if let subnet = appState.systemProperties.network.subnet {
                    LabeledContent("network.subnet", value: subnet)
                        .font(NordicTheme.monoFontSmall)
                }
            }
            .padding(14)
            .nordicSurface()
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Technical Nordic Appearance", subtitle: "Theme, accent color, and table density", info: "Light or dark mode, the accent colour and how dense tables are. Applies at once.")
            Form {
                Picker("Theme Mode", selection: $prefs.appearanceModeRaw) {
                    ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .nordicInfo("Follow macOS, or always use light or dark.")
                LabeledContent {
                    AccentSwatchGrid(selection: $prefs.accentThemeChoiceRaw)
                } label: {
                    Text("Accent Palette").nordicInfo("The colour used for selection, buttons, charts and highlights.")
                }
                Picker("Interface Density", selection: $prefs.uiDensityModeRaw) {
                    ForEach(UIDensityMode.allCases, id: \.rawValue) { density in
                        Text(density.displayName).tag(density.rawValue)
                    }
                }
                .nordicInfo("Compact uses smaller controls, tighter panels and shorter rows, to fit more on screen.")
            }
            .nordicFormPanel()
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Notifications & Alerts", info: "macOS notifications for finished operations and containers that stop unexpectedly. Only available when Låda runs as an app bundle.")
            Form {
                Toggle("Notify on Build Completion", isOn: $prefs.notifyBuildCompletion)
                    .nordicInfo("A macOS notification when an image build finishes.")
                Toggle("Notify on Container Operations Failure", isOn: $prefs.notifyContainerFailures)
                    .nordicInfo("A macOS notification when a container operation fails or a container stops unexpectedly.")
                Toggle("Notify on Runtime Health Degradation", isOn: $prefs.notifyRuntimeFailures)
                    .nordicInfo("A macOS notification when the runtime's services stop or report a problem.")
            }
            .nordicFormPanel()
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader(
                "Diagnostics & Redacted Support Bundle",
                subtitle: "Inspect system logs and export privacy-redacted diagnostic reports",
                info: "Saves a diagnostics report with secrets removed, for troubleshooting or a bug report."
            )

            HStack(spacing: 10) {
                Button {
                    let report = appState.generateRedactedDiagnosticReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    diagnosticSummaryCopied = true
                } label: {
                    Label(diagnosticSummaryCopied ? "Copied Diagnostic Report" : "Copy Redacted Diagnostic Report", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: prefs.accentThemeChoice))

                Button("Save Diagnostic Bundle…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "lada-diagnostics.txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        let report = appState.generateRedactedDiagnosticReport()
                        try? report.write(to: url, atomically: true, encoding: .utf8)
                    }
                }

                Button("Fetch `container system logs`") {
                    Task {
                        systemLogsText = (try? await appState.runtimeService.fetchSystemLogs(lastPeriod: "15m")) ?? "No system logs returned."
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostic Report Preview (Secrets Automatically Redacted)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)
                ScrollView {
                    Text(appState.generateRedactedDiagnosticReport())
                        .font(NordicTheme.monoFontSmall)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 260)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if !systemLogsText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Container System Logs (Last 15m)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NordicTheme.secondaryText)
                    ScrollView {
                        Text(SecretRedactor.redact(systemLogsText))
                            .font(NordicTheme.monoFontSmall)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 200)
                    .background(NordicTheme.codeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Advanced Runtime Overrides", info: "For unusual setups: point Låda at a different `container` binary or change how it talks to the runtime. Leave empty to auto-detect.")
            Form {
                TextField("Custom `container` CLI Path Override (leave blank for automatic discovery)", text: $prefs.customCLIExecutablePath)
                    .font(NordicTheme.monoFontRegular)
                    .nordicInfo("Use a specific `container` binary instead of the one found in /usr/local/bin or /opt/homebrew/bin.")
                Toggle("Enable Experimental Path Masking Options (`--masked-path`, `--read-only-path`)", isOn: $prefs.enableExperimentalPathMasking)
                    .nordicInfo("Shows the experimental --masked-path and --read-only-path options in the Create Container wizard (experimental in container 1.6).")
                Toggle("Enable Verbose Developer Command Logging", isOn: $prefs.enableDeveloperLogging)
                    .nordicInfo("Logs every command Låda runs, with secrets removed, for troubleshooting.")
                Toggle("Enable Simulation Mode When `container` CLI Is Not Installed", isOn: $prefs.useSimulationWhenCLIMissing)
                    .onChange(of: prefs.useSimulationWhenCLIMissing) { _, _ in
                        Task { await appState.refreshAll() }
                    }
                    .nordicInfo("Without the CLI, Låda shows a simulated runtime so you can explore the app. Nothing is created on your Mac.")
            }
            .nordicFormPanel()
        }
    }
}

/// Accent themes as colour swatches (each shown in the current light/dark appearance).
struct AccentSwatchGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 5), alignment: .leading, spacing: 10) {
            ForEach(AccentThemeChoice.allCases, id: \.rawValue) { choice in
                let selected = selection == choice.rawValue
                Button {
                    selection = choice.rawValue
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(NordicTheme.accent(for: choice)).frame(width: 26, height: 26)
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(selected ? NordicTheme.primaryText.opacity(0.7) : .clear, lineWidth: 2).frame(width: 32, height: 32))
                        .frame(width: 34, height: 34)
                        Text(choice.shortName)
                            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? NordicTheme.primaryText : NordicTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(choice.displayName)
                .accessibilityLabel(choice.displayName)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Settings → About: the app's version, the runtime it talks to, this Mac, and where the code
/// and licences live.
struct AboutSection: View {
    @ObservedObject var appState: AppState
    @State private var copied = false

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }

    private var versionReport: String {
        let host = appState.hostEnvironment
        return """
        Låda \(AppVersion.display)
        container CLI \(appState.installation.cliVersion?.description ?? "not installed")
        Runtime: \(appState.systemStatus.state.displayTitle)
        macOS \(host.macOSVersionString) · \(host.cpuBrandString) (\(host.cpuArchitecture))
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(accent.opacity(0.16))
                    LadaIcon(.appIdentity, size: 44, strokeWidth: 2).foregroundStyle(accent)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Låda")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text("Apple Container Studio")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NordicTheme.secondaryText)
                    Text("Version \(AppVersion.display)")
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(NordicTheme.primaryText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("lada.about.version")
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nordicSurface()

            Text("A native Mac app for Apple's `container` runtime: containers, images, stacks, machines, networks and volumes, with live telemetry. Låda (Swedish for \u{201C}box\u{201D}) runs Apple's own CLI and never changes its binaries or data.")
                .font(.system(size: 12.5))
                .foregroundStyle(NordicTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            NordicSectionHeader("This Setup", info: "Useful in a bug report. Copy puts all of it on the clipboard.")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                row("Låda", AppVersion.display)
                row("container CLI", appState.installation.cliVersion.map { "v\($0.description)" } ?? "Not installed")
                row("CLI path", appState.installation.executablePath ?? "—")
                row("Runtime", appState.systemStatus.state.displayTitle)
                row("macOS", appState.hostEnvironment.macOSVersionString)
                row("Chip", "\(appState.hostEnvironment.cpuBrandString) (\(appState.hostEnvironment.cpuArchitecture))")
            }
            .font(.system(size: 12))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nordicSurface()

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(versionReport, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Version Info", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button {
                    if let url = URL(string: "https://github.com/jozeta/Lada-desktop-mac") { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .help("github.com/jozeta/Lada-desktop-mac")
                Button {
                    if let url = URL(string: "https://github.com/apple/container") { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Apple container", systemImage: "shippingbox")
                }
                .help("github.com/apple/container")
            }
            .controlSize(.small)

            NordicSectionHeader("Licences")
            VStack(alignment: .leading, spacing: 6) {
                Text("Låda is released under the MIT License. Copyright © 2026 Låda Contributors.")
                Text("Apple's `container` runtime is a separate project under the Apache License 2.0; Låda runs it but doesn't include it.")
            }
            .font(.system(size: 12))
            .foregroundStyle(NordicTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(NordicTheme.secondaryText)
            Text(value).font(NordicTheme.monoFontRegular).textSelection(.enabled)
        }
    }
}
