import XCTest
@testable import Lada

final class DiskSpaceTests: XCTestCase {
    func testBreakdownAddsUpToTheDisk() {
        let df = DiskUsageSummary(
            images: .init(total: 3, active: 1, sizeInBytes: 2_000, reclaimable: 0),
            containers: .init(total: 2, active: 1, sizeInBytes: 500, reclaimable: 0),
            volumes: .init(total: 1, active: 1, sizeInBytes: 1_500, reclaimable: 0)
        )
        let disk = DiskSpaceSnapshot(totalBytes: 10_000, availableBytes: 3_000)
        let segments = DiskBreakdown.segments(runtime: df, disk: disk)
        XCTAssertEqual(segments.map(\.kind), [.images, .containers, .volumes, .other, .free])
        XCTAssertEqual(segments.first { $0.kind == .other }?.bytes, 3_000)   // 7,000 used − 4,000 runtime
        XCTAssertEqual(segments.reduce(0) { $0 + $1.bytes }, disk.totalBytes)
    }

    func testOtherNeverGoesNegative() {
        // Sparse volumes can report more than they occupy on disk.
        let df = DiskUsageSummary(volumes: .init(total: 1, active: 0, sizeInBytes: 50_000, reclaimable: 0))
        let segments = DiskBreakdown.segments(runtime: df, disk: DiskSpaceSnapshot(totalBytes: 10_000, availableBytes: 9_000))
        XCTAssertEqual(segments.first { $0.kind == .other }?.bytes, 0)
    }

    func testReadsTheRealVolume() throws {
        let snap = try XCTUnwrap(DiskSpaceSnapshot.read(path: NSHomeDirectory() + "/Library/Application Support/does-not-exist/x"))
        XCTAssertGreaterThan(snap.totalBytes, 0)
        XCTAssertLessThanOrEqual(snap.availableBytes, snap.totalBytes)
    }
}
