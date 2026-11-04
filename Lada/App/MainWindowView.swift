import SwiftUI
import AppKit

public struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @FocusState private var isSearchFocused: Bool
    @State private var isDockerfileDropTargeted: Bool = false
    @StateObject private var search = UniversalSearchPanel()
    @State private var searchAnchor = ScreenAnchor()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack {
            NavigationSplitView {
                sidebarView
                    .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 260)
                    .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isDockerfileDropTargeted) { providers in
                        handleWindowDrop(providers: providers)
                    }
            } detail: {
                VStack(spacing: 0) {
                    if let error = appState.activeError {
                        NordicErrorBanner(
                            error: error,
                            onRetry: error.isRetryable ? { Task { await appState.refreshAll() } } : nil,
                            onDismiss: { appState.activeError = nil }
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    if let statusMessage = appState.statusFeedbackMessage {
                        statusFeedbackBanner(message: statusMessage)
                    }
                    if appState.preferences.useSimulationWhenCLIMissing && !appState.installation.isInstalled {
                        simulationBanner
                    }
                    contentDetailView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // One backdrop behind every section, so glass panels frost the same tint everywhere.
                .nordicPageBackground()
                .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isDockerfileDropTargeted) { providers in
                    handleWindowDrop(providers: providers)
                }
            }

            WindowDropPassthroughConfiguringView(
                selectedSection: appState.selectedSection,
                isTargeted: $isDockerfileDropTargeted,
                onFileURLDrop: { url in
                    _ = appState.handleDroppedDockerfile(url: url)
                }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            if isDockerfileDropTargeted {
                dockerfileDropOverlay
            }
        }
        .toolbar {
            globalToolbarContent
        }
        .sheet(isPresented: $appState.showSetupWizard) {
            SetupWizardView(appState: appState)
        }
        .sheet(isPresented: $appState.showCreateContainerSheet) {
            CreateContainerWizardView(
                appState: appState,
                initialRequest: appState.createContainerInitialRequest
            )
            .id(appState.createContainerInitialRequest?.name ?? "default-create-sheet")
        }
        .preferredColorScheme(appState.preferences.appearanceMode.colorScheme)
        .nordicDensity(appState.preferences.uiDensityMode)
        .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
        .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isDockerfileDropTargeted) { providers in
            handleWindowDrop(providers: providers)
        }
        .task {
            await appState.performInitialBootstrap()
        }
    }

    private func statusFeedbackBanner(message: String) -> some View {
        HStack(spacing: 10) {
            if !appState.startingContainerIDs.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NordicTheme.statusGreen)
            }
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NordicTheme.primaryText)
            Spacer()
            Button {
                appState.statusFeedbackMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(NordicTheme.accent(for: appState.preferences.accentThemeChoice).opacity(0.14))
    }

    private var dockerfileDropOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                Text("Drop Dockerfile or docker-compose.yml to Deploy")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(NordicTheme.primaryText)
                Text("Låda will parse Dockerfiles or multi-container Compose stacks and open the pre-populated deployment workspace.")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        NordicTheme.accent(for: appState.preferences.accentThemeChoice),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
            )
            .shadow(radius: 20)
        }
        .allowsHitTesting(false)
    }

    private func handleWindowDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        _ = appState.handleDroppedDockerfile(url: url)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { @Sendable item, _ in
                    guard let str = item as? String else { return }
                    Task { @MainActor in
                        appState.handleDroppedDockerfileText(str)
                    }
                }
                return true
            }
        }
        return false
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LadaIcon(.appIdentity, size: 22)
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Låda")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text("Apple Container Studio")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Nordic navigation (same style as Settings) instead of the system's translucent
            // sidebar list. Badges only count live resources.
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    sidebarGroup("Workloads")
                    sidebarRow(for: .overview, icon: .overview, badge: nil)
                    sidebarRow(for: .containers, icon: .containers, badge: containerBadge)
                    sidebarRow(for: .stacks, icon: .stacks, badge: nil)
                    sidebarRow(for: .images, icon: .images, badge: appState.images.isEmpty ? nil : "\(appState.images.count)")
                    sidebarRow(for: .imageLibrary, icon: .imageLibrary, badge: nil)
                    sidebarRow(for: .dockerfileEditor, icon: .dockerfileEditor, badge: nil)

                    sidebarGroup("Infrastructure")
                    sidebarRow(for: .networks, icon: .networks, badge: appState.networks.isEmpty ? nil : "\(appState.networks.count)")
                    sidebarRow(for: .volumes, icon: .volumes, badge: appState.volumes.isEmpty ? nil : "\(appState.volumes.count)")
                    sidebarRow(for: .machines, icon: .machines, badge: appState.machines.isEmpty ? nil : "\(appState.machines.count)")
                    sidebarRow(for: .nodeGraph, icon: .nodeGraph, badge: nil)
                    sidebarRow(for: .registries, icon: .registries, badge: appState.registries.isEmpty ? nil : "\(appState.registries.count)")

                    sidebarGroup("System")
                    sidebarRow(for: .activity, icon: .activity, badge: nil)
                    sidebarRow(for: .settings, icon: .settings, badge: nil)
                }
                .padding(.horizontal, NordicTheme.Spacing.s)
                .padding(.bottom, NordicTheme.Spacing.m)
            }
            .accessibilityIdentifier(AccessibilityID.sidebar)

            Divider().overlay(NordicTheme.borderSubtle)

            sidebarFooter
        }
        .background(NordicSidebarMaterial().ignoresSafeArea())
    }

    /// Running / total, the number that matters at a glance.
    private var containerBadge: String? {
        guard !appState.containers.isEmpty else { return nil }
        let running = appState.containers.filter { $0.state == .running }.count
        return "\(running)/\(appState.containers.count)"
    }

    private func sidebarGroup(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(NordicTheme.secondaryText.opacity(0.8))
            .padding(.horizontal, NordicTheme.Spacing.s + 2)
            .padding(.top, NordicTheme.Spacing.l)
            .padding(.bottom, NordicTheme.Spacing.xs)
    }

    private func sidebarRow(for section: NavigationSection, icon: LadaIconKind, badge: String?) -> some View {
        SidebarNavRow(
            title: section.rawValue,
            icon: icon,
            badge: badge,
            isSelected: appState.selectedSection == section,
            accent: NordicTheme.accent(for: appState.preferences.accentThemeChoice)
        ) {
            appState.selectedSection = section
        }
        .accessibilityIdentifier("lada.sidebar.\(section.id)")
    }

    private var sidebarFooter: some View {
        Button {
            appState.showSetupWizard = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(runtimeDotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Runtime: \(appState.systemStatus.state.displayTitle)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text(appState.installation.cliVersion.map { "container v\($0.description)" } ?? "CLI Not Installed")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.runtimeStatusBadge)
    }

    private var runtimeDotColor: Color {
        switch appState.systemStatus.state {
        case .running:
            return NordicTheme.statusGreen
        case .starting, .stopping:
            return NordicTheme.statusAmber
        case .stopped, .unregistered:
            return NordicTheme.secondaryText
        case .missingCLI, .error:
            return NordicTheme.statusRed
        }
    }

    @ViewBuilder
    private var contentDetailView: some View {
        switch appState.selectedSection {
        case .overview:
            DashboardView(appState: appState)
        case .containers:
            ContainersView(appState: appState)
        case .stacks:
            StacksView(appState: appState)
        case .images:
            ImagesView(appState: appState)
        case .imageLibrary:
            ImageLibraryView(appState: appState)
        case .dockerfileEditor:
            DockerfileEditorView(appState: appState)
        case .networks:
            NetworksView(appState: appState)
        case .volumes:
            VolumesView(appState: appState)
        case .machines:
            MachinesView(appState: appState)
        case .nodeGraph:
            NodeGraphView(appState: appState)
        case .registries:
            RegistriesView(appState: appState)
        case .activity:
            ActivityView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        }
    }

    @ToolbarContentBuilder
    private var globalToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(isSearchFocused ? NordicTheme.accent(for: appState.preferences.accentThemeChoice) : NordicTheme.secondaryText)
                TextField("Search everything…", text: $appState.globalSearchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 240)
                    .focused($isSearchFocused)
                    .onSubmit { search.openSelection() }
                    .onKeyPress(.downArrow) { search.moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { search.moveSelection(by: -1); return .handled }
                    .onKeyPress(.escape) { clearSearch(); return .handled }
                    .accessibilityIdentifier(AccessibilityID.globalSearchField)
                    .help("Search containers, stacks, images, machines, volumes, networks, registries, Image Library presets and pages")
                if !appState.globalSearchQuery.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .nordicChip()
            .background(ScreenAnchorReader(anchor: searchAnchor))
            .onChange(of: appState.globalSearchQuery) { _, query in updateSearch(query) }
            .onChange(of: isSearchFocused) { _, focused in
                if focused {
                    updateSearch(appState.globalSearchQuery)
                } else {
                    // Let a click on a result land before the list closes.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        if !isSearchFocused { search.hide() }
                    }
                }
            }
            .onAppear {
                search.onOpen = { result in
                    appState.open(result.destination)
                    appState.globalSearchQuery = ""
                    isSearchFocused = false
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.userRefresh() }
            } label: {
                if appState.isUserRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(appState.isUserRefreshing)
            .help("Refresh everything, including the open page's logs and files (⌘R)")
            .accessibilityIdentifier(AccessibilityID.refreshButton)

            Button {
                appState.selectedSection = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings (⌘,)")
        }
    }

    private func updateSearch(_ query: String) {
        guard isSearchFocused || !query.isEmpty else { search.hide(); return }
        search.update(query: query, inputs: appState.searchInputs, anchor: searchAnchor)
    }

    private func clearSearch() {
        appState.globalSearchQuery = ""
        search.hide()
    }

    private var simulationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(NordicTheme.statusAmber)
            Text("Simulation Mode Active: Apple's `container` CLI is not installed on this Mac. Showing simulated runtime data.")
                .font(.system(size: 12))
            Spacer()
            Button("Install Official Runtime…") {
                appState.showSetupWizard = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(NordicTheme.statusAmber.opacity(0.14))
    }
}

/// Ensures AppKit `NSTableView` (`Table`) and `NSOutlineView` (`List`) subviews inside the window do not swallow Finder file drag events, allowing `.onDrop` to accept Dockerfiles anywhere in the window.
private struct WindowDropPassthroughConfiguringView: NSViewRepresentable {
    var selectedSection: NavigationSection
    @Binding var isTargeted: Bool
    var onFileURLDrop: (URL) -> Void

    func makeNSView(context: Context) -> PassthroughHelperNSView {
        let view = PassthroughHelperNSView()
        view.configureWindowSubviews()
        return view
    }

    /// Runs on every window re-render, so it only walks the view tree when the section (and so
    /// its tables) changed; walking it on every poll was a measurable share of idle CPU.
    func updateNSView(_ nsView: PassthroughHelperNSView, context: Context) {
        guard nsView.lastConfiguredSection != selectedSection else { return }
        nsView.lastConfiguredSection = selectedSection
        nsView.configureWindowSubviews()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            nsView.configureWindowSubviews()
        }
    }

    final class PassthroughHelperNSView: NSView {
        var lastConfiguredSection: NavigationSection?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindowSubviews()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.configureWindowSubviews()
            }
        }

        func configureWindowSubviews() {
            guard let rootView = window?.contentView else { return }
            unregisterBlockingDragDestinations(in: rootView)
        }

        private func unregisterBlockingDragDestinations(in view: NSView) {
            if view is NSTableView || view is NSOutlineView {
                view.unregisterDraggedTypes()
            }
            for subview in view.subviews {
                unregisterBlockingDragDestinations(in: subview)
            }
        }
    }
}

/// One sidebar destination: custom icon, title and an optional count, with an accent pill that
/// slides between rows (matched geometry) and a soft hover state.
private struct SidebarNavRow: View {
    let title: String
    let icon: LadaIconKind
    let badge: String?
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.nordicDensity) private var density

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LadaIcon(icon, size: 15)
                    .foregroundStyle(isSelected ? accent : NordicTheme.secondaryText)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(NordicTheme.primaryText)
                Spacer(minLength: 4)
                if let badge {
                    Text(verbatim: badge)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? accent : NordicTheme.secondaryText)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, density == .compact ? 3.5 : 6.5)
            .background(
                RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : (hovered ? NordicTheme.borderSubtle.opacity(0.55) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(NordicTheme.Motion.quick, value: hovered)
        .animation(NordicTheme.Motion.quick, value: isSelected)
        .animation(NordicTheme.Motion.data, value: badge)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
