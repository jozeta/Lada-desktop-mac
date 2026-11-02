import Foundation

/// The Stacks screen's compose file and activity, kept in `AppState` so edits survive leaving the
/// screen.
@MainActor
public final class StackWorkspace: ObservableObject {
    public enum Tab: String, CaseIterable, Identifiable {
        case services = "Services"
        case file = "Compose File"
        case logs = "Logs"
        public var id: String { rawValue }
    }

    @Published public var yamlText: String = ComposeStackTemplate.allTemplates[0].instantiate()
    @Published public var currentFileURL: URL?
    @Published public var isDeploying = false
    @Published public var consoleLines: [String] = []
    @Published public var tab: Tab = .services
    @Published public var logsText = ""
    @Published public var isLoadingLogs = false
    @Published public var logSearch = ""
    @Published public var logPaused = false
    @Published public var logAutoScroll = true

    /// The parsed compose file (re-parsed on every edit, so typed services appear at once).
    public var parsed: ParsedComposeStack { ComposeParser.parse(yaml: yamlText) }

    // MARK: Recent files

    private static let recentKey = "lada.stacks.recentFiles"

    /// Recently opened or saved compose files that still exist, newest first.
    public var recentFiles: [URL] {
        (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func noteRecent(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(8)), forKey: Self.recentKey)
        objectWillChange.send()
    }

    public func open(_ url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        currentFileURL = url
        yamlText = content
        noteRecent(url)
    }

    // MARK: Lifecycle

    /// Starts every service in dependency order (creating named volumes first).
    public func start(appState: AppState) async {
        isDeploying = true
        consoleLines = ["==> Deploying stack '\(parsed.projectName)' (\(parsed.services.count) services)…"]
        defer { isDeploying = false }

        // 1. Ensure declared named volumes exist
        let existingVolNames = Set(appState.volumes.map(\.name))
        for vol in parsed.declaredVolumes where !existingVolNames.contains(vol) {
            consoleLines.append("==> Creating named volume '\(vol)'…")
            try? await appState.runtimeService.createVolume(
                request: VolumeCreateRequest(name: vol, sizeSpec: "2G")
            )
        }

        // 2. Deploy each service in topological order
        for svc in parsed.topologicalServices {
            if let existing = appState.containers.first(where: { $0.id == svc.containerName }) {
                if existing.state == .running {
                    consoleLines.append("==> Service '\(svc.serviceName)' (\(svc.containerName)) is already running.")
                    continue
                } else {
                    consoleLines.append("==> Removing stopped container '\(svc.containerName)' before re-creating…")
                    try? await appState.runtimeService.deleteContainer(id: svc.containerName, force: true)
                }
            }

            // Give each service its name (plus Compose `aliases:`) as DNS aliases so peers can
            // reach it as e.g. `db`, the way Compose does.
            let dnsDomain = appState.systemProperties.dns.domain
            let resolved = ComposeParser.serviceDNSAliases(
                for: svc,
                defaultDNSDomain: dnsDomain,
                claimedNames: ComposeParser.claimedDNSNames(in: appState.containers, network: "default", defaultDNSDomain: dnsDomain, excluding: svc.containerName)
            )
            for note in resolved.notes {
                consoleLines.append("    ! \(note)")
            }
            let req = ComposeParser.buildContainerRequest(
                for: svc,
                projectName: parsed.projectName,
                networkName: "default",
                defaultCPUs: appState.preferences.defaultContainerCPUs,
                defaultMemoryMB: appState.preferences.defaultContainerMemoryMB,
                dnsAliases: resolved.aliases
            )
            if !resolved.aliases.isEmpty {
                consoleLines.append("    DNS aliases: \(resolved.aliases.joined(separator: ", "))")
            }

            consoleLines.append("==> Starting service '\(svc.serviceName)' (\(svc.imageReference))…")
            do {
                let id = try await appState.runtimeService.createOrRunContainer(request: req)
                consoleLines.append("    ✓ Started '\(id)'")
            } catch {
                consoleLines.append("    ✗ Failed to start '\(svc.serviceName)': \(error.localizedDescription)")
            }
        }

        await appState.refreshAll(isUserInitiated: false)
        consoleLines.append("==> Stack '\(parsed.projectName)' orchestration finished.")
        await refreshLogs(appState: appState)
    }

    /// Stops services in reverse dependency order; they keep their data.
    public func stop(appState: AppState) async {
        isDeploying = true
        consoleLines.append("==> Stopping stack '\(parsed.projectName)'…")
        defer { isDeploying = false }

        // Stop in reverse dependency order
        for svc in parsed.topologicalServices.reversed() {
            if appState.containers.first(where: { $0.id == svc.containerName })?.state == .running {
                consoleLines.append("==> Stopping '\(svc.containerName)'…")
                try? await appState.runtimeService.stopContainer(id: svc.containerName, timeoutSeconds: 5)
            }
        }
        await appState.refreshAll(isUserInitiated: false)
        consoleLines.append("==> Stack stopped.")
    }

    /// Deletes the stack's containers (named volumes are kept).
    public func remove(appState: AppState) async {
        isDeploying = true
        consoleLines.append("==> Deleting all containers in stack '\(parsed.projectName)'…")
        defer { isDeploying = false }

        for svc in parsed.topologicalServices.reversed() {
            if appState.containers.contains(where: { $0.id == svc.containerName }) {
                consoleLines.append("==> Deleting '\(svc.containerName)'…")
                try? await appState.runtimeService.deleteContainer(id: svc.containerName, force: true)
            }
        }
        await appState.refreshAll(isUserInitiated: false)
        consoleLines.append("==> Stack containers deleted.")
    }

    /// Recent log lines of every service, prefixed with the service name.
    public func refreshLogs(appState: AppState) async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        var combined: [String] = []
        for svc in parsed.topologicalServices {
            guard appState.containers.contains(where: { $0.id == svc.containerName }) else { continue }
            if let log = try? await appState.runtimeService.fetchContainerLogs(
                id: svc.containerName,
                bootLogs: false,
                tailLines: 60
            ) {
                let prefixed = log
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { "[\(svc.serviceName)] \($0)" }
                    .joined(separator: "\n")
                if !prefixed.isEmpty {
                    combined.append(prefixed)
                }
            }
        }
        logsText = combined.joined(separator: "\n")
    }

}
