import SwiftUI

/// The containers of one stack, grouped in the Containers list.
public struct ContainerStackGroup: Equatable, Sendable {
    public let name: String
    public let members: [ContainerModel]
    public var runningCount: Int { members.filter { $0.state == .running }.count }
}

/// A row in the Containers list: a single container, or a collapsible stack group.
public enum ContainerListRow: Identifiable, Equatable, Sendable {
    case container(ContainerModel)
    case stack(ContainerStackGroup)

    static let stackPrefix = "stack:"

    /// A container's own ID, or `stack:<name>` (selection uses the same IDs).
    public var id: String {
        switch self {
        case .container(let c): return c.id
        case .stack(let g): return Self.stackPrefix + g.name
        }
    }

    public var container: ContainerModel? {
        if case .container(let c) = self { return c }
        return nil
    }

    // Sort keys for the table columns.
    public var sortName: String {
        switch self {
        case .container(let c): return c.id
        case .stack(let g): return g.name
        }
    }

    public var sortState: String {
        switch self {
        case .container(let c): return c.rawState
        case .stack(let g): return g.runningCount > 0 ? "running" : "stopped"
        }
    }

    public var sortImage: String {
        switch self {
        case .container(let c): return c.shortImageReference
        case .stack(let g): return "\(g.members.count) containers"
        }
    }
}

/// Shown in the inspector when a stack row is selected in the Containers list.
struct StackGroupSummaryView: View {
    @ObservedObject var appState: AppState
    let group: ContainerStackGroup

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }
    private var isOpenInStacks: Bool { !appState.stacks.isEmpty && appState.stacks.parsed.projectName == group.name }

    var body: some View {
        VStack(spacing: 0) {
            NordicDetailHeader(
                title: group.name,
                subtitle: "Stack · \(group.runningCount) of \(group.members.count) containers running",
                badge: NordicStatusBadge(
                    label: group.runningCount == group.members.count ? "Running" : (group.runningCount > 0 ? "Partly running" : "Stopped"),
                    tone: group.runningCount == group.members.count ? .positive : (group.runningCount > 0 ? .warning : .neutral)
                )
            ) {
                if group.runningCount < group.members.count {
                    Button {
                        Task { await Self.startAll(group, appState: appState) }
                    } label: {
                        Label("Start All", systemImage: "play.fill")
                    }
                    .controlSize(.small)
                }
                if group.runningCount > 0 {
                    Button {
                        Task { await Self.stopAll(group, appState: appState) }
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                    }
                    .controlSize(.small)
                }
                Button {
                    if !isOpenInStacks { appState.stacks.reopen(stack: group.name) }
                    appState.selectedSection = .stacks
                } label: {
                    Label("Open in Stacks", systemImage: "square.stack.3d.up")
                }
                .controlSize(.small)
                .disabled(!isOpenInStacks && appState.stacks.deployedCompose(for: group.name) == nil)
                .help(isOpenInStacks || appState.stacks.deployedCompose(for: group.name) != nil
                      ? "Open this stack's compose file in Stacks to edit it"
                      : "This stack was not started from this Mac's Stacks screen, so its compose file is unknown")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: NordicTheme.Spacing.s) {
                    Text("Containers in this stack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NordicTheme.secondaryText)
                    ForEach(group.members) { member in
                        Button {
                            appState.selectedContainerID = member.id
                        } label: {
                            HStack(spacing: NordicTheme.Spacing.s) {
                                LadaIcon(.containers, size: 14)
                                    .foregroundStyle(member.state == .running ? NordicTheme.statusGreen : NordicTheme.secondaryText)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.configuration.labels["com.lada.compose.service"] ?? member.id)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(NordicTheme.primaryText)
                                    Text("\(member.shortImageReference) · container \(member.id)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(NordicTheme.secondaryText)
                                }
                                Spacer()
                                NordicStatusBadge(containerState: member.state)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(NordicTheme.secondaryText)
                            }
                            .padding(NordicTheme.Spacing.m)
                            .nordicSurface()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Inspect \(member.id)")
                    }
                }
                .padding(NordicTheme.Spacing.l)
            }
        }
        .background(Color.clear)
    }

    static func startAll(_ group: ContainerStackGroup, appState: AppState) async {
        for member in group.members where member.state != .running {
            await appState.startContainerWithVerification(id: member.id)
        }
    }

    static func stopAll(_ group: ContainerStackGroup, appState: AppState) async {
        await appState.performOperation(
            category: "Containers",
            title: "Stop stack \(group.name)",
            redactedCommand: "container stop \(group.members.map(\.id).joined(separator: " "))"
        ) {
            for member in group.members where member.state == .running {
                try await appState.runtimeService.stopContainer(id: member.id, timeoutSeconds: 5)
            }
            return "Stopped stack '\(group.name)'."
        }
    }
}
