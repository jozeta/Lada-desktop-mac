import XCTest
@testable import Lada

/// Opt-in: builds a tiny image through BuildWorkspace with the real CLI (skipped unless
/// `LADA_LIVE_BUILD=1`). Checks that a folder with only a `Dockerfile` builds (the build file is
/// resolved inside the folder) and that a failing build reports BuildKit's error line.
@MainActor
final class LiveBuildWorkspaceTests: XCTestCase {
    func testBuildAndFailureThroughWorkspace() async throws {
        guard ProcessInfo.processInfo.environment["LADA_LIVE_BUILD"] == "1" else {
            throw XCTSkip("Set LADA_LIVE_BUILD=1 to run a real build.")
        }
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: ContainerCLIClient())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lada-live-build-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "FROM alpine:latest\nRUN echo built-by-lada > /marker\n".write(to: dir.appendingPathComponent("Dockerfile"), atomically: true, encoding: .utf8)

        let work = appState.builds
        work.choose(folder: dir.path)
        work.imageName = "local/lada-live-build:test"
        XCTAssertNil(work.blocker)
        work.build(appState: appState)
        let deadline = Date().addingTimeInterval(240)
        while work.isBuilding, Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        guard case .succeeded(let image, _) = work.phase else { return XCTFail("phase: \(work.phase)\n\(work.log)") }
        XCTAssertEqual(image, "local/lada-live-build:test")
        XCTAssertEqual(appState.buildHistory.first?.status, .succeeded)

        try "FROM alpine:latest\nRUN exit 7\n".write(to: dir.appendingPathComponent("Dockerfile"), atomically: true, encoding: .utf8)
        work.build(appState: appState)
        while work.isBuilding, Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        guard case .failed(let reason) = work.phase else { return XCTFail("expected failure: \(work.phase)") }
        XCTAssertTrue(reason.contains("exit code: 7"), reason)

        try? await appState.runtimeService.deleteImage(reference: "local/lada-live-build:test", force: true)
        try? await appState.runtimeService.stopBuilder()
    }
}
