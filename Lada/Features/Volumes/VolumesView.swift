import SwiftUI

public struct VolumesView: View {
    @ObservedObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var volumePendingDeletion: VolumeModel? = nil
    @State private var confirmPruneUnused = false

    @State private var createName = ""
    @State private var createSize = "512M"
    @State private var createJournalMode: Ext4JournalMode = .ordered
    @State private var validationMessage: String? = nil

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
                .background(NordicTheme.contentSurface)
            }
        }
        .background(NordicTheme.windowBackground)
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
                createSize = "512M"
                createJournalMode = .ordered
                validationMessage = nil
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
        .background(NordicTheme.elevatedSurface)
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
        .background(NordicTheme.contentSurface)
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
            TableColumn("Volume Name") { vol in
                HStack(spacing: 8) {
                    LadaIcon(.volumes, size: 15)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(vol.name)
                        .font(.system(size: 12, weight: .semibold))
                    if vol.isAnonymous {
                        NordicStatusBadge(label: "Anonymous", tone: .neutral, showDot: false)
                    }
                }
            }
            .width(min: 150, ideal: 200)

            TableColumn("Driver / FS") { vol in
                Text("\(vol.driver) (\(vol.format))")
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 95, ideal: 115)

            TableColumn("Capacity") { vol in
                if let size = vol.sizeInBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(NordicTheme.monoFontSmall)
                } else {
                    Text("512 MB (Sparse)")
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            .width(min: 90, ideal: 115)

            TableColumn("Attached Containers") { vol in
                let attached = containersMounting(vol)
                if attached.isEmpty {
                    Text("Unused")
                        .font(.system(size: 11))
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
                        NordicSectionHeader("Volume Metadata")
                        LabeledContent("Driver", value: volume.driver)
                        LabeledContent("Filesystem", value: volume.format)
                        LabeledContent("Sparse Capacity", value: ByteCountFormatter.string(fromByteCount: Int64(volume.sizeInBytes ?? 0), countStyle: .file))
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
                    .background(NordicTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Mounted By (\(attached.count))")
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
                    .background(NordicTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
                }
                .padding(16)
            }
        }
        .background(NordicTheme.contentSurface)
    }

    private var createVolumeSheet: some View {
        let req = VolumeCreateRequest(
            name: createName.trimmingCharacters(in: .whitespacesAndNewlines),
            sizeSpec: createSize.trimmingCharacters(in: .whitespacesAndNewlines),
            journalMode: createJournalMode
        )
        return VStack(alignment: .leading, spacing: 16) {
            Text("Create Named Volume")
                .font(NordicTheme.titleFont)

            Form {
                TextField("Volume Name (e.g. pgdata)", text: $createName)
                    .font(NordicTheme.monoFontRegular)
                TextField("Sparse Size (-s, e.g. 512M, 5G, 20G)", text: $createSize)
                    .font(NordicTheme.monoFontRegular)
                Picker("Ext4 Journal Mode (--opt journal=...)", selection: $createJournalMode) {
                    ForEach(Ext4JournalMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayDescription).tag(mode)
                    }
                }
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
                Button("Create Volume") {
                    if let err = ValidationUtils.validateVolumeName(req.name) {
                        validationMessage = err
                        return
                    }
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
