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

    // MARK: - Per-container disk

    func testContainerFreeSpaceIsLimitedByTheMac() {
        // 512 GiB sparse image, 200 MB written, but the Mac has only 100 GB free.
        let disk = ContainerDiskSnapshot.make(allocatedBytes: 200_000_000, logicalSizeBytes: 549_755_813_888, hostAvailableBytes: 100_000_000_000)
        XCTAssertEqual(disk.usedBytes, 200_000_000)
        XCTAssertEqual(disk.freeBytes, 100_000_000_000)
        XCTAssertTrue(disk.limitedByHostDisk)
    }

    func testContainerFreeSpaceIsLimitedByTheImage() {
        let disk = ContainerDiskSnapshot.make(allocatedBytes: 900, logicalSizeBytes: 1_000, hostAvailableBytes: 10_000)
        XCTAssertEqual(disk.freeBytes, 100)
        XCTAssertFalse(disk.limitedByHostDisk)
    }

    func testAllocatedLargerThanLogicalNeverGoesNegative() {
        // A filesystem's block rounding can allocate a little more than a tiny file's size.
        let disk = ContainerDiskSnapshot.make(allocatedBytes: 4_096, logicalSizeBytes: 10, hostAvailableBytes: 1_000)
        XCTAssertEqual(disk.freeBytes, 0)
        XCTAssertEqual(disk.capacityBytes, 4_096)
    }

    func testReadsASparseFileAndSkipsUnsafeIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lada-disk-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("containers/web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = dir.appendingPathComponent("rootfs.ext4")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 1 << 30)          // 1 GiB logical, nothing written
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(repeating: 1, count: 1 << 20))   // 1 MiB really used
        try handle.close()

        let disks = AppState.readContainerDisks(ids: ["web", "../web", "missing"], dataRoot: root.path, hostAvailable: 1 << 40)
        XCTAssertEqual(Array(disks.keys), ["web"])
        let web = try XCTUnwrap(disks["web"])
        XCTAssertEqual(web.capacityBytes, 1 << 30)
        XCTAssertLessThan(web.usedBytes, 8 << 20, "sparse: only written blocks count")
        XCTAssertGreaterThanOrEqual(web.usedBytes, 1 << 20)
    }
}
