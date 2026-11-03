import XCTest
@testable import Lada

final class BulkSelectionTests: XCTestCase {
    private func c(_ id: String, _ state: ContainerState = .running) -> ContainerModel {
        ContainerModel(id: id, imageReference: "alpine", state: state)
    }

    private var rows: [ContainerListRow] {
        [
            .stack(ContainerStackGroup(name: "shop", members: [c("shop-web"), c("shop-db", .stopped)])),
            .container(c("solo")),
            .container(c("other", .stopped)),
        ]
    }

    func testStackRowCoversAllMembersInListOrder() {
        let ids = BulkSelection.containerIDs(in: ["other", "stack:shop"], rows: rows)
        XCTAssertEqual(ids, ["shop-web", "shop-db", "other"])
    }

    func testMemberAndItsStackAreNotCountedTwice() {
        let ids = BulkSelection.containerIDs(in: ["stack:shop", "shop-db", "solo"], rows: rows)
        XCTAssertEqual(ids, ["shop-web", "shop-db", "solo"])
    }

    func testSingleMemberCanBePickedAlone() {
        XCTAssertEqual(BulkSelection.containerIDs(in: ["shop-db"], rows: rows), ["shop-db"])
    }

    func testPrunedDropsGoneIDsButKeepsMembers() {
        let kept = BulkSelection.pruned(["shop-db", "stack:shop", "deleted", "stack:gone"], rows: rows)
        XCTAssertEqual(kept, ["shop-db", "stack:shop"])
    }

    func testRunCarriesOnAfterAFailureAndSummarises() async {
        struct Boom: Error {}
        let outcome = await BulkSelection.run(["a", "b", "c"]) { item in
            if item == "b" { throw LadaError(category: .containerLifecycleFailure, explanation: "busy", suggestedRemediation: "") }
        }
        XCTAssertEqual(outcome.succeeded, ["a", "c"])
        XCTAssertEqual(outcome.failed, [BulkSelection.Failure(item: "b", reason: "busy")])
        XCTAssertEqual(outcome.summary(verb: "Stopped", noun: "container"), "Stopped 2 of 3 containers.\nb: busy")
        XCTAssertEqual(BulkSelection.Outcome(succeeded: ["x"]).summary(verb: "Deleted", noun: "image"), "Deleted 1 image.")
    }

    @MainActor
    func testBulkStopAndDeleteAgainstMockRuntime() async throws {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: MockContainerRuntimeService())
        await appState.refreshAll(isUserInitiated: false)

        let all = appState.containers.map(\.id)
        XCTAssertGreaterThanOrEqual(all.count, 2, "mock runtime has several containers")
        await appState.startContainers(ids: appState.containers.filter { $0.state != .running }.map(\.id))
        XCTAssertNil(appState.activeError)
        let running = appState.containers.filter { $0.state == .running }.map(\.id)
        XCTAssertEqual(Set(running), Set(all), "bulk start starts every stopped container")

        await appState.stopContainers(ids: running)
        XCTAssertNil(appState.activeError)
        XCTAssertTrue(appState.containers.filter { running.contains($0.id) }.allSatisfy { $0.state != .running },
                      "every selected container is stopped")
        XCTAssertEqual(appState.activityEvents.first?.title, "Stop \(running.count) containers", "one Activity entry for the batch")

        let doomed = Array(running.prefix(2))
        appState.selectedContainerID = doomed[0]
        await appState.deleteContainers(ids: doomed)
        XCTAssertNil(appState.activeError)
        XCTAssertFalse(appState.containers.contains { doomed.contains($0.id) })
        XCTAssertNil(appState.selectedContainerID, "a deleted selection is cleared")
    }
}
