import SwiftUI

public struct NetworksView: View {
    @ObservedObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var networkPendingDeletion: NetworkModel?
    @State private var confirmPruneUnused = false

    @State private var createName = ""
    @State private var createIPv4Subnet = ""
    @State private var createIPv6Subnet = ""
    @State private var createInternal = false
    @State private var createLabels: [KeyValueEntry] = []

    public init(appState: AppState) {
        self.appState = appState
    }

    private func containersAttached(to network: NetworkModel) -> [ContainerModel] {
        appState.containers.filter { container in
            container.networks.contains(where: { $0.network == network.name })
                || container.configuration.configuredNetworks.contains(network.name)
        }
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                headerBar
                if appState.networks.isEmpty {
                    NordicEmptyState(
                        icon: .networks,
                        title: "No Container Networks",
                        description: "Create isolated vmnet bridge networks with custom IPv4/IPv6 CIDR subnets and container-to-container DNS resolution.",
                        primaryActionTitle: "Create Network",
                        onPrimaryAction: { showCreateSheet = true }
                    )
                } else {
                    networkTable
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

            if let selectedId = appState.selectedNetworkID,
               let network = appState.networks.first(where: { $0.id == selectedId }) {
                networkInspector(for: network)
                    .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .networks,
                    title: "Select a Network",
                    description: "Choose a network from the list to inspect its IPv4/IPv6 CIDR subnets, gateway, plugin, and attached containers."
                )
                .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .onAppear {
            if appState.selectedNetworkID == nil || !appState.networks.contains(where: { $0.id == appState.selectedNetworkID }) {
                appState.selectedNetworkID = appState.networks.first?.id
            }
        }
        .onChange(of: appState.networks.count) { _, _ in
            if appState.selectedNetworkID == nil || !appState.networks.contains(where: { $0.id == appState.selectedNetworkID }) {
                appState.selectedNetworkID = appState.networks.first?.id
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createNetworkSheet
        }
        .confirmationDialog(
            "Delete Network '\(networkPendingDeletion?.name ?? "")'?",
            isPresented: Binding(
                get: { networkPendingDeletion != nil },
                set: { if !$0 { networkPendingDeletion = nil } }
            ),
            presenting: networkPendingDeletion
        ) { target in
            let attached = containersAttached(to: target)
            if attached.isEmpty && !target.isBuiltin {
                Button("Delete Network", role: .destructive) {
                    Task {
                        await appState.performOperation(
                            category: "Networks",
                            title: "Delete Network \(target.name)",
                            redactedCommand: "container network delete \(target.name)"
                        ) {
                            try await appState.runtimeService.deleteNetwork(name: target.name)
                            return "Deleted network '\(target.name)'."
                        }
                        if appState.selectedNetworkID == target.id {
                            appState.selectedNetworkID = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            let attached = containersAttached(to: target)
            if target.isBuiltin {
                Text("The builtin '\(target.name)' network cannot be deleted.")
            } else if !attached.isEmpty {
                Text("Cannot delete '\(target.name)' while \(attached.count) container(s) are attached (\(attached.map(\.id).joined(separator: ", "))). Stop or remove attached containers first.")
            } else {
                Text("Permanently remove the virtual network '\(target.name)' (\(target.ipv4Subnet))?")
            }
        }
        .confirmationDialog("Prune Unused Networks?", isPresented: $confirmPruneUnused) {
            Button("Prune Unused Networks", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Networks",
                        title: "Prune Unused Networks",
                        redactedCommand: "container network prune"
                    ) {
                        try await appState.runtimeService.pruneNetworks()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all user-defined networks with no connected containers. The builtin `default` network is preserved.")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text(verbatim: "Networks (\(appState.networks.count))")
                .font(NordicTheme.subtitleFont)
                .foregroundStyle(NordicTheme.primaryText)
            if !appState.capabilities.networkManagement.isEnabledByDefault {
                NordicStatusBadge(label: appState.capabilities.networkManagement.statusDescription, tone: .warning)
            }
            Spacer()
            Button {
                confirmPruneUnused = true
            } label: {
                Label("Prune Unused", systemImage: "sparkles")
            }
            .controlSize(.small)

            Button {
                createName = ""
                createIPv4Subnet = ""
                createIPv6Subnet = ""
                createInternal = false
                createLabels = []
                showCreateSheet = true
            } label: {
                Label("Create Network", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            .controlSize(.small)
            .disabled(!appState.capabilities.networkManagement.isEnabledByDefault && appState.installation.isInstalled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .nordicBar()
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var networkTable: some View {
        Table(appState.networks, selection: $appState.selectedNetworkID) {
            TableColumn("Name") { net in
                HStack(spacing: 8) {
                    LadaIcon(.networks, size: 14)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(net.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if net.isBuiltin {
                        NordicStatusBadge(label: "Builtin", tone: .neutral, showDot: false)
                    }
                }
            }
            .width(min: 155, ideal: 200)

            TableColumn("Mode") { net in
                Text(net.mode.uppercased())
                    .font(.system(size: 12).monospacedDigit())
            }
            .width(min: 70, ideal: 85)

            TableColumn("IPv4 Subnet") { net in
                Text(net.ipv4Subnet.isEmpty ? "—" : net.ipv4Subnet)
                    .font(.system(size: 12).monospacedDigit())
            }
            .width(min: 120, ideal: 145)

            TableColumn("IPv4 Gateway") { net in
                Text(net.ipv4Gateway.isEmpty ? "—" : net.ipv4Gateway)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 110, ideal: 135)

            TableColumn("Containers") { net in
                let count = containersAttached(to: net).count
                Text(verbatim: "\(count) attached")
                    .font(.system(size: 12))
                    .foregroundStyle(count > 0 ? NordicTheme.primaryText : NordicTheme.secondaryText)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Actions") { net in
                Button(role: .destructive) {
                    networkPendingDeletion = net
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(net.isBuiltin ? NordicTheme.secondaryText.opacity(0.4) : NordicTheme.statusRed)
                }
                .buttonStyle(.borderless)
                .disabled(net.isBuiltin)
                .help(net.isBuiltin ? "The default builtin network cannot be deleted." : "Delete network \(net.name)")
            }
            .width(min: 55, ideal: 65)
        }
        .nordicTransparentTable()
        .accessibilityIdentifier(AccessibilityID.networkTable)
    }

    private func networkInspector(for network: NetworkModel) -> some View {
        let attached = containersAttached(to: network)
        return VStack(spacing: 0) {
            NordicDetailHeader(
                title: network.name,
                subtitle: network.plugin,
                badge: NordicStatusBadge(label: network.mode.uppercased(), tone: .positive)
            ) {
                if !network.isBuiltin {
                    Button(role: .destructive) {
                        networkPendingDeletion = network
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Subnet & Routing", info: "The network's address range and gateway. Containers on it get an address from this subnet and can reach each other.")
                        LabeledContent("Mode", value: network.mode.uppercased())
                        LabeledContent("Plugin", value: network.plugin)
                            .font(NordicTheme.monoFontSmall)
                        LabeledContent("IPv4 CIDR", value: network.ipv4Subnet.isEmpty ? "Auto" : network.ipv4Subnet)
                            .font(NordicTheme.monoFontSmall)
                        LabeledContent("IPv4 Gateway", value: network.ipv4Gateway.isEmpty ? "Auto" : network.ipv4Gateway)
                            .font(NordicTheme.monoFontSmall)
                        LabeledContent("IPv6 CIDR", value: network.ipv6Subnet ?? "None")
                            .font(NordicTheme.monoFontSmall)
                        LabeledContent("Created", value: network.creationDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding(14)
                    .nordicSurface()

                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Attached Containers (\(attached.count))", info: "Containers currently connected to this network.")
                        if attached.isEmpty {
                            Text("No containers are currently attached to '\(network.name)'.")
                                .font(.system(size: 12))
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            ForEach(attached) { container in
                                HStack {
                                    NordicStatusBadge(containerState: container.state)
                                    Text(container.id)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    if let netInfo = container.networks.first(where: { $0.network == network.name }) {
                                        Text(verbatim: netInfo.ipv4Address)
                                            .font(NordicTheme.monoFontSmall)
                                            .foregroundStyle(NordicTheme.secondaryText)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .nordicSurface()
                }
                .padding(16)
            }
        }
        .background(Color.clear)
    }

    private var createNetworkSheet: some View {
        let req = NetworkCreateRequest(
            name: createName.trimmingCharacters(in: .whitespacesAndNewlines),
            ipv4Subnet: createIPv4Subnet.trimmingCharacters(in: .whitespacesAndNewlines),
            ipv6Subnet: createIPv6Subnet.trimmingCharacters(in: .whitespacesAndNewlines),
            isInternal: createInternal,
            labels: createLabels
        )
        let usedSubnets = appState.networks.map(\.ipv4Subnet).filter { !$0.isEmpty }
        return NordicSheet(
            icon: .networks,
            title: "Create Network",
            subtitle: "A private network for containers. Containers on the same network reach each other by name and address.",
            primaryTitle: "Create Network",
            problem: networkProblem(req, usedSubnets: usedSubnets),
            onCancel: { showCreateSheet = false },
            onPrimary: { createNetwork(req) }
        ) {
            NordicFormSection(title: "Network") {
                NordicFormField(title: "Name", hint: "Lowercase letters, digits, '.', '-' or '_'. Used with --network when running containers.",
                                info: "The network's name. Containers join it with `container run --network <name>`.") {
                    TextField("backend-net", text: $createName)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                        .accessibilityIdentifier("lada.networks.create.name")
                }
                NordicFormField(title: "IPv4 subnet", hint: "Optional. Leave empty and the runtime picks one.",
                                info: "The address range containers on this network get addresses from, in CIDR form (192.168.70.0/24 gives 254 addresses). It must not overlap another network's subnet.") {
                    HStack {
                        TextField("automatic", text: $createIPv4Subnet)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontRegular)
                        Button("Suggest a Free Subnet") {
                            createIPv4Subnet = SubnetSuggester.nextFree(avoiding: usedSubnets) ?? ""
                        }
                        .controlSize(.small)
                        .help("Pick the first 192.168.x.0/24 that no existing network uses")
                    }
                    if !usedSubnets.isEmpty {
                        HStack(spacing: 6) {
                            Text("In use:").font(.system(size: 11)).foregroundStyle(NordicTheme.secondaryText)
                            ForEach(usedSubnets, id: \.self) { subnet in
                                Text(subnet)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .nordicChip(cornerRadius: 4)
                            }
                        }
                    }
                }
                Toggle(isOn: $createInternal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Internal only").font(.system(size: 12.5, weight: .semibold))
                        Text("Containers can talk to each other but not to the internet or your Mac's network (--internal).")
                            .font(.system(size: 11)).foregroundStyle(NordicTheme.secondaryText)
                    }
                }
                .toggleStyle(.switch)
            }

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
                    NordicFormField(title: "IPv6 subnet", hint: "Optional, e.g. fd00:70::/64.",
                                    info: "Gives containers IPv6 addresses from this prefix as well.") {
                        TextField("none", text: $createIPv6Subnet)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontRegular)
                    }
                    NordicKeyValueEditor(title: "Labels", keyPlaceholder: "key", valuePlaceholder: "value", entries: $createLabels)
                }
                .padding(.top, NordicTheme.Spacing.s)
            }
            .font(.system(size: 12.5, weight: .semibold))

            NordicCommandPreview(arguments: req.buildCLIArguments())
        }
    }

    /// What blocks creating, in plain words.
    private func networkProblem(_ req: NetworkCreateRequest, usedSubnets: [String]) -> String? {
        if req.name.isEmpty { return "Give the network a name." }
        if let err = ValidationUtils.validateResourceName(req.name, fieldName: "The name") { return err }
        if CreateSheetChecks.nameTaken(req.name, in: appState.networks.map(\.name)) { return "A network called \(req.name) already exists." }
        if let err = ValidationUtils.validateIPv4CIDR(req.ipv4Subnet) { return err }
        if let clash = usedSubnets.first(where: { IPv4.overlaps($0, req.ipv4Subnet) }) {
            return "\(req.ipv4Subnet) overlaps \(clash), which another network uses."
        }
        if let err = ValidationUtils.validateIPv6CIDR(req.ipv6Subnet) { return err }
        return nil
    }

    private func createNetwork(_ req: NetworkCreateRequest) {
        showCreateSheet = false
        Task {
            await appState.performOperation(
                category: "Networks",
                title: "Create Network \(req.name)",
                redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments())
            ) {
                try await appState.runtimeService.createNetwork(request: req)
                return "Created network '\(req.name)'."
            }
            if appState.networks.contains(where: { $0.id == req.name }) { appState.selectedNetworkID = req.name }
        }
    }
}
