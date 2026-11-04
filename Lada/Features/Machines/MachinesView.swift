import SwiftUI

public struct MachinesView: View {
    @ObservedObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var machinePendingDeletion: MachineModel?

    @State private var createName = ""
    @State private var createImage = "alpine:latest"
    @State private var createCPUs = 4
    @State private var createMemoryGB = 8
    @State private var createHomeMount: HomeMountMode = .rw
    @State private var createVirtualization = false
    @State private var createSetDefault = false
    @State private var createBootImmediately = true

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
        let nested = appState.capabilities.nestedVirtualization
        let nestedSupported: Bool = { if case .unsupported = nested { return false }; return true }()
        return NordicSheet(
            icon: .machines,
            title: "Create Machine",
            subtitle: "A persistent Linux virtual machine with your Mac user and home folder: a place for dev tools and long-lived shells.",
            primaryTitle: "Create Machine",
            problem: machineProblem(req),
            onCancel: { showCreateSheet = false },
            onPrimary: { createMachine(req) }
        ) {
            NordicFormSection(title: "Machine") {
                NordicFormField(title: "Name", hint: "Lowercase letters, digits and hyphens.",
                                info: "Open a shell in it later with `container machine run -n <name>`.") {
                    TextField("dev", text: $createName)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                        .accessibilityIdentifier("lada.machines.create.name")
                }
                NordicFormField(title: "Linux image", hint: "Type to search images on this Mac and in the Image Library.",
                                info: "The distribution the machine starts from. Its package manager and tools are what you get in the shell.") {
                    ImageReferenceField(text: $createImage, placeholder: "alpine:3.22",
                                        localReferences: appState.images.map(\.fullReference),
                                        accent: NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    NordicChoiceChips(options: ["alpine:3.22", "debian:trixie-slim", "ubuntu:24.04", "fedora:42"], selected: createImage) { createImage = $0 }
                }
            }

            NordicFormSection(title: "Resources") {
                HStack(alignment: .top, spacing: NordicTheme.Spacing.xl) {
                    NordicFormField(title: "CPUs", hint: runtimeDefaultHint(appState.systemProperties.machine.cpus.map { "\($0)" }),
                                    info: "Virtual CPUs the machine may use. They are shared with your Mac, not reserved.") {
                        Stepper(value: $createCPUs, in: 1...32) { Text(verbatim: "\(createCPUs) vCPU").monospacedDigit() }
                    }
                    NordicFormField(title: "Memory", hint: runtimeDefaultHint(appState.systemProperties.machine.memoryGB.map { "\($0) GB" }),
                                    info: "The most memory the machine can use; taken from your Mac only as needed.") {
                        Stepper(value: $createMemoryGB, in: 1...64) { Text(verbatim: "\(createMemoryGB) GB").monospacedDigit() }
                    }
                }
            }

            NordicFormSection(title: "Sharing & Options") {
                NordicFormField(title: "Home folder", hint: Self.homeMountExplanation(createHomeMount),
                                info: "Your Mac home folder appears inside the machine at the same path.") {
                    Picker("Home folder", selection: $createHomeMount) {
                        Text("Read-write").tag(HomeMountMode.rw)
                        Text("Read-only").tag(HomeMountMode.ro)
                        Text("Not shared").tag(HomeMountMode.none)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                optionToggle("Start now", detail: "Boot the machine as soon as it's created.", isOn: $createBootImmediately)
                optionToggle("Make it the default machine", detail: "Used by `container machine` commands that don't name one.", isOn: $createSetDefault)
                optionToggle("Nested virtualization",
                             detail: nestedSupported ? "Lets the machine run its own VMs (KVM)." : nested.statusDescription,
                             isOn: $createVirtualization)
                    .disabled(!nestedSupported)
            }

            NordicCommandPreview(arguments: req.buildCLIArguments())
        }
    }

    private func optionToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(NordicTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    private func runtimeDefaultHint(_ value: String?) -> String? {
        value.map { "Runtime default: \($0)" }
    }

    static func homeMountExplanation(_ mode: HomeMountMode) -> String {
        switch mode {
        case .rw: return "The machine can read and change files in your Mac home folder."
        case .ro: return "The machine can read your home folder but not change it."
        case .none: return "Your home folder isn't visible in the machine."
        }
    }

    private func machineProblem(_ req: MachineCreateRequest) -> String? {
        if req.name.isEmpty { return "Give the machine a name." }
        if let err = ValidationUtils.validateResourceName(req.name, fieldName: "The name") { return err }
        if !ValidationUtils.isValidMachineName(req.name) { return "Use lowercase letters, digits and hyphens in the name." }
        if CreateSheetChecks.nameTaken(req.name, in: appState.machines.map(\.id)) { return "A machine called \(req.name) already exists." }
        if req.imageReference.isEmpty { return "Choose the Linux image the machine starts from." }
        return nil
    }

    private func createMachine(_ req: MachineCreateRequest) {
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
            if appState.machines.contains(where: { $0.id == req.name }) { appState.selectedMachineID = req.name }
        }
    }
}
