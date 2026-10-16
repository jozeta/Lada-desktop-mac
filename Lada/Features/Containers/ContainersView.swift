import SwiftUI

public struct ContainersView: View {
    @ObservedObject var appState: AppState

    @State private var stateFilter: StateFilter = .all
    @State private var sortOrder: [KeyPathComparator<ContainerModel>] = [
        .init(\.id, order: .forward)
    ]
    @State private var containerPendingDeletion: ContainerModel? = nil
    @State private var confirmPruneStopped: Bool = false

    public enum StateFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
        case createdOrExited = "Created / Exited"
        case unknown = "Unknown"

        public var id: String { rawValue }
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredContainers: [ContainerModel] {
        let query = appState.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.containers
            .filter { c in
                switch stateFilter {
                case .all: break
                case .running: if c.state != .running { return false }
                case .stopped: if c.state != .stopped && c.state != .stopping { return false }
                case .createdOrExited: if c.state != .created && c.state != .exited { return false }
                case .unknown: if c.state != .unknown { return false }
                }
                if !query.isEmpty {
                    return c.id.lowercased().contains(query)
                        || c.imageReference.lowercased().contains(query)
                        || (c.primaryIPv4?.lowercased().contains(query) ?? false)
                }
                return true
            }
            .sorted(using: sortOrder)
    }

    private var selectedContainer: ContainerModel? {
        guard let id = appState.selectedContainerID else { return nil }
        return appState.containers.first { $0.id == id }
    }

    public var body: some View {
        HSplitView {
            // Left / Top: Container Table
            VStack(spacing: 0) {
                // Filter & Action Bar
                HStack(spacing: 10) {
                    Picker("Filter", selection: $stateFilter) {
                        ForEach(StateFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 380)

                    Spacer()

                    Button("Prune Stopped…") {
                        confirmPruneStopped = true
                    }
                    .controlSize(.small)
                    .disabled(!appState.containers.contains { $0.state != .running })

                    Button {
                        appState.createContainerInitialRequest = nil
                        appState.showCreateContainerSheet = true
                    } label: {
                        Label("New Container…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(NordicTheme.elevatedSurface)
                .overlay(alignment: .bottom) {
                    Divider().overlay(NordicTheme.borderSubtle)
                }

                if filteredContainers.isEmpty {
                    NordicEmptyState(
                        icon: .containers,
                        title: appState.containers.isEmpty ? "No Containers Found" : "No Matching Containers",
                        description: appState.containers.isEmpty
                            ? "Create and run a Linux container from any OCI-compatible image."
                            : "Adjust the status filter or search query to see containers.",
                        primaryActionTitle: "Create Container…",
                        onPrimaryAction: {
                            appState.createContainerInitialRequest = nil
                            appState.showCreateContainerSheet = true
                        }
                    )
                } else {
                    Table(filteredContainers, selection: $appState.selectedContainerID, sortOrder: $sortOrder) {
                        TableColumn("Name / ID", value: \.id) { container in
                            HStack(spacing: 7) {
                                LadaIcon(.containers, size: 14)
                                    .foregroundStyle(container.state == .running ? NordicTheme.statusGreen : NordicTheme.secondaryText)
                                Text(container.id)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NordicTheme.primaryText)
                            }
                        }
                        .width(min: 130, ideal: 160)

                        TableColumn("Status", value: \.rawState) { container in
                            NordicStatusBadge(containerState: container.state)
                        }
                        .width(min: 95, ideal: 105)

                        TableColumn("Image", value: \.imageReference) { container in
                            Text(container.imageReference)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .width(min: 140, ideal: 200)

                        TableColumn("IP / Ports") { container in
                            HStack(spacing: 5) {
                                if container.state == .running, let firstPort = container.configuration.publishedPorts.first {
                                    let probe = appState.portHealthMap[firstPort.hostPort]
                                    Circle()
                                        .fill(
                                            (probe?.state == .healthyHTTP || probe?.state == .listeningTCP)
                                                ? NordicTheme.statusGreen
                                                : NordicTheme.statusAmber
                                        )
                                        .frame(width: 6, height: 6)
                                        .help(probe?.tooltipDescription ?? "Port \(firstPort.hostPort)")
                                }
                                Text([container.primaryIPv4, container.portsSummary == "—" ? nil : container.portsSummary].compactMap { $0 }.joined(separator: " • "))
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .width(min: 115, ideal: 155)

                        TableColumn("Resources") { container in
                            Text("\(container.configuration.cpus)c / \(container.memoryFormatted) (\(container.configuration.arch))")
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        .width(min: 100, ideal: 130)

                        TableColumn("Actions") { container in
                            HStack(spacing: 6) {
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
                                    Image(systemName: "apple.terminal")
                                        .foregroundStyle(container.state == .running ? NordicTheme.accent(for: appState.preferences.accentThemeChoice) : NordicTheme.secondaryText)
                                }
                                .buttonStyle(.borderless)
                                .help(container.state == .running ? "Open Real Terminal Connected to Container" : "Start & Open Terminal")

                                if container.state == .running {
                                    Button {
                                        Task {
                                            await appState.performOperation(
                                                category: "Containers",
                                                title: "Stop \(container.id)",
                                                redactedCommand: "container stop \(container.id)"
                                            ) {
                                                try await appState.runtimeService.stopContainer(id: container.id, timeoutSeconds: 5)
                                                return "Stopped '\(container.id)'."
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "stop.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Stop Container")
                                } else {
                                    if appState.startingContainerIDs.contains(container.id) {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Button {
                                            Task {
                                                await appState.startContainerWithVerification(id: container.id)
                                            }
                                        } label: {
                                            Image(systemName: "play.fill")
                                                .foregroundStyle(NordicTheme.statusGreen)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Start Container")
                                    }
                                }

                                Button {
                                    containerPendingDeletion = container
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(NordicTheme.statusRed)
                                }
                                .buttonStyle(.borderless)
                                .help("Delete Container")
                            }
                        }
                        .width(88)
                    }
                    .accessibilityIdentifier(AccessibilityID.containerTable)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            // Right / Bottom: Contextual Container Detail Panel
            if let selected = selectedContainer {
                ContainerDetailView(appState: appState, container: selected)
                    .frame(minWidth: 460, idealWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .containers,
                    title: "Select a Container",
                    description: "Choose a container from the list to inspect its overview, live logs, interactive PTY terminal, networking, mounts, and environment."
                )
                .frame(minWidth: 440, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(NordicTheme.contentSurface)
            }
        }
        .onAppear {
            if appState.selectedContainerID == nil || !filteredContainers.contains(where: { $0.id == appState.selectedContainerID }) {
                appState.selectedContainerID = filteredContainers.first?.id
            }
        }
        .onChange(of: appState.containers.count) { _, _ in
            if appState.selectedContainerID == nil || !filteredContainers.contains(where: { $0.id == appState.selectedContainerID }) {
                appState.selectedContainerID = filteredContainers.first?.id
            }
        }
        .confirmationDialog(
            "Delete Container '\(containerPendingDeletion?.id ?? "")'?",
            isPresented: Binding(
                get: { containerPendingDeletion != nil },
                set: { if !$0 { containerPendingDeletion = nil } }
            ),
            presenting: containerPendingDeletion
        ) { target in
            Button(target.state == .running ? "Force Delete Running Container" : "Delete Container", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Containers",
                        title: "Delete Container \(target.id)",
                        redactedCommand: "container delete \(target.state == .running ? "--force " : "")\(target.id)"
                    ) {
                        try await appState.runtimeService.deleteContainer(id: target.id, force: target.state == .running)
                        return "Deleted container '\(target.id)'."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Deleting '\(target.id)' removes its container rootfs disk image. Host bind mounts and named volumes will not be deleted.")
        }
        .confirmationDialog(
            "Prune All Stopped Containers?",
            isPresented: $confirmPruneStopped
        ) {
            Button("Prune Stopped Containers", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Containers",
                        title: "Prune Stopped Containers",
                        redactedCommand: "container prune"
                    ) {
                        try await appState.runtimeService.pruneContainers()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs `container prune` and permanently deletes all stopped containers to reclaim disk space.")
        }
    }
}
