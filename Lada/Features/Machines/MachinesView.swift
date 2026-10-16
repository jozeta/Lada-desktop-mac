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

    // Machine detail tabs
    @State private var detailTab = "config"
    @State private var editCPUs = 4
    @State private var editMemoryGB = 8
    @State private var editHomeMount: HomeMountMode = .rw
    @State private var editVirtualization = false
    @State private var machineLogsText = ""
    @State private var machineCommandInput = "uname -a && df -h"
    @State private var machineCommandOutput = ""
    @State private var isRunningMachineCmd = false

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
                machineDetailPane(for: machine)
                    .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .machines,
                    title: "Select a Machine",
                    description: "Choose a persistent Linux virtual machine from the list to reconfigure its CPU/RAM/home-mount settings, run commands, or inspect boot logs."
                )
                .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .background(NordicTheme.contentSurface)
            }
        }
        .background(NordicTheme.windowBackground)
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
        .onChange(of: appState.selectedMachineID) { _, newValue in
            guard let id = newValue, let m = appState.machines.first(where: { $0.id == id }) else { return }
            editCPUs = m.cpus
            editMemoryGB = max(1, Int(m.memoryBytes / (1024 * 1024 * 1024)))
            editHomeMount = m.homeMount
            editVirtualization = m.virtualizationEnabled
            Task {
                machineLogsText = (try? await appState.runtimeService.fetchMachineLogs(id: id, bootLogs: false, tailLines: 200)) ?? ""
            }
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
                createCPUs = 4
                createMemoryGB = 8
                createHomeMount = .rw
                createVirtualization = false
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
        .background(NordicTheme.elevatedSurface)
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
        .background(NordicTheme.contentSurface)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private var machinesTable: some View {
        Table(appState.machines, selection: $appState.selectedMachineID) {
            TableColumn("Machine") { m in
                HStack(spacing: 8) {
                    LadaIcon(.machines, size: 15)
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
                Text(verbatim: "\(m.cpus) cores")
                    .font(NordicTheme.monoFontSmall)
            }
            .width(min: 65, ideal: 80)

            TableColumn("Memory") { m in
                Text(ByteCountFormatter.string(fromByteCount: Int64(m.memoryBytes), countStyle: .memory))
                    .font(NordicTheme.monoFontSmall)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Home Mount") { m in
                Text(m.homeMount.rawValue)
                    .font(NordicTheme.monoFontSmall)
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
        .accessibilityIdentifier(AccessibilityID.machineTable)
    }

    private func machineDetailPane(for machine: MachineModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NordicDetailHeader(
                title: machine.name,
                subtitle: machine.ipAddress ?? machine.imageReference ?? "Linux VM",
                badge: NordicStatusBadge(containerState: machine.status)
            ) {
                Button(role: .destructive) {
                    machinePendingDeletion = machine
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }

            Picker("Tab", selection: $detailTab) {
                Text("Configuration").tag("config")
                Text("Run Command").tag("exec")
                Text("Boot Logs").tag("logs")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider().overlay(NordicTheme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if detailTab == "config" {
                        machineConfigurationEditor(for: machine)
                    } else if detailTab == "exec" {
                        machineCommandRunner(for: machine)
                    } else {
                        machineLogsInspector(for: machine)
                    }
                }
                .padding(16)
            }
        }
        .background(NordicTheme.contentSurface)
    }

    private func machineConfigurationEditor(for machine: MachineModel) -> some View {
        let req = MachineUpdateRequest(
            name: machine.name,
            cpus: editCPUs,
            memoryGB: editMemoryGB,
            homeMount: editHomeMount,
            enableVirtualization: editVirtualization
        )
        return VStack(alignment: .leading, spacing: 12) {
            NordicSectionHeader(
                "Hardware & Mount Settings",
                subtitle: machine.status == .running ? "Stop machine before applying changes via `container machine set`" : "Ready to reconfigure"
            )
            Stepper(value: $editCPUs, in: 1...32) {
                Text(verbatim: "CPUs: \(editCPUs) cores")
            }
            Stepper(value: $editMemoryGB, in: 1...64) {
                Text(verbatim: "Memory: \(editMemoryGB) GB")
            }
            Picker("Home Directory Mount", selection: $editHomeMount) {
                ForEach(HomeMountMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayTitle).tag(mode)
                }
            }
            Toggle("Expose Nested Virtualization", isOn: $editVirtualization)

            Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments()))
                .font(NordicTheme.monoFontSmall)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Spacer()
                Button("Apply Machine Settings") {
                    Task {
                        await appState.performOperation(
                            category: "Machines",
                            title: "Reconfigure Machine \(machine.name)",
                            redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments())
                        ) {
                            try await appState.runtimeService.updateMachineConfig(request: req)
                            return "Updated configuration for machine '\(machine.name)'."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .controlSize(.small)
                .disabled(machine.status == .running)
            }
        }
        .padding(14)
        .background(NordicTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
    }

    private func machineCommandRunner(for machine: MachineModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NordicSectionHeader(
                "Execute Command inside \(machine.name)",
                subtitle: "Runs `container machine run --name \(machine.name) <cmd>`"
            )
            HStack {
                TextField("Command (e.g. uname -a)", text: $machineCommandInput)
                    .textFieldStyle(.roundedBorder)
                    .font(NordicTheme.monoFontRegular)
                Button(isRunningMachineCmd ? "Running…" : "Run") {
                    isRunningMachineCmd = true
                    let parts = machineCommandInput.split(separator: " ").map(String.init)
                    Task {
                        let res = try? await appState.runtimeService.runInMachine(
                            id: machine.id,
                            command: parts.isEmpty ? ["uname", "-a"] : parts,
                            asRoot: false
                        )
                        machineCommandOutput = res?.combinedOutput ?? "Failed to execute command."
                        isRunningMachineCmd = false
                        await appState.refreshAll(isUserInitiated: false)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(isRunningMachineCmd)
            }

            Text(machineCommandOutput.isEmpty ? "Command output will appear here." : machineCommandOutput)
                .font(NordicTheme.monoFontRegular)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func machineLogsInspector(for machine: MachineModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NordicSectionHeader("Machine Boot & Console Logs")
                Spacer()
                Button("Refresh") {
                    Task {
                        machineLogsText = (try? await appState.runtimeService.fetchMachineLogs(id: machine.id, bootLogs: false, tailLines: 200)) ?? ""
                    }
                }
                .controlSize(.small)
            }
            Text(machineLogsText.isEmpty ? "No machine logs available." : machineLogsText)
                .font(NordicTheme.monoFontRegular)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
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
                TextField("Base Image (e.g. alpine:latest, ubuntu:24.04)", text: $createImage)
                    .font(NordicTheme.monoFontRegular)
                Stepper(value: $createCPUs, in: 1...32) {
                    Text(verbatim: "CPUs: \(createCPUs) cores")
                }
                Stepper(value: $createMemoryGB, in: 1...64) {
                    Text(verbatim: "Memory: \(createMemoryGB) GB")
                }
                Picker("Home Directory Mount", selection: $createHomeMount) {
                    ForEach(HomeMountMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
                Toggle("Boot Machine Immediately", isOn: $createBootImmediately)
                Toggle("Enable Nested Virtualization (--virtualization)", isOn: $createVirtualization)
                Toggle("Set as Default Machine (--set-default)", isOn: $createSetDefault)
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
        .frame(width: 520)
    }
}
