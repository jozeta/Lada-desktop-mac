import AppKit
import SwiftUI

public struct ImagesView: View {
    @ObservedObject var appState: AppState
    @State private var inspectedImage: ImageModel? = nil
    @State private var showTagSheetFor: ImageModel? = nil
    @State private var newTagInput = ""
    @State private var imagePendingDeletion: ImageModel? = nil
    @State private var confirmPruneUnused = false
    @State private var pullImageRef = ""
    @State private var pullPlatform = ""
    @State private var pullScheme = "https"
    @State private var isPulling = false
    @State private var pullProgressLines: [String] = []

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredImages: [ImageModel] {
        let query = appState.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appState.images }
        return appState.images.filter {
            $0.fullReference.lowercased().contains(query)
                || $0.repository.lowercased().contains(query)
                || $0.tag.lowercased().contains(query)
                || $0.digest.lowercased().contains(query)
        }
    }

    private func containersReferencing(_ image: ImageModel) -> [ContainerModel] {
        appState.containers.filter {
            $0.imageReference == image.fullReference
                || $0.imageReference.contains(image.repository)
                || (!image.digest.isEmpty && $0.imageDigest == image.digest)
        }
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                headerToolbar
                if filteredImages.isEmpty {
                    NordicEmptyState(
                        icon: .images,
                        title: appState.images.isEmpty ? "No Local Container Images" : "No Matching Images",
                        description: appState.images.isEmpty
                            ? "Pull an OCI image from a registry, load a tar archive, or build a Containerfile to populate your local image store."
                            : "Adjust your search filter to see matching images.",
                        primaryActionTitle: "Pull Image",
                        onPrimaryAction: { appState.showPullImageSheet = true }
                    )
                } else {
                    imageTable
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

            if let selectedId = appState.selectedImageID,
               let image = appState.images.first(where: { $0.id == selectedId }) {
                imageInspector(for: inspectedImage?.id == image.id ? (inspectedImage ?? image) : image)
                    .frame(minWidth: 420, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NordicEmptyState(
                    icon: .images,
                    title: "Select an Image",
                    description: "Choose an image from the list to inspect its OCI manifest, architecture variants, default entrypoint, environment, and layer history."
                )
                .frame(minWidth: 420, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                .background(NordicTheme.contentSurface)
            }
        }
        .background(NordicTheme.windowBackground)
        .onAppear {
            if appState.selectedImageID == nil || !filteredImages.contains(where: { $0.id == appState.selectedImageID }) {
                appState.selectedImageID = filteredImages.first?.id
            }
        }
        .onChange(of: appState.images.count) { _, _ in
            if appState.selectedImageID == nil || !filteredImages.contains(where: { $0.id == appState.selectedImageID }) {
                appState.selectedImageID = filteredImages.first?.id
            }
        }
        .sheet(isPresented: $appState.showPullImageSheet) {
            pullImageSheet
        }
        .sheet(item: $showTagSheetFor) { image in
            tagImageSheet(for: image)
        }
        .confirmationDialog(
            "Delete Image '\(imagePendingDeletion?.fullReference ?? "")'?",
            isPresented: Binding(
                get: { imagePendingDeletion != nil },
                set: { if !$0 { imagePendingDeletion = nil } }
            ),
            presenting: imagePendingDeletion
        ) { target in
            let usingContainers = containersReferencing(target)
            Button(usingContainers.isEmpty ? "Delete Image" : "Force Delete Referenced Image", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Images",
                        title: "Delete Image \(target.fullReference)",
                        redactedCommand: "container image delete \(usingContainers.isEmpty ? "" : "--force ")\(target.fullReference)"
                    ) {
                        try await appState.runtimeService.deleteImage(reference: target.fullReference, force: !usingContainers.isEmpty)
                        return "Deleted image '\(target.fullReference)'."
                    }
                    if appState.selectedImageID == target.id {
                        appState.selectedImageID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            let usingContainers = containersReferencing(target)
            if usingContainers.isEmpty {
                Text("Are you sure you want to delete '\(target.fullReference)' (\(target.shortDigest)) from your local store?")
            } else {
                Text("Warning: \(usingContainers.count) container(s) currently reference this image (\(usingContainers.map(\.id).joined(separator: ", "))).")
            }
        }
        .confirmationDialog("Prune Unreferenced Images?", isPresented: $confirmPruneUnused) {
            Button("Prune Unused Images", role: .destructive) {
                Task {
                    await appState.performOperation(
                        category: "Images",
                        title: "Prune Unreferenced Images",
                        redactedCommand: "container image prune -a"
                    ) {
                        try await appState.runtimeService.pruneImages(allUnused: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs `container image prune -a` and removes all local images not referenced by any container.")
        }
        .onChange(of: appState.selectedImageID) { _, newValue in
            guard let id = newValue, let img = appState.images.first(where: { $0.id == id }) else {
                inspectedImage = nil
                return
            }
            Task {
                inspectedImage = try? await appState.runtimeService.inspectImage(reference: img.fullReference)
            }
        }
    }

    private var headerToolbar: some View {
        HStack(spacing: 12) {
            Text(verbatim: "Images (\(filteredImages.count))")
                .font(NordicTheme.subtitleFont)
                .foregroundStyle(NordicTheme.primaryText)
            Spacer()
            Button {
                loadTarArchive()
            } label: {
                Label("Load Archive…", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)

            Button {
                confirmPruneUnused = true
            } label: {
                Label("Prune Unused", systemImage: "sparkles")
            }
            .controlSize(.small)
            .disabled(appState.images.isEmpty)

            Button {
                appState.showPullImageSheet = true
            } label: {
                Label("Pull Image", systemImage: "arrow.down.to.line")
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

    private var imageTable: some View {
        Table(filteredImages, selection: $appState.selectedImageID) {
            TableColumn("Repository") { img in
                HStack(spacing: 8) {
                    LadaIcon(.images, size: 15)
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    Text(img.repository)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                }
            }
            .width(min: 150, ideal: 210)

            TableColumn("Tag") { img in
                Text(img.tag)
                    .font(NordicTheme.monoFontSmall)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(NordicTheme.elevatedSurface))
            }
            .width(min: 70, ideal: 95)

            TableColumn("Digest") { img in
                Text(img.shortDigest)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 95, ideal: 120)

            TableColumn("Size") { img in
                Text(ByteCountFormatter.string(fromByteCount: img.totalSizeBytes, countStyle: .file))
                    .font(NordicTheme.monoFontSmall)
            }
            .width(min: 80, ideal: 95)

            TableColumn("Platforms") { img in
                Text(img.architecturesSummary)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            .width(min: 95, ideal: 120)

            TableColumn("In Use") { img in
                let count = containersReferencing(img).count
                if count > 0 {
                    NordicStatusBadge(label: "\(count) container\(count == 1 ? "" : "s")", tone: .positive)
                } else {
                    Text("Unused")
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            .width(min: 85, ideal: 105)

            TableColumn("Actions") { img in
                HStack(spacing: 6) {
                    Button {
                        appState.createContainerInitialRequest = ContainerCreateRequest(
                            imageReference: img.fullReference,
                            cpus: appState.preferences.defaultContainerCPUs,
                            memoryMB: appState.preferences.defaultContainerMemoryMB
                        )
                        appState.showCreateContainerSheet = true
                    } label: {
                        Image(systemName: "play.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Create Container from \(img.fullReference)")

                    Menu {
                        Button("Run Container from Image…") {
                            appState.createContainerInitialRequest = ContainerCreateRequest(
                                imageReference: img.fullReference,
                                cpus: appState.preferences.defaultContainerCPUs,
                                memoryMB: appState.preferences.defaultContainerMemoryMB
                            )
                            appState.showCreateContainerSheet = true
                        }
                        Button("Tag Image…") {
                            newTagInput = "\(img.repository):v2"
                            showTagSheetFor = img
                        }
                        Button("Push Image to Registry") {
                            Task {
                                await appState.performOperation(
                                    category: "Images",
                                    title: "Push Image \(img.fullReference)",
                                    redactedCommand: "container image push \(img.fullReference)"
                                ) {
                                    try await appState.runtimeService.pushImage(
                                        reference: img.fullReference,
                                        platform: nil,
                                        scheme: "https",
                                        onProgressLine: { _ in }
                                    )
                                    return "Pushed '\(img.fullReference)'."
                                }
                            }
                        }
                        Button("Save as Tar Archive…") {
                            saveTarArchive(for: img)
                        }
                        Divider()
                        Button("Copy Reference") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(img.fullReference, forType: .string)
                        }
                        Button("Copy Digest") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(img.digest, forType: .string)
                        }
                        Divider()
                        Button("Delete Image…", role: .destructive) {
                            imagePendingDeletion = img
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
            }
            .width(min: 65, ideal: 75)
        }
        .accessibilityIdentifier(AccessibilityID.imageTable)
    }

    private func imageInspector(for image: ImageModel) -> some View {
        VStack(spacing: 0) {
            NordicDetailHeader(
                title: image.fullReference,
                subtitle: image.digest,
                badge: NordicStatusBadge(label: image.architecturesSummary, tone: .accent, showDot: false)
            ) {
                Button {
                    appState.createContainerInitialRequest = ContainerCreateRequest(
                        imageReference: image.fullReference,
                        cpus: appState.preferences.defaultContainerCPUs,
                        memoryMB: appState.preferences.defaultContainerMemoryMB
                    )
                    appState.showCreateContainerSheet = true
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .controlSize(.small)

                Button {
                    newTagInput = "\(image.repository):v2"
                    showTagSheetFor = image
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    imagePendingDeletion = image
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        NordicSectionHeader("Image Manifest Summary")
                        LabeledContent("Repository", value: image.repository)
                        LabeledContent("Tag", value: image.tag)
                        LabeledContent("Registry Origin", value: image.registryOrigin)
                        LabeledContent("Media Type", value: image.mediaType)
                            .font(NordicTheme.monoFontSmall)
                        LabeledContent("Total Size", value: ByteCountFormatter.string(fromByteCount: image.totalSizeBytes, countStyle: .file))
                        LabeledContent("Created", value: image.creationDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding(14)
                    .background(NordicTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))

                    ForEach(image.variants) { variant in
                        VStack(alignment: .leading, spacing: 8) {
                            NordicSectionHeader(
                                "Variant: \(variant.platformString)",
                                trailingText: ByteCountFormatter.string(fromByteCount: variant.sizeBytes, countStyle: .file)
                            )
                            if let ep = variant.entrypoint, !ep.isEmpty {
                                LabeledContent("Entrypoint", value: ep.joined(separator: " "))
                                    .font(NordicTheme.monoFontSmall)
                            }
                            if let cmd = variant.cmd, !cmd.isEmpty {
                                LabeledContent("Default Cmd", value: cmd.joined(separator: " "))
                                    .font(NordicTheme.monoFontSmall)
                            }
                            if let wd = variant.workingDir, !wd.isEmpty {
                                LabeledContent("Working Dir", value: wd)
                                    .font(NordicTheme.monoFontSmall)
                            }
                            if let usr = variant.user, !usr.isEmpty {
                                LabeledContent("User", value: usr)
                                    .font(NordicTheme.monoFontSmall)
                            }
                            if let envList = variant.env, !envList.isEmpty {
                                Divider()
                                Text("Default Environment")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                ForEach(envList, id: \.self) { env in
                                    Text(SecretRedactor.redact(env))
                                        .font(NordicTheme.monoFontSmall)
                                        .textSelection(.enabled)
                                }
                            }
                            if !variant.history.isEmpty {
                                Divider()
                                Text("Layer History (\(variant.history.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                ForEach(variant.history) { layer in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(layer.createdBy ?? "(layer)")
                                            .font(NordicTheme.monoFontSmall)
                                            .lineLimit(2)
                                        if let c = layer.created {
                                            Text(c)
                                                .font(.system(size: 10))
                                                .foregroundStyle(NordicTheme.secondaryText)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(14)
                        .background(NordicTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
                    }
                }
                .padding(16)
            }
        }
        .background(NordicTheme.contentSurface)
    }

    private var pullImageSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                LadaIcon(.images, size: 22)
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pull Container Image")
                        .font(NordicTheme.titleFont)
                    Text("Fetch an OCI image from Docker Hub, GHCR, or a custom registry.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                Spacer()
            }

            Form {
                TextField("Image Reference (e.g. docker.io/library/alpine:latest)", text: $pullImageRef)
                    .font(NordicTheme.monoFontRegular)
                TextField("Platform Override (optional, e.g. linux/arm64)", text: $pullPlatform)
                    .font(NordicTheme.monoFontRegular)
                Picker("Transport Scheme", selection: $pullScheme) {
                    Text("HTTPS").tag("https")
                    Text("HTTP (Insecure)").tag("http")
                }
            }
            .formStyle(.grouped)

            let req = ImagePullRequest(
                reference: pullImageRef.trimmingCharacters(in: .whitespacesAndNewlines),
                platform: pullPlatform.trimmingCharacters(in: .whitespacesAndNewlines),
                scheme: pullScheme
            )

            Text(SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments()))
                .font(NordicTheme.monoFontSmall)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if !pullProgressLines.isEmpty || isPulling {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(pullProgressLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(NordicTheme.monoFontSmall)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 110)
                .background(NordicTheme.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack {
                Button("Cancel") {
                    appState.showPullImageSheet = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isPulling ? "Pulling…" : "Pull Image") {
                    isPulling = true
                    pullProgressLines = []
                    Task {
                        await appState.performOperation(
                            category: "Images",
                            title: "Pull Image \(req.reference)",
                            redactedCommand: SecretRedactor.formatCommandPreview(executable: "container", arguments: req.buildCLIArguments())
                        ) {
                            try await appState.runtimeService.pullImage(request: req) { line in
                                Task { @MainActor in
                                    pullProgressLines.append(line)
                                }
                            }
                            return "Pulled image '\(req.reference)'."
                        }
                        isPulling = false
                        if appState.activeError == nil {
                            appState.showPullImageSheet = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(req.reference.isEmpty || isPulling)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func tagImageSheet(for image: ImageModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tag Image")
                .font(NordicTheme.titleFont)
            Text("Create a new tag pointing to \(image.fullReference)")
                .font(.system(size: 12))
                .foregroundStyle(NordicTheme.secondaryText)

            TextField("Target Tag (e.g. local/myapp:v1.0)", text: $newTagInput)
                .textFieldStyle(.roundedBorder)
                .font(NordicTheme.monoFontRegular)

            HStack {
                Button("Cancel") { showTagSheetFor = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Tag") {
                    let target = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    showTagSheetFor = nil
                    Task {
                        await appState.performOperation(
                            category: "Images",
                            title: "Tag Image \(image.fullReference) -> \(target)",
                            redactedCommand: "container image tag \(image.fullReference) \(target)"
                        ) {
                            try await appState.runtimeService.tagImage(source: image.fullReference, target: target)
                            return "Tagged '\(image.fullReference)' as '\(target)'."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func saveTarArchive(for image: ImageModel) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(image.repository.replacingOccurrences(of: "/", with: "_"))-\(image.tag).tar"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await appState.performOperation(
                    category: "Images",
                    title: "Save Image Archive \(url.lastPathComponent)",
                    redactedCommand: "container image save -o \(url.path) \(image.fullReference)"
                ) {
                    try await appState.runtimeService.saveImage(reference: image.fullReference, outputPath: url.path, platform: nil)
                    return "Saved archive to \(url.path)."
                }
            }
        }
    }

    private func loadTarArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await appState.performOperation(
                    category: "Images",
                    title: "Load Image Archive \(url.lastPathComponent)",
                    redactedCommand: "container image load -i \(url.path)"
                ) {
                    try await appState.runtimeService.loadImage(inputPath: url.path, force: false)
                    return "Loaded image archive from \(url.path)."
                }
            }
        }
    }
}
