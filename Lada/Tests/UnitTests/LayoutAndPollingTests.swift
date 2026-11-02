import XCTest
import Combine
@testable import Lada

final class MasonryLayoutTests: XCTestCase {
    func testTwoColumnsFillTheShortestColumn() {
        let layout = MasonryLayout(minColumnWidth: 380, maxColumns: 2, spacing: 14)
        // Active containers (tall), disk (short), activity: activity goes under the short disk panel.
        let heights: [CGFloat] = [400, 200, 150]
        let p = layout.place(count: 3, width: 900) { i, _ in heights[i] }
        let columnWidth = (900 - 14) / 2.0
        XCTAssertEqual(p.frames[0], CGRect(x: 0, y: 0, width: columnWidth, height: 400))
        XCTAssertEqual(p.frames[1], CGRect(x: columnWidth + 14, y: 0, width: columnWidth, height: 200))
        XCTAssertEqual(p.frames[2], CGRect(x: columnWidth + 14, y: 214, width: columnWidth, height: 150))
        XCTAssertEqual(p.height, 400)
    }

    func testNarrowWidthStacksInOneColumn() {
        let layout = MasonryLayout(minColumnWidth: 380, maxColumns: 2, spacing: 14)
        XCTAssertEqual(layout.columnCount(for: 600), 1)
        let p = layout.place(count: 3, width: 600) { _, _ in 100 }
        XCTAssertEqual(p.frames.map(\.minY), [0, 114, 228])
        XCTAssertEqual(p.frames.map(\.width), [600, 600, 600])
        XCTAssertEqual(p.height, 328)
    }

    func testColumnCountIsCappedAndNeverZero() {
        let layout = MasonryLayout(minColumnWidth: 380, maxColumns: 2, spacing: 14)
        XCTAssertEqual(layout.columnCount(for: 3000), 2)
        XCTAssertEqual(layout.columnCount(for: 0), 1)
        XCTAssertEqual(layout.columnCount(for: .infinity), 1)
    }
}

@MainActor
final class PollingPublishTests: XCTestCase {
    /// An unchanged poll result must not publish: every publish re-renders the whole window.
    func testUnchangedRefreshDoesNotPublish() async {
        let mock = MockContainerRuntimeService()
        let state = AppState(injectedService: mock)
        await state.refreshAll(isUserInitiated: false)
        await state.refreshFastWorkloadState()

        var publishes = 0
        let token = state.objectWillChange.sink { publishes += 1 }
        state.assignIfChanged(\.containers, state.containers)
        state.assignIfChanged(\.images, state.images)
        state.assignIfChanged(\.portHealthMap, state.portHealthMap)
        XCTAssertEqual(publishes, 0)

        state.assignIfChanged(\.dnsDomains, state.dnsDomains + ["changed"])
        XCTAssertEqual(publishes, 1)
        token.cancel()
    }

    func testOnePollIntervalFeedsTheCharts() {
        // History length is sized for this cadence (5 minutes of points).
        XCTAssertEqual(AppState.pollIntervalSeconds * AppState.telemetryHistoryLength, 300)
    }
}
