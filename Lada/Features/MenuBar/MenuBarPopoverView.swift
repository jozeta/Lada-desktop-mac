import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState) {
        self.appState = appState
    }

    private var runningContainersCount: Int {
        appState.containers.filter { $0.state == .running }.count
    }

    private var latestSystemTelemetry: ContainerPerformanceSample? {
        appState.systemTelemetryHistory.last
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                LadaIcon(.appIdentity, size: 18)
                    .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Låda")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text(verbatim: "\(runningContainersCount) of \(appState.containers.count) containers running")
                        .font(.system(size: 10))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                Spacer()
                NordicStatusBadge(
                    label: appState.systemStatus.state.displayTitle,
                    tone: appState.systemStatus.state == .running ? .positive : .neutral
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NordicTheme.elevatedSurface)

            Divider().overlay(NordicTheme.borderSubtle)

            // Live Telemetry Strip
            if let sample = latestSystemTelemetry, runningContainersCount > 0 {
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                            .foregroundStyle(NordicTheme.accent(for: appState.preferences.accentThemeChoice))
                        Text(String(format: "CPU %.1f%%", sample.cpuPercent))
                            .font(NordicTheme.monoFontSmall)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10))
                            .foregroundStyle(NordicTheme.statusGreen)
                        Text(verbatim: "RAM \(ByteCountFormatter.string(fromByteCount: Int64(sample.memoryUsageBytes), countStyle: .memory))")
                            .font(NordicTheme.monoFontSmall)
                    }
                    Spacer()
                    Button {
                        Task { await appState.refreshAll(isUserInitiated: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Now")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(NordicTheme.surfaceBackground)

                Divider().overlay(NordicTheme.borderSubtle)
            }

            // Containers List
            if appState.containers.isEmpty {
                VStack(spacing: 6) {
                    Text("No containers created")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sortedContainers) { container in
                            menuBarContainerRow(container)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 280)
            }

            Divider().overlay(NordicTheme.borderSubtle)

            // Quick Actions Footer
            HStack(spacing: 8) {
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    appState.createContainerInitialRequest = nil
                    appState.showCreateContainerSheet = true
                } label: {
                    Label("New Container", systemImage: "plus")
                }
                .controlSize(.small)

                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    appState.selectedSection = .stacks
                } label: {
                    Label("Stacks", systemImage: "square.stack.3d.up")
                }
                .controlSize(.small)

                Spacer()

                Button("Open Låda") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    for window in NSApplication.shared.windows where window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .controlSize(.small)
                .help("Quit Låda")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NordicTheme.elevatedSurface)
        }
        .frame(width: 360)
        .background(NordicTheme.windowBackground)
    }

    private var sortedContainers: [ContainerModel] {
        appState.containers.sorted { a, b in
            if (a.state == .running) != (b.state == .running) {
                return a.state == .running
            }
            return a.id < b.id
        }
    }

    private func menuBarContainerRow(_ container: ContainerModel) -> some View {
        let isRunning = container.state == .running
        let firstPort = container.configuration.publishedPorts.first
        let probe = firstPort.flatMap { appState.portHealthMap[$0.hostPort] }

        return HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? NordicTheme.statusGreen : NordicTheme.secondaryText.opacity(0.45))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(container.id)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                        .lineLimit(1)

                    if let firstPort {
                        HStack(spacing: 3) {
                            if isRunning {
                                Circle()
                                    .fill(
                                        (probe?.state == .healthyHTTP || probe?.state == .listeningTCP)
                                            ? NordicTheme.statusGreen
                                            : NordicTheme.statusAmber
                                    )
                                    .frame(width: 5, height: 5)
                            }
                            Text(verbatim: ":\(firstPort.hostPort)")
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                Text(container.imageReference)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if isRunning, let firstPort {
                Button {
                    if let url = URL(string: "http://localhost:\(firstPort.hostPort)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .controlSize(.small)
                .help("Open http://localhost:\(firstPort.hostPort) in Browser")
            }

            if isRunning {
                Button {
                    appState.openExternalTerminalForContainer(id: container.id)
                } label: {
                    Image(systemName: "apple.terminal")
                }
                .controlSize(.small)
                .help("Open Shell in Terminal.app")

                Button {
                    Task {
                        try? await appState.runtimeService.stopContainer(id: container.id, timeoutSeconds: 5)
                        await appState.refreshAll(isUserInitiated: false)
                    }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .controlSize(.small)
                .help("Stop Container")
            } else {
                Button {
                    Task {
                        await appState.startContainerWithVerification(id: container.id)
                    }
                } label: {
                    Image(systemName: "play.fill")
                }
                .controlSize(.small)
                .tint(NordicTheme.statusGreen)
                .help("Start Container")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(NordicTheme.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
        )
    }
}
