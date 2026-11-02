import Foundation

/// What you were doing in one container's inspector: kept in `AppState`, so it survives switching
/// to another container and leaving the Containers section, until the container goes away.
@MainActor
public final class ContainerWorkspace: ObservableObject {
    public let containerID: String
    @Published public var tab: ContainerDetailView.DetailTab
    /// The shell keeps running while you look elsewhere; its screen and scrollback stay intact.
    public let terminal = PTYTerminalSession()
    public let files = ContainerFilesState()
    public let logs = ContainerLogsState()

    init(containerID: String, tab: ContainerDetailView.DetailTab) {
        self.containerID = containerID
        self.tab = tab
    }

    func close() {
        terminal.terminateSession()
    }
}

/// Files tab state, including unsaved edits in the editor.
@MainActor
public final class ContainerFilesState: ObservableObject {
    @Published public var currentPath = "/"
    @Published public var entries: [ContainerFileEntry] = []
    @Published public var selectedEntryID: String?
    @Published public var previewingEntry: ContainerFileEntry?
    @Published public var fileEditorText = ""
    @Published public var editorNotice: String?
}

/// Logs tab state. `text` is the last fetch, shown at once when you come back.
@MainActor
public final class ContainerLogsState: ObservableObject {
    @Published public var text = ""
    @Published public var showBootLogs = false
    @Published public var searchText = ""
    @Published public var isPaused = false
    @Published public var autoScroll = true
}

/// Per-container workspaces. A container you open for the first time starts on the tab you used
/// last; workspaces of deleted or stopped containers are closed (their shell ends).
@MainActor
public final class ContainerWorkspaceStore: ObservableObject {
    private var workspaces: [String: ContainerWorkspace] = [:]
    private(set) var lastUsedTab: ContainerDetailView.DetailTab = .overview

    public init() {}

    public func workspace(for containerID: String) -> ContainerWorkspace {
        if let existing = workspaces[containerID] { return existing }
        let ws = ContainerWorkspace(containerID: containerID, tab: lastUsedTab)
        workspaces[containerID] = ws
        return ws
    }

    public func select(_ tab: ContainerDetailView.DetailTab, for containerID: String) {
        workspace(for: containerID).tab = tab
        lastUsedTab = tab
    }

    public var openContainerIDs: Set<String> { Set(workspaces.keys) }

    /// Drops workspaces for containers that no longer exist and ends shells in stopped ones
    /// (the rest of a stopped container's workspace is kept).
    public func reconcile(with containers: [ContainerModel]) {
        let byID = Dictionary(containers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, ws) in workspaces {
            guard let container = byID[id] else {
                ws.close()
                workspaces[id] = nil
                continue
            }
            if container.state != .running && ws.terminal.isRunning {
                ws.terminal.terminateSession()
            }
        }
    }
}
