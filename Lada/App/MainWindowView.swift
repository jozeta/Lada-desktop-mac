import SwiftUI
import AppKit

public struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @FocusState private var isSearchFocused: Bool
    @State private var isDockerfileDropTargeted: Bool = false

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
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NordicTheme.elevatedSurface)
            )
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
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        _ = appState.handleDroppedDockerfile(url: url)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
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

            List(selection: $appState.selectedSection) {
                Section("Workloads") {
                    sidebarRow(for: .overview, icon: .overview, badge: nil)
                    sidebarRow(for: .containers, icon: .containers, badge: appState.containers.count)
                    sidebarRow(for: .stacks, icon: .stacks, badge: ComposeStackTemplate.allTemplates.count)
                    sidebarRow(for: .images, icon: .images, badge: appState.images.count)
                    sidebarRow(for: .imageLibrary, icon: .imageLibrary, badge: DockerHubService.curatedCatalog.count)
                    sidebarRow(for: .dockerfileEditor, icon: .dockerfileEditor, badge: nil)
                    sidebarRow(for: .builds, icon: .builds, badge: appState.buildHistory.isEmpty ? nil : appState.buildHistory.count)
                }

                Section("Infrastructure") {
                    sidebarRow(for: .networks, icon: .networks, badge: appState.networks.count)
                    sidebarRow(for: .volumes, icon: .volumes, badge: appState.volumes.count)
                    sidebarRow(for: .machines, icon: .machines, badge: appState.machines.count)
                    sidebarRow(for: .registries, icon: .registries, badge: appState.registries.count)
                }

                Section("System") {
                    sidebarRow(for: .activity, icon: .activity, badge: appState.activityEvents.isEmpty ? nil : appState.activityEvents.count)
                    sidebarRow(for: .settings, icon: .settings, badge: nil)
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(AccessibilityID.sidebar)

            Divider().overlay(NordicTheme.borderSubtle)

            sidebarFooter
        }
        .background(NordicTheme.sidebarBackground)
    }

    private func sidebarRow(for section: NavigationSection, icon: LadaIconKind, badge: Int?) -> some View {
        let isSelected = appState.selectedSection == section
        return NavigationLink(value: section) {
            HStack(spacing: 10) {
                LadaIcon(icon, size: 16)
                    .foregroundStyle(
                        isSelected
                            ? NordicTheme.accent(for: appState.preferences.accentThemeChoice)
                            : NordicTheme.secondaryText
                    )
                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
                if let badge {
                    Text(verbatim: "\(badge)")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(isSelected ? NordicTheme.primaryText : NordicTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? Color.primary.opacity(0.16)
                                    : Color.primary.opacity(0.08)
                            )
                        )
                }
            }
        }
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
        case .builds:
            BuildsView(appState: appState)
        case .networks:
            NetworksView(appState: appState)
        case .volumes:
            VolumesView(appState: appState)
        case .machines:
            MachinesView(appState: appState)
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
                    .foregroundStyle(NordicTheme.secondaryText)
                TextField("Filter resources…", text: $appState.globalSearchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 190)
                    .focused($isSearchFocused)
                    .accessibilityIdentifier(AccessibilityID.globalSearchField)
                if !appState.globalSearchQuery.isEmpty {
                    Button {
                        appState.globalSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(NordicTheme.elevatedSurface)
            )
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.createContainerInitialRequest = nil
                appState.showCreateContainerSheet = true
            } label: {
                Label("New Container", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("Create or Run Container (⌘N)")
            .accessibilityIdentifier(AccessibilityID.newContainerButton)

            Button {
                appState.selectedSection = .images
                appState.showPullImageSheet = true
            } label: {
                Label("Pull Image", systemImage: "arrow.down.to.line")
            }
            .help("Pull OCI Image (⇧⌘N)")
            .accessibilityIdentifier(AccessibilityID.pullImageButton)

            Button {
                appState.selectedSection = .builds
            } label: {
                Label("Build Image", systemImage: "hammer")
            }
            .help("Open Build Studio")
            .accessibilityIdentifier(AccessibilityID.buildImageButton)

            Button {
                Task { await appState.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh Runtime State (⌘R)")
            .accessibilityIdentifier(AccessibilityID.refreshButton)

            Button {
                appState.selectedSection = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings (⌘,)")
        }
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

    func updateNSView(_ nsView: PassthroughHelperNSView, context: Context) {
        nsView.configureWindowSubviews()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            nsView.configureWindowSubviews()
        }
    }

    final class PassthroughHelperNSView: NSView {
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

