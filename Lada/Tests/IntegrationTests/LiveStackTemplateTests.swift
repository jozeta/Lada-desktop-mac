import XCTest
@testable import Lada

/// Opt-in: starts every stack template on the real runtime through StackWorkspace (skipped unless
/// `LADA_LIVE_STACKS` is `all` or a comma-separated list of template IDs). Each stack is removed
/// afterwards with the volumes it created; images the test pulled are deleted at the end.
@MainActor
final class LiveStackTemplateTests: XCTestCase {
    func testTemplatesStartAndKeepRunning() async throws {
        guard let list = ProcessInfo.processInfo.environment["LADA_LIVE_STACKS"], !list.isEmpty else {
            throw XCTSkip("Set LADA_LIVE_STACKS to 'all' or template IDs.")
        }
        let wanted = Set(list.split(separator: ",").map(String.init))
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let cli = ContainerCLIClient()
        let appState = AppState(preferences: preferences, injectedService: cli)
        await appState.refreshAll(isUserInitiated: false)
        let imagesBefore = Set(try await cli.listImages().map(\.fullReference))
        let volumesBefore = Set(try await cli.listVolumes().map(\.name))
        var failures: [String] = []

        for template in ComposeStackTemplate.allTemplates where wanted.contains("all") || wanted.contains(template.id) {
            appState.stacks.yamlText = template.instantiate()
            let stack = appState.stacks.parsed
            await appState.stacks.start(appState: appState)
            try await Task.sleep(for: .seconds(20))
            await appState.refreshAll(isUserInitiated: false)
            for svc in stack.services {
                let state = appState.containers.first { $0.id == svc.containerName }?.state
                if state != .running {
                    let logs = (try? await cli.fetchContainerLogs(id: svc.containerName, bootLogs: false, tailLines: 12)) ?? ""
                    failures.append("\(template.id)/\(svc.serviceName): \(state.map(\.rawValue) ?? "missing")\n\(logs)\n\(appState.stacks.consoleLines.suffix(4).joined(separator: "\n"))")
                }
            }
            await appState.stacks.remove(appState: appState)
            for vol in stack.declaredVolumes where !volumesBefore.contains(vol) {
                try? await cli.deleteVolume(name: vol)
            }
        }
        for image in try await cli.listImages().map(\.fullReference) where !imagesBefore.contains(image) {
            try? await cli.deleteImage(reference: image, force: true)
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n---\n"))
    }
}
