import SwiftUI

public struct MachinesView: View {
    @ObservedObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var machinePendingDeletion: MachineModel? = nil

    @State private var createName = ""
    @State private var createImage = "alpine:latest"
    @State private var createCPUs = 4
    @State private var createMemoryGB = 8
    @State private var createHomeMount: HomeMountMode = .rw
    @State private var createVirtualization = false
    @State private var createSetDefault = false
    @State private var createBootImmediately = true
    @State private var validationMessage: String? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                headerBar
                architectureBanner
                if appState.machines.isEmpty {
                    NordicEmptyState(
                        icon: .machines,
                        title: "No Container Machines",
                        description: "Apple's container runtime runs every container inside its own lightweight micro-VM by default (`container run`). In addition, `container machine` lets you create persistent Linux virtual machines for interactive dev shells, nested virtualization, or custom kernels.",
                        primaryActionTitle: "Create Machine",
                        onPrimaryAction: { showCreateSheet = true }
                    )
                } else {
                    machinesTable
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

            if let selectedId = appState.selectedMachineID,
               let machine = appState.machines.first(where: { $0.id == selectedId }) {
                MachineDetailView(
                    appState: appState,
                    machine: machine,
                    workspace: appState.machineWorkspaces.workspace(for: machine.id),
                    onDelete: { machinePendingDeletion = machine }
                )
                .id(machine.id)
                .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .machines,
                    title: "Select a Machine",
                    description: "Choose a machine to see its details and live activity, open its shell, browse its files, read its logs or change its settings."
                )
                .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .onAppear {
            if appState.selectedMachineID == nil || !appState.machines.contains(where: { $0.id == appState.selectedMachineID }) {
                appState.selectedMachineID = appState.machines.first?.id
            }
        }
        .onChange(of: appState.machines.count) { _, _ in
            if appState.selectedMachineID == nil || !appState.machines.contains(where: { $0.id == appState.selectedMachineID }) {
                appState.selectedMachineID = appState.machines.first?.id
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createMachineSheet
        }
        .confirmationDialog(
            "Delete Machine '\(machinePendingDeletion?.name ?? "")'?",
            isPresented: Binding(
                get: { machinePendingDeletion != nil },
                set: { if !$0 { machinePendingDeletion = nil } }
            ),
            presenting: machinePendingDeletion
        ) { target in
            Button("Delete Machine", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Machines",
                        title: "Delete Machine \(target.name)",
                        redactedCommand: "container machine delete \(target.name)"
                    ) {
                        try await appState.runtimeService.deleteMachine(id: target.id)
                        return "Deleted machine '\(target.name)'."
                    }
                    if appState.selectedMachineID == target.id {
                        appState.selectedMachineID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Permanently remove Linux virtual machine '\(target.name)' and its virtual disk image?")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text(verbatim: "Container Machines (\(appState.machines.count))")
                .font(NordicTheme.subtitleFont)
                .foregroundStyle(NordicTheme.primaryText)
            Spacer()
            Button {
                createName = ""
                createImage = "alpine:latest"
                // Start from the runtime's own machine defaults (`machine.*` properties) when reported.
                let defaults = appState.systemProperties.machine
                createCPUs = defaults.cpus ?? 4
                createMemoryGB = defaults.memoryGB ?? 8
                createHomeMount = defaults.homeMount ?? .rw
                createVirtualization = defaults.virtualization ?? false
                createSetDefault = false
                createBootImmediately = true
                validationMessage = nil
                showCreateSheet = true
            } label: {
                Label("Create Machine", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .nordicBar()
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var architectureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            Text("Apple's container runtime isolates each OCI container in a dedicated Virtualization.framework micro-VM (`container run`), and also provides persistent Linux machines via `container machine` (`create`, `run`, `set`, `set-default`, `logs`, `stop`, `delete`).")
                .font(.system(size: 11))
                .foregroundStyle(NordicTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var machinesTable: some View {
        Table(appState.machines, selection: $appState.selectedMachineID) {
            TableColumn("Machine") { m in
                HStack(spacing: 8) {
                    LadaIcon(.machines, size: 14)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(m.name)
                        .font(.system(size: 12, weight: .semibold))
                    if m.isDefault {
                        NordicStatusBadge(label: "Default", tone: .positive, showDot: false)
                    }
                }
            }
            .width(min: 140, ideal: 180)

            TableColumn("State") { m in
                NordicStatusBadge(containerState: m.status)
            }
            .width(min: 85, ideal: 100)

            TableColumn("CPUs") { m in
                Text(verbatim: m.cpus > 0 ? "\(m.cpus) cores" : "—")
                    .font(.system(size: 12).monospacedDigit())
            }
            .width(min: 65, ideal: 80)

            TableColumn("Memory") { m in
                Text(m.memoryBytes > 0 ? NordicFormat.bytes(fromByteCount: Int64(m.memoryBytes), countStyle: .memory) : "—")
                    .font(.system(size: 12).monospacedDigit())
            }
            .width(min: 80, ideal: 100)

            TableColumn("Home Mount") { m in
                Text(m.homeMount.rawValue)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 75, ideal: 90)

            TableColumn("Actions") { m in
                HStack(spacing: 6) {
                    if m.status == .running {
                        Button {
                            Task {
                                await appState.performOperation(
                                    category: "Machines",
                                    title: "Stop Machine \(m.name)",
                                    redactedCommand: "container machine stop \(m.name)"
                                ) {
                                    try await appState.runtimeService.stopMachine(id: m.id)
                                    return "Stopped machine '\(m.name)'."
                                }
                            }
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop Machine")
                    } else {
                        Button {
                            Task {
                                await appState.performOperation(
                                    category: "Machines",
                                    title: "Start Machine \(m.name)",
                                    redactedCommand: "container machine run --name \(m.name)"
                                ) {
                                    try await appState.runtimeService.startMachine(id: m.id)
                                    return "Started machine '\(m.name)'."
                                }
                            }
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Start Machine")
                    }

                    Button {
                        Task {
                            await appState.performOperation(
                                category: "Machines",
                                title: "Set Default Machine \(m.name)",
                                redactedCommand: "container machine set-default \(m.name)"
                            ) {
                                try await appState.runtimeService.setDefaultMachine(id: m.id)
                                return "Set '\(m.name)' as default machine."
                            }
                        }
                    } label: {
                        Image(systemName: m.isDefault ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                    .disabled(m.isDefault)
                    .help("Set as Default Machine")

                    Button(role: .destructive) {
                        machinePendingDeletion = m
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(NordicTheme.statusRed)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete Machine")
                }
            }
            .width(min: 90, ideal: 105)
        }
        .nordicTransparentTable()
        .accessibilityIdentifier(AccessibilityID.machineTable)
    }

    private var createMachineSheet: some View {
        let req = MachineCreateRequest(
            name: createName.trimmingCharacters(in: .whitespacesAndNewlines),
            imageReference: createImage.trimmingCharacters(in: .whitespacesAndNewlines),
            cpus: createCPUs,
            memoryGB: createMemoryGB,
            homeMount: createHomeMount,
            setDefault: createSetDefault,
            bootImmediately: createBootImmediately,
            enableVirtualization: createVirtualization
        )
        return VStack(alignment: .leading, spacing: 16) {
            Text("Create Container Machine")
                .font(NordicTheme.titleFont)

            Form {
                TextField("Machine Name (e.g. dev-vm)", text: $createName)
                    .font(NordicTheme.monoFontRegular)
                    .nordicInfo("Lowercase letters, digits and hyphens. Used with `container machine run -n <name>`.")
                TextField("Base Image (e.g. alpine:latest, ubuntu:24.04)", text: $createImage)
                    .font(NordicTheme.monoFontRegular)
                    .nordicInfo("The Linux image the machine's disk starts from, e.g. alpine:3.22 or ubuntu:24.04.")
                Stepper(value: $createCPUs, in: 1...32) {
                    Text(verbatim: "CPUs: \(createCPUs) cores")
                }
                .nordicInfo("Virtual CPUs the machine may use; shared with your Mac, not reserved.")
                Stepper(value: $createMemoryGB, in: 1...64) {
                    Text(verbatim: "Memory: \(createMemoryGB) GB")
                }
                .nordicInfo("The most memory the machine can use; taken from your Mac only as needed.")
                Picker("Home Directory Mount", selection: $createHomeMount) {
                    ForEach(HomeMountMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
                .nordicInfo("Share your Mac home folder into the machine read-write, read-only, or not at all.")
                Toggle("Boot Machine Immediately", isOn: $createBootImmediately)
                    .nordicInfo("Start the machine as soon as it is created.")
                Toggle("Enable Nested Virtualization (--virtualization)", isOn: $createVirtualization)
                    .nordicInfo("Lets the machine run its own VMs (KVM). Needs an M3 chip or newer.")
                Toggle("Set as Default Machine (--set-default)", isOn: $createSetDefault)
                    .nordicInfo("The default machine is used by machine commands that don't name one.")
            }
            .nordicFormPanel()

            if let msg = validationMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.statusRed)
            }

            Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments()))
                .font(NordicTheme.monoFontSmall)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nordicChip()

            HStack {
                Button("Cancel") { showCreateSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Machine") {
                    if let err = ValidationUtils.validateResourceName(req.name, fieldName: "Machine name") {
                        validationMessage = err
                        return
                    }
                    showCreateSheet = false
                    Task {
                        await appState.performOperation(
                            category: "Machines",
                            title: "Create Machine \(req.name)",
                            redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments())
                        ) {
                            try await appState.runtimeService.createMachine(request: req)
                            return "Created machine '\(req.name)'."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(req.name.isEmpty || req.imageReference.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .nordicPageBackground()
    }
}
