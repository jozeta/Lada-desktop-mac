import XCTest
@testable import Lada

final class ContainerFileOperationsTests: XCTestCase {
    private let id = "web-01"

    private func makeOps() -> (MockContainerRuntimeService, ContainerFileOperations) {
        let mock = MockContainerRuntimeService()
        return (mock, ContainerFileOperations(runtime: mock, containerID: id))
    }

    // MARK: - ls -la parsing (real BusyBox output from an Alpine container on container 1.6.1)

    func testParsesDeviceFilesWithMajorMinorColumns() {
        let ls = """
        total 4
        drwxr-xr-x    8 root     root          3060 Oct 16 11:35 .
        drwxr-xr-x   22 root     root          4096 Nov  2 17:12 ..
        crw-r--r--    1 root     root       10, 235 Jan  1  1970 autofs
        crw--w----    1 root     tty       136,   0 Oct 16 11:35 console
        lrwxrwxrwx    1 root     root            13 Oct 16 11:35 fd -> /proc/self/fd
        crw-rw-rw-    1 root     root        1,   7 Jan  1  1970 full
        """
        let entries = ContainerFileOperations.parseLsOutput(ls, basePath: "/dev")
        XCTAssertEqual(entries.map(\.name), ["autofs", "console", "fd", "full"])
        let console = entries.first { $0.name == "console" }
        XCTAssertEqual(console?.fullPath, "/dev/console")
        XCTAssertEqual(console?.modifiedText, "Oct 16 11:35")
        XCTAssertEqual(console?.sizeBytes, 0)
        let fd = entries.first { $0.name == "fd" }
        XCTAssertEqual(fd?.symlinkTarget, "/proc/self/fd")
        XCTAssertEqual(entries.first { $0.name == "autofs" }?.modifiedText, "Jan 1 1970")
    }

    func testKeepsSpacesAndQuotesInsideNames() {
        let ls = "-rw-r--r--    1 root     root             6 Nov  2 17:12 name with  'quote'.txt \n"
        let entries = ContainerFileOperations.parseLsOutput(ls, basePath: "/tmp")
        XCTAssertEqual(entries.first?.name, "name with  'quote'.txt ")
        XCTAssertEqual(entries.first?.sizeBytes, 6)
    }

    // MARK: - Editor

    func testLoadsWholeTextFile() async throws {
        let (_, ops) = makeOps()
        let entry = try await ops.listDirectory("/etc/nginx").first { $0.name == "nginx.conf" }
        let result = try await ops.loadText(try XCTUnwrap(entry))
        XCTAssertEqual(result, .text("worker_processes auto;\n"))
    }

    func testRefusesToEditLargeFilesInsteadOfTruncating() async throws {
        let (mock, ops) = makeOps()
        var fs = MockContainerRuntimeService.defaultFileSystem()
        fs["/var-big.log"] = MockFileNode(isDirectory: false, mode: "644", contents: Data(repeating: 65, count: 2_000_000))
        mock.simulatedFileSystems[id] = fs
        let entry = try await ops.listDirectory("/").first { $0.name == "var-big.log" }
        let result = try await ops.loadText(try XCTUnwrap(entry))
        XCTAssertEqual(result, .tooLarge(bytes: 2_000_000))
    }

    func testRefusesToEditBinaryFiles() async throws {
        let (mock, ops) = makeOps()
        var fs = MockContainerRuntimeService.defaultFileSystem()
        fs["/bin.dat"] = MockFileNode(isDirectory: false, mode: "644", contents: Data([0x7F, 0x45, 0x4C, 0x46, 0x00, 0xFF]))
        mock.simulatedFileSystems[id] = fs
        let entry = try await ops.listDirectory("/").first { $0.name == "bin.dat" }
        let result = try await ops.loadText(try XCTUnwrap(entry))
        XCTAssertEqual(result, .binary)
    }

    func testSaveRestoresOriginalModeAndOwner() async throws {
        let (mock, ops) = makeOps()
        try await ops.saveText("#!/bin/sh\necho Låda\n", to: "/app/start.sh")
        let node = try XCTUnwrap(mock.simulatedFileSystems[id]?["/app/start.sh"])
        XCTAssertEqual(String(decoding: node.contents, as: UTF8.self), "#!/bin/sh\necho Låda\n")
        XCTAssertEqual(node.mode, "755")
        XCTAssertEqual(node.uid, 1000)
        XCTAssertEqual(node.gid, 1000)
        XCTAssertTrue(mock.recordedOperations.contains("execCommand:\(id):chmod 755 /app/start.sh"))
    }

    func testSaveOfLargeContentUsesCopyNotExecArguments() async throws {
        let (mock, ops) = makeOps()
        let big = String(repeating: "x", count: 500_000)
        try await ops.saveText(big, to: "/tmp/big.txt")
        XCTAssertEqual(mock.simulatedFileSystems[id]?["/tmp/big.txt"]?.contents.count, 500_000)
        XCTAssertFalse(mock.recordedOperations.contains { $0.contains("base64") || $0.contains("sh -c") })
    }

    // MARK: - Transfers and folders

    func testUploadAndDownloadRoundTripBinaryData() async throws {
        let (_, ops) = makeOps()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lada-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Data((0..<300_000).map { UInt8($0 % 251) })
        let source = dir.appendingPathComponent("weird: name.bin")
        try payload.write(to: source)

        let path = try await ops.upload(source, into: "/tmp")
        XCTAssertEqual(path, "/tmp/weird: name.bin")

        let dest = dir.appendingPathComponent("out.bin")
        try await ops.download(path, to: dest)
        XCTAssertEqual(try Data(contentsOf: dest), payload)
    }

    func testMakeDirectoryValidatesNameAndRemoveReportsResult() async throws {
        let (mock, ops) = makeOps()
        let created = try await ops.makeDirectory(named: "conf.d", in: "/etc/nginx")
        XCTAssertEqual(created, "/etc/nginx/conf.d")
        XCTAssertEqual(mock.simulatedFileSystems[id]?["/etc/nginx/conf.d"]?.isDirectory, true)

        for bad in ["", "..", "a/b"] {
            do {
                _ = try await ops.makeDirectory(named: bad, in: "/tmp")
                XCTFail("Expected '\(bad)' to be rejected")
            } catch {}
        }

        try await ops.remove("/etc/nginx")
        XCTAssertNil(mock.simulatedFileSystems[id]?["/etc/nginx/nginx.conf"])
        do {
            try await ops.remove("/")
            XCTFail("Expected '/' to be refused")
        } catch {}
    }

    func testListingMissingDirectoryThrows() async {
        let (_, ops) = makeOps()
        do {
            _ = try await ops.listDirectory("/does-not-exist")
            XCTFail("Expected an error")
        } catch {}
    }

    // MARK: - Argument builder

    func testCopyArgumentsAndValidation() throws {
        XCTAssertEqual(
            try ContainerCopyArguments.copyFromContainer(containerID: "web-01", containerPath: "/etc/hosts", hostPath: "/tmp/x/payload"),
            ["copy", "web-01:/etc/hosts", "/tmp/x/payload"]
        )
        XCTAssertEqual(
            try ContainerCopyArguments.copyToContainer(hostPath: "/tmp/x/payload", containerID: "web-01", containerPath: "/app/a b.txt"),
            ["copy", "/tmp/x/payload", "web-01:/app/a b.txt"]
        )
        XCTAssertThrowsError(try ContainerCopyArguments.copyFromContainer(containerID: "web-01", containerPath: "relative", hostPath: "/tmp/p"))
        XCTAssertThrowsError(try ContainerCopyArguments.copyFromContainer(containerID: "web-01", containerPath: "/a\nb", hostPath: "/tmp/p"))
        XCTAssertThrowsError(try ContainerCopyArguments.copyToContainer(hostPath: "/tmp/a:b", containerID: "web-01", containerPath: "/a"))
        XCTAssertThrowsError(try ContainerCopyArguments.copyToContainer(hostPath: "/tmp/p", containerID: "-rf", containerPath: "/a"))
    }
}
