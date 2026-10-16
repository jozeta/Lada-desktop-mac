import SwiftUI

public struct NetworksView: View {
    @ObservedObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var networkPendingDeletion: NetworkModel? = nil
    @State private var confirmPruneUnused = false

    @State private var createName = ""
    @State private var createIPv4Subnet = ""
    @State private var createIPv6Subnet = ""
    @State private var createInternal = false
    @State private var validationMessage: String? = nil

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
                .background(NordicTheme.contentSurface)
            }
        }
        .background(NordicTheme.windowBackground)
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
                validationMessage = nil
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
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var networkTable: some View {
        Table(appState.networks, selection: $appState.selectedNetworkID) {
            TableColumn("Name") { net in
                HStack(spacing: 8) {
                    LadaIcon(.networks, size: 15)
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
                    .font(NordicTheme.monoFontSmall)
            }
            .width(min: 70, ideal: 85)

            TableColumn("IPv4 Subnet") { net in
                Text(net.ipv4Subnet.isEmpty ? "—" : net.ipv4Subnet)
                    .font(NordicTheme.monoFontSmall)
            }
            .width(min: 120, ideal: 145)

            TableColumn("IPv4 Gateway") { net in
                Text(net.ipv4Gateway.isEmpty ? "—" : net.ipv4Gateway)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 110, ideal: 135)

            TableColumn("Containers") { net in
                let count = containersAttached(to: net).count
                Text(verbatim: "\(count) attached")
                    .font(.system(size: 11))
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
                        NordicSectionHeader("Subnet & Routing")
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
                    .background(NordicTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Attached Containers (\(attached.count))")
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
                    .background(NordicTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
                }
                .padding(16)
            }
        }
        .background(NordicTheme.contentSurface)
    }

    private var createNetworkSheet: some View {
        let req = NetworkCreateRequest(
            name: createName.trimmingCharacters(in: .whitespacesAndNewlines),
            ipv4Subnet: createIPv4Subnet.trimmingCharacters(in: .whitespacesAndNewlines),
            ipv6Subnet: createIPv6Subnet.trimmingCharacters(in: .whitespacesAndNewlines),
            isInternal: createInternal
        )
        return VStack(alignment: .leading, spacing: 16) {
            Text("Create Isolated Network")
                .font(NordicTheme.titleFont)

            Form {
                TextField("Network Name (e.g. backend-net)", text: $createName)
                    .font(NordicTheme.monoFontRegular)
                TextField("IPv4 Subnet CIDR (optional, e.g. 192.168.70.0/24)", text: $createIPv4Subnet)
                    .font(NordicTheme.monoFontRegular)
                TextField("IPv6 Subnet Prefix (optional, e.g. fd00:70::/64)", text: $createIPv6Subnet)
                    .font(NordicTheme.monoFontRegular)
                Toggle("Internal Network Only (--internal, disables external routing)", isOn: $createInternal)
            }
            .formStyle(.grouped)

            if let msg = validationMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.statusRed)
            }

            Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments()))
                .font(NordicTheme.monoFontSmall)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("Cancel") { showCreateSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Network") {
                    if let nameErr = ValidationUtils.validateResourceName(req.name, fieldName: "Network name") {
                        validationMessage = nameErr
                        return
                    }
                    if let cidrErr = ValidationUtils.validateIPv4CIDR(req.ipv4Subnet) {
                        validationMessage = cidrErr
                        return
                    }
                    if let v6Err = ValidationUtils.validateIPv6CIDR(req.ipv6Subnet) {
                        validationMessage = v6Err
                        return
                    }
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
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(req.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
