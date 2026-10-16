import AppKit
import SwiftUI

public struct ActivityView: View {
    @ObservedObject var appState: AppState
    @State private var selectedCategory = "All"

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredEvents: [ActivityEvent] {
        let query = appState.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.activityEvents.filter { ev in
            let matchesCat = selectedCategory == "All" || ev.category.lowercased().contains(selectedCategory.lowercased())
            let matchesQuery = query.isEmpty
                || ev.title.lowercased().contains(query)
                || ev.detail.lowercased().contains(query)
                || (ev.redactedCommand?.lowercased().contains(query) ?? false)
            return matchesCat && matchesQuery
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
            .background(NordicTheme.elevatedSurface)
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
            }
        }
        .background(NordicTheme.windowBackground)
    }
}

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var prefs: AppPreferences
    @State private var selectedTab = "runtime"
    @State private var systemLogsText = ""
    @State private var diagnosticSummaryCopied = false

    public init(appState: AppState) {
        self.appState = appState
        self.prefs = appState.preferences
    }

    public var body: some View {
        HSplitView {
            List(selection: $selectedTab) {
                Label("General", systemImage: "gearshape").tag("general")
                Label("System & Runtime", systemImage: "cpu").tag("runtime")
                Label("Resources & DNS", systemImage: "memorychip").tag("resources")
                Label("Registries", systemImage: "key").tag("registries")
                Label("Appearance", systemImage: "paintbrush").tag("appearance")
                Label("Notifications", systemImage: "bell").tag("notifications")
                Label("Diagnostics", systemImage: "stethoscope").tag("diagnostics")
                Label("Advanced", systemImage: "wrench.and.screwdriver").tag("advanced")
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 230)

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
                    default:
                        runtimeSection
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NordicTheme.windowBackground)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NordicSectionHeader("General Preferences", subtitle: "Startup landing section, refresh interval, and confirmation prompts")
            Form {
                Picker("Default Landing Screen", selection: $prefs.defaultLandingSectionRaw) {
                    ForEach(NavigationSection.allCases) { sec in
                        Text(sec.rawValue).tag(sec.rawValue)
                    }
                }
                Stepper(value: $prefs.autoRefreshIntervalSeconds, in: 5...120, step: 5) {
                    Text(verbatim: "Auto-Refresh Interval: \(prefs.autoRefreshIntervalSeconds)s")
                }
                Toggle("Confirm Destructive Actions (Delete / Prune)", isOn: $prefs.confirmDestructiveActions)
                Toggle("Confirm Before Stopping Running Containers", isOn: $prefs.confirmStopContainer)
            }
            .formStyle(.grouped)
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader(
                "System & Runtime Dependency Management",
                subtitle: "Inspect, start/stop, verify, and repair Apple's official `container` runtime"
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
            .background(NordicTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                NordicSectionHeader("Prerequisite Verification Summary")
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
            .background(NordicTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
        }
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader(
                "Default Container Resources & Runtime Properties",
                subtitle: "Configure default CPU/RAM allocations and inspect `container system property list`"
            )

            Form {
                Stepper(value: $prefs.defaultContainerCPUs, in: 1...32) {
                    Text(verbatim: "Default Container CPUs: \(prefs.defaultContainerCPUs) cores")
                }
                Picker("Default Container Memory", selection: $prefs.defaultContainerMemoryMB) {
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("8 GB").tag(8192)
                }
                Stepper(value: $prefs.defaultBuildCPUs, in: 1...32) {
                    Text(verbatim: "Default BuildKit CPUs: \(prefs.defaultBuildCPUs) cores")
                }
                Picker("Default BuildKit Memory", selection: $prefs.defaultBuildMemoryMB) {
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("4 GB").tag(4096)
                    Text("8 GB").tag(8192)
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 8) {
                NordicSectionHeader("Runtime System Properties (`container system property list`)")
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
            .background(NordicTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Technical Nordic Appearance", subtitle: "Theme, accent color, and table density")
            Form {
                Picker("Theme Mode", selection: $prefs.appearanceModeRaw) {
                    ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Picker("Accent Palette", selection: $prefs.accentThemeChoiceRaw) {
                    ForEach(AccentThemeChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
                Picker("Interface Density", selection: $prefs.uiDensityModeRaw) {
                    ForEach(UIDensityMode.allCases, id: \.rawValue) { density in
                        Text(density.displayName).tag(density.rawValue)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader("Notifications & Alerts")
            Form {
                Toggle("Notify on Build Completion", isOn: $prefs.notifyBuildCompletion)
                Toggle("Notify on Container Operations Failure", isOn: $prefs.notifyContainerFailures)
                Toggle("Notify on Runtime Health Degradation", isOn: $prefs.notifyRuntimeFailures)
            }
            .formStyle(.grouped)
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NordicSectionHeader(
                "Diagnostics & Redacted Support Bundle",
                subtitle: "Inspect system logs and export privacy-redacted diagnostic reports"
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
            NordicSectionHeader("Advanced Runtime Overrides")
            Form {
                TextField("Custom `container` CLI Path Override (leave blank for automatic discovery)", text: $prefs.customCLIExecutablePath)
                    .font(NordicTheme.monoFontRegular)
                Toggle("Enable Experimental Path Masking Options (`--masked-path`, `--read-only-path`)", isOn: $prefs.enableExperimentalPathMasking)
                Toggle("Enable Verbose Developer Command Logging", isOn: $prefs.enableDeveloperLogging)
                Toggle("Enable Simulation Mode When `container` CLI Is Not Installed", isOn: $prefs.useSimulationWhenCLIMissing)
                    .onChange(of: prefs.useSimulationWhenCLIMissing) { _, _ in
                        Task { await appState.refreshAll() }
                    }
            }
            .formStyle(.grouped)
        }
    }
}
