import XCTest
import SwiftUI
@testable import Lada

@MainActor
final class TelemetryTests: XCTestCase {
    func testRatesFromTwoCumulativeSnapshots() {
        let previous = ContainerStatsModel(id: "web", cpuUsageUsec: 1_000_000, networkRxBytes: 1_000, networkTxBytes: 500, blockReadBytes: 0, blockWriteBytes: 0)
        // 2 s later: 1 s of CPU time on a 4-vCPU container = 12.5 %.
        let current = ContainerStatsModel(id: "web", cpuUsageUsec: 2_000_000, networkRxBytes: 5_000, networkTxBytes: 500, blockReadBytes: 4_096, blockWriteBytes: 8_192)
        let rates = AppState.telemetryRates(current: current, previous: previous, interval: 2, cpus: 4)
        XCTAssertEqual(rates.cpuPercent, 12.5, accuracy: 0.0001)
        XCTAssertEqual(rates.rxBps, 2_000)
        XCTAssertEqual(rates.txBps, 0)
        XCTAssertEqual(rates.readBps, 2_048)
        XCTAssertEqual(rates.writeBps, 4_096)
    }

    func testIdleContainerReportsZeroNotAFloor() {
        let s = ContainerStatsModel(id: "idle", cpuUsageUsec: 5_000)
        XCTAssertEqual(AppState.telemetryRates(current: s, previous: s, interval: 2, cpus: 2).cpuPercent, 0)
    }

    func testFirstSnapshotIsOnlyABaselineAndNoSamplesAreInvented() async throws {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = true
        let appState = AppState(preferences: preferences, injectedService: MockContainerRuntimeService())

        await appState.refreshAll(isUserInitiated: false)
        let running = try XCTUnwrap(appState.containers.first { $0.state == .running })
        XCTAssertNotNil(appState.containerStats[running.id], "baseline counters are stored")
        XCTAssertTrue((appState.containerTelemetryHistory[running.id] ?? []).isEmpty, "no estimated or back-filled points")
        XCTAssertTrue(appState.systemTelemetryHistory.isEmpty)

        try await Task.sleep(for: .milliseconds(50))
        await appState.sampleAllRunningContainersTelemetry()
        XCTAssertEqual(appState.containerTelemetryHistory[running.id]?.count, 1, "one measured point after two snapshots")
        XCTAssertEqual(appState.systemTelemetryHistory.count, 1)
    }

    func testClusterCPUIsWeightedByAllottedVCPUs() {
        let now = Date()
        let busy = ContainerPerformanceSample(timestamp: now, cpuPercent: 100, cpuCoresUsed: 4, allocatedCPUs: 4)
        let idle = ContainerPerformanceSample(timestamp: now, cpuPercent: 0, cpuCoresUsed: 0, allocatedCPUs: 1)
        let agg = AppState.aggregateSample([busy, idle], at: now)
        XCTAssertEqual(agg.cpuPercent, 80, accuracy: 0.0001)
        XCTAssertEqual(agg.cpuCoresUsed, 4)
        XCTAssertEqual(agg.allocatedCPUs, 5)
    }

    func testCoresUsedMatchesMeasuredLoad() {
        // Measured on container 1.6.1: a 5 s single-core busy loop added 5,051,627 µs of CPU time
        // over 7.2 s on a 4-vCPU container.
        let a = ContainerStatsModel(id: "m", cpuUsageUsec: 115_186)
        let b = ContainerStatsModel(id: "m", cpuUsageUsec: 5_166_813)
        let rates = AppState.telemetryRates(current: b, previous: a, interval: 7.2, cpus: 4)
        XCTAssertEqual(rates.cpuCoresUsed, 0.70, accuracy: 0.01)
        XCTAssertEqual(rates.cpuPercent, 17.5, accuracy: 0.2)
    }

    func testSmoothCurveNeverOvershootsTheSamples() {
        // A spiky series: a straight cubic spline would dip below 0 and rise above 100 here.
        let ys: [CGFloat] = [100, 100, 0, 100, 0, 0, 100, 100]
        let pts = ys.enumerated().map { CGPoint(x: CGFloat($0.offset) * 10, y: $0.element) }
        var path = Path()
        NordicPerformanceChartCard.addSmoothCurve(through: pts, to: &path, moveToStart: true)
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minY, -0.001)
        XCTAssertLessThanOrEqual(bounds.maxY, 100.001)
        XCTAssertEqual(bounds.width, 70, accuracy: 0.001)
    }
}

