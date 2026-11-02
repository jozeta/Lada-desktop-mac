import XCTest
@testable import Lada

/// Opt-in test against a real running container (skipped unless `LADA_LIVE_CONTAINER` names one):
///
///     LADA_LIVE_CONTAINER=my-container swift test --filter LiveFileOperationsTests
///
/// Works only inside `/tmp/lada-live-test-*` in that container and removes it afterwards.
final class LiveFileOperationsTests: XCTestCase {
    func testRoundTripAgainstRealContainer() async throws {
        guard let id = ProcessInfo.processInfo.environment["LADA_LIVE_CONTAINER"], !id.isEmpty else {
            throw XCTSkip("Set LADA_LIVE_CONTAINER to a running container ID to run this test.")
        }
        let ops = ContainerFileOperations(runtime: ContainerCLIClient(), containerID: id)
        let dir = try await ops.makeDirectory(named: "lada-live-test-\(UUID().uuidString.prefix(8))", in: "/tmp")
        do {
            // A 3 MB binary payload: far beyond the 128 KiB single-argument limit of the old exec path.
            let host = FileManager.default.temporaryDirectory.appendingPathComponent("lada-live-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: host) }
            let payload = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
            let source = host.appendingPathComponent("blob.bin")
            try payload.write(to: source)

            let remote = try await ops.upload(source, into: dir)
            let back = host.appendingPathComponent("back.bin")
            try await ops.download(remote, to: back)
            XCTAssertEqual(try Data(contentsOf: back), payload)

            // Saving must keep an executable script executable.
            let script = ContainerFileOperations.join(dir, "run me.sh")
            try await ops.saveText("#!/bin/sh\necho hej\n", to: script)
            _ = try await ContainerCLIClient().execCommand(containerID: id, command: ["chmod", "750", script], user: nil, workdir: nil, env: [])
            try await ops.saveText("#!/bin/sh\necho Låda\n", to: script)
            let listing = try await ops.listDirectory(dir)
            let entry = try XCTUnwrap(listing.first { $0.name == "run me.sh" })
            XCTAssertEqual(entry.permissions, "-rwxr-x---")
            let loaded = try await ops.loadText(entry)
            XCTAssertEqual(loaded, .text("#!/bin/sh\necho Låda\n"))
        } catch {
            try? await ops.remove(dir)
            throw error
        }
        try await ops.remove(dir)
    }
}
