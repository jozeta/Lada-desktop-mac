import XCTest
@testable import Lada

/// Opt-in check that Image Library presets actually start (skipped unless `LADA_LIVE_PRESETS`
/// lists slugs, or is `all`):
///
///     LADA_LIVE_PRESETS=alpine,nginx,registry swift test --filter LiveImageLibraryPresetTests
///
/// Each preset is launched exactly as the library does it (`buildDeployRequest`, first tag), under
/// a `lada-preset-` name and with host ports shifted by 20000 to avoid clashes, then removed with
/// any volume the run created.
final class LiveImageLibraryPresetTests: XCTestCase {
    func testPresetsStartAndKeepRunning() async throws {
        guard let list = ProcessInfo.processInfo.environment["LADA_LIVE_PRESETS"], !list.isEmpty else {
            throw XCTSkip("Set LADA_LIVE_PRESETS to a comma-separated list of catalog slugs (or 'all').")
        }
        let wanted = Set(list.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        let presets = DockerHubService.curatedCatalog.filter { wanted.contains("all") || wanted.contains($0.slug) }
        XCTAssertFalse(presets.isEmpty, "No catalog entries match \(list)")

        let cli = ContainerCLIClient()
        let existingVolumes = Set(try await cli.listVolumes().map(\.name))
        var failures: [String] = []
        for item in presets {
            var req = item.buildDeployRequest(selectedTag: item.availableTags.first ?? "latest", defaultCPUs: 2, defaultMemoryMB: 1024)
            req.name = "lada-preset-" + item.name.replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
            req.publishedPorts = req.publishedPorts.map { var p = $0; p.hostPort &+= 20000; return p }
            req.mounts = req.mounts.map { var m = $0; m.source = "lada-preset-" + m.source; m.volumeName = m.source; return m }
            try? await cli.deleteContainer(id: req.name, force: true)
            do {
                _ = try await cli.createOrRunContainer(request: req)
                try await Task.sleep(for: .seconds(15))
                let state = try await cli.inspectContainer(id: req.name).state
                if state != .running {
                    let logs = (try? await cli.fetchContainerLogs(id: req.name, bootLogs: false, tailLines: 15)) ?? ""
                    failures.append("\(item.slug): \(state.rawValue)\n\(logs)")
                }
            } catch {
                failures.append("\(item.slug): \(error)")
            }
            try? await cli.deleteContainer(id: req.name, force: true)
        }
        for vol in try await cli.listVolumes().map(\.name) where vol.hasPrefix("lada-preset-") && !existingVolumes.contains(vol) {
            try? await cli.deleteVolume(name: vol)
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n---\n"))
    }
}
