import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ContainerFileEntry: Identifiable, Equatable, Sendable {
    public var id: String { fullPath }
    public let name: String
    public let fullPath: String
    public let permissions: String
    public let owner: String
    public let sizeBytes: Int64
    public let modifiedText: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let symlinkTarget: String?

    public var formattedSize: String {
        if isDirectory { return "—" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct ContainerFileBrowserView: View {
    @ObservedObject var appState: AppState
    public let container: ContainerModel

    @State private var currentPath: String = "/"
    @State private var entries: [ContainerFileEntry] = []
    @State private var selectedEntryID: String? = nil
    @State private var isLoadingDirectory: Bool = false
    @State private var directoryError: String? = nil

    // File Editor / Preview state
    @State private var previewingEntry: ContainerFileEntry? = nil
    @State private var fileEditorText: String = ""
    /// Set when the selected file can't be edited (too large or binary); the editor is hidden.
    @State private var editorNotice: String? = nil
    @State private var isSavingFile: Bool = false
    @State private var fileStatusBanner: String? = nil
    @State private var isFileDropTargeted: Bool = false
    @State private var showNewFolderSheet: Bool = false
    @State private var newFolderName: String = ""

    public init(appState: AppState, container: ContainerModel) {
        self.appState = appState
        self.container = container
    }

    private var breadcrumbSegments: [(label: String, path: String)] {
        let trimmed = currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty {
            return [("/", "/")]
        }
        var result: [(String, String)] = [("/", "/")]
        var running = ""
        for comp in trimmed.split(separator: "/").map(String.init) {
            running += "/\(comp)"
            result.append((comp, running))
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider().overlay(NordicTheme.borderSubtle)

            if container.state != .running {
                NordicEmptyState(
                    icon: .volumes,
                    title: "Container Is Not Running",
                    description: "Start '\(container.id)' to browse, edit, upload, or download files inside the container filesystem."
                )
            } else {
                HSplitView {
                    // Left: Directory Listing Table
                    directoryListPane
                        .frame(minWidth: 320, idealWidth: 390)

                    // Right: In-Place File Preview & Editor
                    fileInspectorPane
                        .frame(minWidth: 300, idealWidth: 380)
                }
            }
        }
        .background(NordicTheme.windowBackground)
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
            handleDroppedHostFiles(providers: providers)
        }
        .overlay {
            if isFileDropTargeted && container.state == .running {
                ZStack {
                    Color.black.opacity(0.38)
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        Text("Drop File to Upload into \(currentPath)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(NordicTheme.primaryText)
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 12).fill(NordicTheme.elevatedSurface))
                }
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            newFolderSheetView
        }
        .task(id: "\(container.id)-\(container.state.rawValue)") {
            if container.state == .running {
                await loadDirectory(path: currentPath)
            }
        }
    }

    // MARK: - Browser Toolbar

    private var browserToolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    navigateUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .controlSize(.small)
                .disabled(currentPath == "/" || container.state != .running)
                .help("Go to Parent Directory")

                // Breadcrumbs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(breadcrumbSegments.enumerated()), id: \.offset) { idx, seg in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                            Button(seg.label) {
                                Task { await loadDirectory(path: seg.path) }
                            }
                            .buttonStyle(.plain)
                            .font(NordicTheme.monoFontSmall)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(seg.path == currentPath ? Color.primary.opacity(0.12) : Color.clear)
                            )
                        }
                    }
                }

                Spacer()

                if let fileStatusBanner {
                    Text(fileStatusBanner)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NordicTheme.statusGreen)
                        .lineLimit(1)
                }

                Button {
                    newFolderName = ""
                    showNewFolderSheet = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
                .disabled(container.state != .running)
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    uploadFileViaOpenPanel()
                } label: {
                    Label("Upload File…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                .disabled(container.state != .running)
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    Task { await loadDirectory(path: currentPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(container.state != .running)
                .help("Refresh Directory")
            }

            // Quick Jump Bar
            HStack(spacing: 6) {
                Text("Quick Jump:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NordicTheme.secondaryText)
                ForEach(["/", "/etc", "/var/log", "/usr/share/nginx/html", "/app", "/tmp"], id: \.self) { preset in
                    Button(preset) {
                        Task { await loadDirectory(path: preset) }
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .disabled(container.state != .running)
                }
                Spacer()
                Text(verbatim: "\(entries.count) items")
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(NordicTheme.elevatedSurface)
    }

    // MARK: - Directory List Pane

    private var directoryListPane: some View {
        VStack(spacing: 0) {
            if isLoadingDirectory {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Listing \(currentPath)…")
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let directoryError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(NordicTheme.statusAmber)
                    Text(directoryError)
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Button("Return to /") {
                        Task { await loadDirectory(path: "/") }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedEntryID) {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder.fill" : (entry.isSymlink ? "arrow.turn.down.right" : "doc.text"))
                                .foregroundStyle(
                                    entry.isDirectory
                                        ? NordicTheme.accent(for: appState.preferences.accentThemeChoice)
                                        : NordicTheme.secondaryText
                                )
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name)
                                    .font(.system(size: 12, weight: entry.isDirectory ? .semibold : .regular))
                                    .foregroundStyle(NordicTheme.primaryText)
                                    .lineLimit(1)
                                Text(verbatim: "\(entry.permissions) • \(entry.owner) • \(entry.modifiedText)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(entry.formattedSize)
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .tag(entry.id)
                        .onTapGesture(count: 2) {
                            handleDoubleClick(on: entry)
                        }
                        .onTapGesture(count: 1) {
                            selectedEntryID = entry.id
                            handleSingleClick(on: entry)
                        }
                        .contextMenu {
                            if entry.isDirectory {
                                Button("Open Folder") {
                                    Task { await loadDirectory(path: entry.fullPath) }
                                }
                            } else {
                                Button("Preview / Edit File") {
                                    Task { await loadFileContent(for: entry) }
                                }
                                Button("Download to Mac…") {
                                    Task { await downloadFileToMac(entry: entry) }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                Task { await deleteEntry(entry) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Right File Inspector / Editor

    private var fileInspectorPane: some View {
        VStack(spacing: 0) {
            if let entry = previewingEntry {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NordicTheme.primaryText)
                            .lineLimit(1)
                        Text(entry.fullPath)
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()

                    Button {
                        Task { await downloadFileToMac(entry: entry) }
                    } label: {
                        Label("Download…", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)

                    Button {
                        Task { await saveEditedFileContent(for: entry) }
                    } label: {
                        if isSavingFile {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Save to Container", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSavingFile || editorNotice != nil)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NordicTheme.elevatedSurface)
                .overlay(alignment: .bottom) {
                    Divider().overlay(NordicTheme.borderSubtle)
                }

                if let editorNotice {
                    Text(editorNotice)
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                        .background(NordicTheme.codeSurface)
                        .accessibilityIdentifier(AccessibilityID.filesEditorNotice)
                } else {
                    TextEditor(text: $fileEditorText)
                        .font(NordicTheme.monoFontRegular)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(NordicTheme.codeSurface)
                }
            } else {
                NordicEmptyState(
                    icon: .dockerfileEditor,
                    title: "Select a File to Inspect or Edit",
                    description: "Single-click any file to view and edit its contents in place, double-click a folder to navigate inside, or drag files from Finder to upload."
                )
            }
        }
        .background(NordicTheme.surfaceBackground)
    }

    private var newFolderSheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create New Directory in \(currentPath)")
                .font(.system(size: 14, weight: .semibold))
            TextField("Folder name (e.g. config)", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Spacer()
                Button("Cancel") { showNewFolderSheet = false }
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    showNewFolderSheet = false
                    guard !name.isEmpty else { return }
                    Task { await createNewDirectory(named: name) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Filesystem Operations via `container exec`

    private func navigateUp() {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        Task { await loadDirectory(path: parent.isEmpty ? "/" : parent) }
    }

    private func handleSingleClick(on entry: ContainerFileEntry) {
        if !entry.isDirectory {
            Task { await loadFileContent(for: entry) }
        }
    }

    private func handleDoubleClick(on entry: ContainerFileEntry) {
        if entry.isDirectory {
            previewingEntry = nil
            Task { await loadDirectory(path: entry.fullPath) }
        } else {
            Task { await loadFileContent(for: entry) }
        }
    }

    private var fileOps: ContainerFileOperations {
        ContainerFileOperations(runtime: appState.runtimeService, containerID: container.id)
    }

    private func loadDirectory(path: String) async {
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }

        let normalizedPath = path.isEmpty ? "/" : path
        do {
            entries = try await fileOps.listDirectory(normalizedPath)
            currentPath = normalizedPath
        } catch {
            directoryError = Self.message(for: error)
        }
    }

    private func loadFileContent(for entry: ContainerFileEntry) async {
        do {
            switch try await fileOps.loadText(entry) {
            case .text(let text):
                editorNotice = nil
                fileEditorText = text
            case .tooLarge(let bytes):
                editorNotice = "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) is too large to edit here (limit \(ByteCountFormatter.string(fromByteCount: ContainerFileOperations.maxEditableBytes, countStyle: .file))). Use Download… instead."
                fileEditorText = ""
            case .binary:
                editorNotice = "This looks like a binary file, so it can't be edited as text. Use Download… instead."
                fileEditorText = ""
            }
            previewingEntry = entry
        } catch {
            showBanner("Failed to read \(entry.name): \(Self.message(for: error))")
        }
    }

    private func saveEditedFileContent(for entry: ContainerFileEntry) async {
        guard editorNotice == nil else { return }
        isSavingFile = true
        defer { isSavingFile = false }
        do {
            try await fileOps.saveText(fileEditorText, to: entry.fullPath)
            showBanner("Saved \(entry.name)")
            await loadDirectory(path: currentPath)
        } catch {
            showBanner("Save failed: \(Self.message(for: error))")
        }
    }

    private func downloadFileToMac(entry: ContainerFileEntry) async {
        let panel = NSSavePanel()
        panel.title = "Save '\(entry.name)' to Mac"
        panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        do {
            try await fileOps.download(entry.fullPath, to: destURL)
            showBanner("Downloaded \(entry.name)")
        } catch {
            showBanner("Download failed: \(Self.message(for: error))")
        }
    }

    private func createNewDirectory(named folderName: String) async {
        do {
            try await fileOps.makeDirectory(named: folderName, in: currentPath)
            showBanner("Created folder \(folderName)")
        } catch {
            showBanner("Create folder failed: \(Self.message(for: error))")
        }
        await loadDirectory(path: currentPath)
    }

    private func deleteEntry(_ entry: ContainerFileEntry) async {
        do {
            try await fileOps.remove(entry.fullPath)
            if previewingEntry?.id == entry.id {
                previewingEntry = nil
            }
            showBanner("Deleted \(entry.name)")
        } catch {
            showBanner("Delete failed: \(Self.message(for: error))")
        }
        await loadDirectory(path: currentPath)
    }

    private static func message(for error: Error) -> String {
        if let lada = error as? LadaError {
            let detail = lada.diagnosticOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty ? lada.explanation : "\(lada.explanation) \(detail)"
        }
        return error.localizedDescription
    }

    private func uploadFileViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Upload File to Container (\(currentPath))"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                for url in urls {
                    await uploadHostFile(url: url)
                }
                await loadDirectory(path: currentPath)
            }
        }
    }

    private func handleDroppedHostFiles(providers: [NSItemProvider]) -> Bool {
        guard container.state == .running else { return false }
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await uploadHostFile(url: url)
                    await loadDirectory(path: currentPath)
                }
            }
        }
        return handled
    }

    private func uploadHostFile(url: URL) async {
        do {
            try await fileOps.upload(url, into: currentPath)
            showBanner("Uploaded \(url.lastPathComponent)")
        } catch {
            showBanner("Upload of \(url.lastPathComponent) failed: \(Self.message(for: error))")
        }
    }

    private func showBanner(_ text: String) {
        fileStatusBanner = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.fileStatusBanner == text {
                self.fileStatusBanner = nil
            }
        }
    }
}
