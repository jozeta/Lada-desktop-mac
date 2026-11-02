import SwiftUI

public struct ContainersView: View {
    @ObservedObject var appState: AppState

    @State private var stateFilter: StateFilter = .all
    @State private var sortOrder: [KeyPathComparator<ContainerListRow>] = [
        .init(\.sortName, order: .forward)
    ]
    @State private var containerPendingDeletion: ContainerModel? = nil
    @State private var confirmPruneStopped: Bool = false

    // MARK: - Stack group cells

    private func stackNameCell(_ stack: ContainerStackGroup) -> some View {
        HStack(spacing: 7) {
            LadaIcon(.stacks, size: 14)
                .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            Text(stack.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NordicTheme.primaryText)
                .help("Stack \(stack.name)")
        }
    }

    private func stackStatusCell(_ stack: ContainerStackGroup) -> some View {
        NordicStatusBadge(
            label: "\(stack.runningCount)/\(stack.members.count) running",
            tone: stack.runningCount == stack.members.count ? .positive : (stack.runningCount > 0 ? .warning : .neutral)
        )
    }

    private func stackImageCell(_ stack: ContainerStackGroup) -> some View {
        Text("\(stack.members.count) container\(stack.members.count == 1 ? "" : "s")")
            .font(.system(size: 12))
            .foregroundStyle(NordicTheme.secondaryText)
    }

    private func stackPortsCell(_ stack: ContainerStackGroup) -> some View {
        let ports = stack.members.flatMap { $0.configuration.publishedPorts.map { "\($0.hostPort)" } }
        return Text(ports.isEmpty ? "—" : ports.joined(separator: ", "))
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(NordicTheme.secondaryText)
            .lineLimit(1)
    }

    private func stackActionsCell(_ stack: ContainerStackGroup) -> some View {
        HStack(spacing: 6) {
            if stack.runningCount > 0 {
                Button {
                    Task { await StackGroupSummaryView.stopAll(stack, appState: appState) }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("Stop every container in this stack")
            }
            if stack.runningCount < stack.members.count {
                Button {
                    Task { await StackGroupSummaryView.startAll(stack, appState: appState) }
                } label: {
                    Image(systemName: "play.fill").foregroundStyle(NordicTheme.statusGreen)
                }
                .buttonStyle(.borderless)
                .help("Start every container in this stack")
            }
        }
    }

    public enum StateFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
        case createdOrExited = "Created / Exited"
        case unknown = "Unknown"

        public var id: String { rawValue }
    }

    /// "Unknown" is only offered while some container is actually in that state.
    private var visibleFilters: [StateFilter] {
        StateFilter.allCases.filter { $0 != .unknown || stateFilter == .unknown || appState.containers.contains { $0.state == .unknown } }
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
    }

    /// Stack members grouped under their stack (by the `com.lada.compose.project` label Låda sets
    /// when it starts a stack); everything else as single rows. Groups and members are sorted.
    private var listRows: [ContainerListRow] {
        var groups: [String: [ContainerModel]] = [:]
        var singles: [ContainerListRow] = []
        for c in filteredContainers {
            if let stack = c.composeProject {
                groups[stack, default: []].append(c)
            } else {
                singles.append(.container(c))
            }
        }
        let stackRows = groups.map { name, members in
            ContainerListRow.stack(ContainerStackGroup(
                name: name,
                members: members.map(ContainerListRow.container).sorted(using: sortOrder).compactMap(\.container)
            ))
        }
        return (stackRows + singles).sorted(using: sortOrder)
    }

    private func isValidSelection(_ id: String?) -> Bool {
        guard let id else { return false }
        if id.hasPrefix(ContainerListRow.stackPrefix) {
            return listRows.contains { $0.id == id }
        }
        return filteredContainers.contains { $0.id == id }
    }

    private func expandedBinding(for stack: String) -> Binding<Bool> {
        Binding(
            get: { !appState.collapsedContainerStacks.contains(stack) },
            set: { expanded in
                if expanded { appState.collapsedContainerStacks.remove(stack) } else { appState.collapsedContainerStacks.insert(stack) }
            }
        )
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
                    // Segmented when it fits, a compact menu when the inspector narrows the table.
                    ViewThatFits(in: .horizontal) {
                        Picker("Filter", selection: $stateFilter) {
                            ForEach(visibleFilters) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()

                        Picker("Filter", selection: $stateFilter) {
                            ForEach(visibleFilters) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .layoutPriority(-1)

                    Spacer()

                    Button("Prune Stopped…") {
                        confirmPruneStopped = true
                    }
                    .controlSize(.small)
                    .fixedSize()
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
                .nordicBar()
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
                    Table(of: ContainerListRow.self, selection: $appState.selectedContainerID, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.sortName) { row in
                            switch row {
                            case .container(let container):
                            HStack(spacing: 7) {
                                LadaIcon(.containers, size: 14)
                                    .foregroundStyle(container.state == .running ? NordicTheme.statusGreen : NordicTheme.secondaryText)
                                // Inside a stack group, the service name (db, web…) reads better than
                                // the full container name, which stays in the tooltip.
                                Text(container.composeProject != nil ? (container.configuration.labels["com.lada.compose.service"] ?? container.id) : container.id)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NordicTheme.primaryText)
                                    .help(container.id)
                            }
                            case .stack(let stack):
                                stackNameCell(stack)
                            }
                        }
                        .width(min: 120, ideal: 150)

                        TableColumn("Status", value: \.sortState) { row in
                            switch row {
                            case .container(let container):
                            NordicStatusBadge(containerState: container.state)
                            case .stack(let stack):
                                stackStatusCell(stack)
                            }
                        }
                        .width(min: 90, ideal: 95)

                        TableColumn("Image", value: \.sortImage) { row in
                            switch row {
                            case .container(let container):
                            Text(container.shortImageReference)
                                .font(.system(size: 12))
                                .foregroundStyle(NordicTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(container.imageReference)
                            case .stack(let stack):
                                stackImageCell(stack)
                            }
                        }
                        .width(min: 110, ideal: 150)

                        TableColumn("Ports") { row in
                            switch row {
                            case .container(let container):
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
                                Text(container.configuration.publishedPorts.isEmpty ? "—" : container.configuration.publishedPorts.map { "\($0.hostPort) → \($0.containerPort)" }.joined(separator: ", "))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .lineLimit(1)
                                    .help(container.primaryIPv4.map { "IP \($0)" } ?? "")
                            }
                            case .stack(let stack):
                                stackPortsCell(stack)
                            }
                        }
                        .width(min: 90, ideal: 110)

                        TableColumn("Actions") { row in
                            switch row {
                            case .container(let container):
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
                            case .stack(let stack):
                                stackActionsCell(stack)
                            }
                        }
                        .width(88)
                    } rows: {
                        ForEach(listRows) { row in
                            if case .stack(let stack) = row {
                                DisclosureTableRow(row, isExpanded: expandedBinding(for: stack.name)) {
                                    ForEach(stack.members) { member in
                                        TableRow(ContainerListRow.container(member))
                                    }
                                }
                            } else {
                                TableRow(row)
                            }
                        }
                    }
                    // No striped filler rows below the last container: a calmer, flat list.
                    .alternatingRowBackgrounds(.disabled)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .accessibilityIdentifier(AccessibilityID.containerTable)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            // Right / Bottom: Contextual Container Detail Panel
            if let selected = selectedContainer {
                ContainerDetailView(appState: appState, container: selected)
                    .frame(minWidth: 460, idealWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            } else if let id = appState.selectedContainerID, id.hasPrefix(ContainerListRow.stackPrefix),
                      case .stack(let group)? = listRows.first(where: { $0.id == id }) {
                StackGroupSummaryView(appState: appState, group: group)
                    .frame(minWidth: 460, idealWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .containers,
                    title: "Select a Container",
                    description: "Pick a container to see its details, logs, terminal, files and network."
                )
                .frame(minWidth: 440, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .onAppear {
            if !isValidSelection(appState.selectedContainerID) {
                appState.selectedContainerID = listRows.first?.id
            }
        }
        .onChange(of: appState.containers.count) { _, _ in
            if !isValidSelection(appState.selectedContainerID) {
                appState.selectedContainerID = listRows.first?.id
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
