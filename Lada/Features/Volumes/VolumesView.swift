import SwiftUI

public struct VolumesView: View {
    @ObservedObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var volumePendingDeletion: VolumeModel?
    @State private var confirmPruneUnused = false

    @State private var createName = ""
    @State private var createSize = ""
    @State private var createJournalMode: Ext4JournalMode = .ordered
    @State private var createJournalSize = ""
    @State private var createLabels: [KeyValueEntry] = []

    public init(appState: AppState) {
        self.appState = appState
    }

    private func containersMounting(_ volume: VolumeModel) -> [ContainerModel] {
        appState.containers.filter { container in
            container.configuration.mounts.contains { mount in
                mount.kind == .volume && (mount.source == volume.name || mount.source.contains(volume.name))
            }
        }
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                headerBar
                mountComparisonBanner
                if appState.volumes.isEmpty {
                    NordicEmptyState(
                        icon: .volumes,
                        title: "No Named Volumes",
                        description: "Create persistent ext4 sparse block volumes that can be mounted across container lifecycles.",
                        primaryActionTitle: "Create Volume",
                        onPrimaryAction: { showCreateSheet = true }
                    )
                } else {
                    volumeTable
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

            if let selectedId = appState.selectedVolumeID,
               let volume = appState.volumes.first(where: { $0.id == selectedId }) {
                volumeInspector(for: volume)
                    .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .volumes,
                    title: "Select a Volume",
                    description: "Choose a volume from the list to inspect its ext4 block image path, sparse allocation size, mount options, and attached containers."
                )
                .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .onAppear {
            if appState.selectedVolumeID == nil || !appState.volumes.contains(where: { $0.id == appState.selectedVolumeID }) {
                appState.selectedVolumeID = appState.volumes.first?.id
            }
        }
        .onChange(of: appState.volumes.count) { _, _ in
            if appState.selectedVolumeID == nil || !appState.volumes.contains(where: { $0.id == appState.selectedVolumeID }) {
                appState.selectedVolumeID = appState.volumes.first?.id
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createVolumeSheet
        }
        .confirmationDialog(
            "Delete Volume '\(volumePendingDeletion?.name ?? "")'?",
            isPresented: Binding(
                get: { volumePendingDeletion != nil },
                set: { if !$0 { volumePendingDeletion = nil } }
            ),
            presenting: volumePendingDeletion
        ) { target in
            let attached = containersMounting(target)
            if attached.isEmpty {
                Button("Delete Volume", role: .destructive) {
                    Task {
                        await appState.performOperation(
                            category: "Volumes",
                            title: "Delete Volume \(target.name)",
                            redactedCommand: "container volume delete \(target.name)"
                        ) {
                            try await appState.runtimeService.deleteVolume(name: target.name)
                            return "Deleted volume '\(target.name)'."
                        }
                        if appState.selectedVolumeID == target.id {
                            appState.selectedVolumeID = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            let attached = containersMounting(target)
            if attached.isEmpty {
                Text("Permanently delete persistent ext4 volume '\(target.name)' and all files stored inside it?")
            } else {
                Text("Cannot delete volume '\(target.name)' while \(attached.count) container(s) mount it (\(attached.map(\.id).joined(separator: ", "))).")
            }
        }
        .confirmationDialog("Prune Unused Volumes?", isPresented: $confirmPruneUnused) {
            Button("Prune Unused Volumes", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Volumes",
                        title: "Prune Unused Volumes",
                        redactedCommand: "container volume prune"
                    ) {
                        try await appState.runtimeService.pruneVolumes()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all local volumes that are not mounted by any container. Data inside pruned volumes cannot be recovered.")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text(verbatim: "Volumes & Mounts (\(appState.volumes.count))")
                .font(NordicTheme.subtitleFont)
                .foregroundStyle(NordicTheme.primaryText)
            Spacer()
            Button {
                confirmPruneUnused = true
            } label: {
                Label("Prune Unused", systemImage: "sparkles")
            }
            .controlSize(.small)
            .disabled(appState.volumes.isEmpty)

            Button {
                createName = ""
                createSize = ""
                createJournalMode = .ordered
                createJournalSize = ""
                createLabels = []
                showCreateSheet = true
            } label: {
                Label("Create Volume", systemImage: "plus")
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

    private var mountComparisonBanner: some View {
        HStack(spacing: 16) {
            mountGuideItem(
                title: "Named Volumes (ext4)",
                subtitle: "Managed block filesystems (`-v name:/path`). Best for databases & high IOPS."
            )
            Divider().frame(height: 28)
            mountGuideItem(
                title: "Host Bind Mounts (virtiofs)",
                subtitle: "Shared macOS directory (`-v /Users/...:/path`). Best for live source code."
            )
            Divider().frame(height: 28)
            mountGuideItem(
                title: "Tmpfs Mounts (RAM)",
                subtitle: "Ephemeral memory filesystem (`--tmpfs /path`). Cleared when stopped."
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }

    private func mountGuideItem(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(NordicTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var volumeTable: some View {
        Table(appState.volumes, selection: $appState.selectedVolumeID) {
            TableColumn("Name") { vol in
                HStack(spacing: 8) {
                    LadaIcon(.volumes, size: 14)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(vol.name)
                        .font(.system(size: 12, weight: .semibold))
                    if vol.isAnonymous {
                        NordicStatusBadge(label: "Anonymous", tone: .neutral, showDot: false)
                    }
                }
            }
            .width(min: 150, ideal: 200)

            TableColumn("Format") { vol in
                Text("\(vol.driver) (\(vol.format))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 95, ideal: 115)

            TableColumn("Capacity") { vol in
                if let size = vol.sizeInBytes {
                    Text(NordicFormat.bytes(fromByteCount: Int64(size), countStyle: .file))
                        .font(.system(size: 12).monospacedDigit())
                } else {
                    Text("512 MB (Sparse)")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            .width(min: 90, ideal: 115)

            TableColumn("Used by") { vol in
                let attached = containersMounting(vol)
                if attached.isEmpty {
                    Text("Unused")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                } else {
                    NordicStatusBadge(label: "\(attached.count) mounted", tone: .positive)
                }
            }
            .width(min: 95, ideal: 120)

            TableColumn("Actions") { vol in
                Button(role: .destructive) {
                    volumePendingDeletion = vol
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(NordicTheme.statusRed)
                }
                .buttonStyle(.borderless)
                .help("Delete volume \(vol.name)")
            }
            .width(min: 55, ideal: 65)
        }
        .nordicTransparentTable()
        .accessibilityIdentifier(AccessibilityID.volumeTable)
    }

    private func volumeInspector(for volume: VolumeModel) -> some View {
        let attached = containersMounting(volume)
        return VStack(spacing: 0) {
            NordicDetailHeader(
                title: volume.name,
                subtitle: volume.sourcePath,
                badge: NordicStatusBadge(label: volume.format.uppercased(), tone: .accent, showDot: false)
            ) {
                Button(role: .destructive) {
                    volumePendingDeletion = volume
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Volume Metadata", info: "Where the volume's disk image lives on your Mac, its format and size, from `container volume inspect`.")
                        LabeledContent("Driver", value: volume.driver)
                        LabeledContent("Filesystem", value: volume.format)
                        LabeledContent("Sparse Capacity", value: NordicFormat.bytes(fromByteCount: Int64(volume.sizeInBytes ?? 0), countStyle: .file))
                        LabeledContent("Anonymous", value: volume.isAnonymous ? "Yes" : "No")
                        LabeledContent("Created", value: volume.creationDate.formatted(date: .abbreviated, time: .shortened))
                        if !volume.options.isEmpty {
                            Divider()
                            ForEach(volume.options.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                                LabeledContent("Option: \(k)", value: v)
                                    .font(NordicTheme.monoFontSmall)
                            }
                        }
                    }
                    .padding(14)
                    .nordicSurface()

                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Mounted By (\(attached.count))", info: "Containers that have this volume mounted. A volume in use can't be deleted.")
                        if attached.isEmpty {
                            Text("No containers currently mount this volume.")
                                .font(.system(size: 12))
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            ForEach(attached) { container in
                                HStack {
                                    NordicStatusBadge(containerState: container.state)
                                    Text(container.id)
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    if let mount = container.configuration.mounts.first(where: { $0.source.contains(volume.name) }) {
                                        Text(mount.destination)
                                            .font(NordicTheme.monoFontSmall)
                                            .foregroundStyle(NordicTheme.secondaryText)
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

    private var createVolumeSheet: some View {
        let req = VolumeCreateRequest(
            name: createName.trimmingCharacters(in: .whitespacesAndNewlines),
            sizeSpec: createSize.trimmingCharacters(in: .whitespacesAndNewlines),
            journalMode: createJournalMode,
            journalSize: createJournalSize.trimmingCharacters(in: .whitespacesAndNewlines),
            labels: createLabels
        )
        let sizeBytes = ByteSizeSpec.bytes(req.sizeSpec)
        let free = appState.hostDiskSpace?.availableBytes
        return NordicSheet(
            icon: .volumes,
            title: "Create Volume",
            subtitle: "Storage that outlives containers. Mount it into a container to keep databases, uploads and caches.",
            primaryTitle: "Create Volume",
            problem: volumeProblem(req),
            onCancel: { showCreateSheet = false },
            onPrimary: { createVolume(req) }
        ) {
            NordicFormSection(title: "Volume") {
                NordicFormField(title: "Name", hint: "Lowercase letters, digits, '.', '-' or '_'. Mount it with -v <name>:/path.",
                                info: "The volume's name. Containers mount it with `container run -v <name>:/path/in/container`.") {
                    TextField("pgdata", text: $createName)
                        .textFieldStyle(.roundedBorder)
                        .font(NordicTheme.monoFontRegular)
                        .accessibilityIdentifier("lada.volumes.create.name")
                }
                NordicFormField(title: "Size",
                                info: "The volume is a sparse ext4 disk image: this is the most it can hold, but it only takes space on your Mac as data is written. Leave empty for the runtime's default.") {
                    HStack {
                        TextField("runtime default", text: $createSize)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontRegular)
                            .frame(width: 150)
                        NordicChoiceChips(options: ["1G", "5G", "20G", "50G", "100G"], selected: createSize.uppercased()) { createSize = $0 }
                    }
                    Group {
                        if let sizeBytes, let free, sizeBytes > free {
                            Text("Larger than this Mac's free space (\(NordicFormat.bytes(fromByteCount: free, countStyle: .file))). That's allowed, since the volume only grows as it's filled, but it can't be filled completely.")
                                .foregroundStyle(NordicTheme.statusAmber)
                        } else if let free {
                            Text("Uses space only as data is written. This Mac has \(NordicFormat.bytes(fromByteCount: free, countStyle: .file)) free.")
                                .foregroundStyle(NordicTheme.secondaryText)
                        } else {
                            Text("Uses space only as data is written.").foregroundStyle(NordicTheme.secondaryText)
                        }
                    }
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                }
                NordicFormField(title: "Journal", hint: Self.journalExplanation(createJournalMode),
                                info: "How the ext4 filesystem protects data against a crash. Ordered suits almost everything.") {
                    Picker("Journal", selection: $createJournalMode) {
                        Text("Ordered").tag(Ext4JournalMode.ordered)
                        Text("Writeback").tag(Ext4JournalMode.writeback)
                        Text("Full journal").tag(Ext4JournalMode.journal)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
                    NordicFormField(title: "Journal size", hint: "Optional, e.g. 64M. Leave empty for the default.",
                                    info: "Space reserved for the filesystem journal.") {
                        TextField("default", text: $createJournalSize)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontRegular)
                            .frame(width: 150)
                    }
                    NordicKeyValueEditor(title: "Labels", keyPlaceholder: "key", valuePlaceholder: "value", entries: $createLabels)
                }
                .padding(.top, NordicTheme.Spacing.s)
            }
            .font(.system(size: 12.5, weight: .semibold))

            NordicCommandPreview(arguments: req.buildCLIArguments())
        }
    }

    static func journalExplanation(_ mode: Ext4JournalMode) -> String {
        switch mode {
        case .ordered: return "Recommended. Metadata is journaled and data is written before it, so files are never left with garbage after a crash."
        case .writeback: return "Fastest. Only metadata is journaled; after a crash, recently written files may contain old data."
        case .journal: return "Safest and slowest. Data and metadata are both journaled."
        }
    }

    private func volumeProblem(_ req: VolumeCreateRequest) -> String? {
        if req.name.isEmpty { return "Give the volume a name." }
        if let err = ValidationUtils.validateVolumeName(req.name) { return err }
        if CreateSheetChecks.nameTaken(req.name, in: appState.volumes.map(\.name)) { return "A volume called \(req.name) already exists." }
        if !req.sizeSpec.isEmpty, ByteSizeSpec.bytes(req.sizeSpec) == nil { return "Write the size as a number and unit, e.g. 512M or 20G." }
        if !req.journalSize.isEmpty, ByteSizeSpec.bytes(req.journalSize) == nil { return "Write the journal size as a number and unit, e.g. 64M." }
        return nil
    }

    private func createVolume(_ req: VolumeCreateRequest) {
        showCreateSheet = false
        Task {
            await appState.performOperation(
                category: "Volumes",
                title: "Create Volume \(req.name)",
                redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments())
            ) {
                try await appState.runtimeService.createVolume(request: req)
                return "Created volume '\(req.name)'."
            }
            if appState.volumes.contains(where: { $0.id == req.name }) { appState.selectedVolumeID = req.name }
        }
    }
}
