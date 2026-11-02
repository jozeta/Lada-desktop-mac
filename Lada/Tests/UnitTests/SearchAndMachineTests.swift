import XCTest
@testable import Lada

final class UniversalSearchTests: XCTestCase {
    private func inputs() -> UniversalSearch.Inputs {
        var i = UniversalSearch.Inputs()
        i.containers = [
            ContainerModel(id: "nordic-web", imageReference: "docker.io/library/nginx:1.27-alpine", state: .running,
                           configuration: ContainerConfigurationModel(labels: ["com.lada.compose.project": "shop"])),
            ContainerModel(id: "postgres-dev", imageReference: "docker.io/library/postgres:17", state: .stopped)
        ]
        i.machines = [MachineModel(id: "devbox", status: .running, ipAddress: "192.168.64.96", homeDirectory: "/home/zeta")]
        i.volumes = [VolumeModel(id: "pgdata", sourcePath: "/Users/zeta/Library/Application Support/com.apple.container/volumes/pgdata")]
        i.catalog = DockerHubService.curatedCatalog
        return i
    }

    func testFindsEveryKindWithWhereItLives() {
        let results = UniversalSearch.results(for: "pg", in: inputs())
        let volume = try? XCTUnwrap(results.first { $0.kind == .volume })
        XCTAssertEqual(volume?.title, "pgdata")
        XCTAssertTrue(volume?.location.hasPrefix("Volumes · /Users/zeta/") ?? false)
        XCTAssertEqual(volume?.destination, .volume("pgdata"))
    }

    func testNameMatchesRankAboveOtherFields() {
        // "nginx" is the image of nordic-web (field match) and a library preset name (name match).
        let results = UniversalSearch.results(for: "nginx", in: inputs())
        XCTAssertEqual(results.first?.kind, .libraryImage)
        XCTAssertTrue(results.contains { $0.kind == .container && $0.title == "nordic-web" })
    }

    func testStacksAndPagesAndMachines() {
        XCTAssertEqual(UniversalSearch.results(for: "shop", in: inputs()).first?.destination, .stack("shop"))
        XCTAssertEqual(UniversalSearch.results(for: "dockerfile", in: inputs()).first?.destination, .section(.dockerfileEditor))
        let machine = UniversalSearch.results(for: "192.168.64.96", in: inputs()).first
        XCTAssertEqual(machine?.destination, .machine("devbox"))
        XCTAssertEqual(machine?.location, "Machines · 192.168.64.96 · /home/zeta")
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(UniversalSearch.results(for: "  ", in: inputs()).isEmpty)
    }

    @MainActor
    func testOpeningAResultSelectsIt() async {
        let state = AppState(injectedService: MockContainerRuntimeService())
        await state.refreshAll(isUserInitiated: false)
        let machine = try? XCTUnwrap(state.machines.first)
        state.open(.machine(machine?.id ?? ""))
        XCTAssertEqual(state.selectedSection, .machines)
        XCTAssertEqual(state.selectedMachineID, machine?.id)
        state.open(.libraryImage("redis"))
        XCTAssertEqual(state.selectedSection, .imageLibrary)
        XCTAssertEqual(state.pendingLibrarySearch, "redis")
    }

    @MainActor
    func testUserRefreshTellsViewsToReload() async {
        let state = AppState(injectedService: MockContainerRuntimeService())
        let before = state.refreshGeneration
        await state.userRefresh()
        XCTAssertEqual(state.refreshGeneration, before + 1)
        XCTAssertFalse(state.isUserRefreshing)
    }
}

final class ExternalTerminalScriptTests: XCTestCase {
    func testEveryWordIsQuoted() {
        XCTAssertEqual(ExternalTerminalScript.quote("it's"), "'it'\\''s'")
        let script = ExternalTerminalScript.make(heading: "x", command: ["/usr/local/bin/container", "machine", "run", "-i", "-t", "-n", "dev"])
        XCTAssertTrue(script.contains("'/usr/local/bin/container' 'machine' 'run' '-i' '-t' '-n' 'dev'"))
    }

    func testInjectionStaysInsideOneArgument() {
        let script = ExternalTerminalScript.make(heading: "a'; rm -rf ~; '", command: ["/opt/x y/container", "exec", "-it", "c\"$(id)"])
        XCTAssertTrue(script.contains("'/opt/x y/container' 'exec' '-it' 'c\"$(id)'"))
        XCTAssertTrue(script.contains("'a'\\''; rm -rf ~; '\\'''"))
    }
}

final class MachineParsingTests: XCTestCase {
    /// `container machine inspect testmachine01` from container 1.6.1.
    let inspect = """
    [
      {
        "containerId" : "testmachine01-0d1c9e",
        "cpus" : 4,
        "createdDate" : "2026-10-16T11:34:37Z",
        "diskSize" : 1224867840,
        "homeMount" : "ro",
        "id" : "testmachine01",
        "image" : {
          "descriptor" : { "digest" : "sha256:294b", "mediaType" : "application/vnd.oci.image.index.v1+json", "size" : 9218 },
          "reference" : "docker.io/library/alpine:latest"
        },
        "ipAddress" : "192.168.64.96",
        "memory" : 8589934592,
        "platform" : { "architecture" : "arm64", "os" : "linux" },
        "startedDate" : "2026-11-02T21:12:03Z",
        "status" : "running",
        "userSetup" : { "gid" : 20, "home" : "/home/zeta", "uid" : 501, "username" : "zeta" }
      }
    ]
    """

    func testReadsTopLevelFieldsOfRealInspectOutput() throws {
        let m = try XCTUnwrap(ContainerOutputParser.parseMachines(jsonString: inspect).first)
        XCTAssertEqual(m.containerID, "testmachine01-0d1c9e")
        XCTAssertEqual(m.imageReference, "docker.io/library/alpine:latest")
        XCTAssertEqual(m.homeMount, .ro)
        XCTAssertEqual(m.username, "zeta")
        XCTAssertEqual(m.homeDirectory, "/home/zeta")
        XCTAssertEqual(m.cpus, 4)
        XCTAssertEqual(m.status, .running)
    }

    func testMachineStatsUseTheMachinesCPUs() {
        let m = MachineModel(id: "dev", status: .running, cpus: 6, containerID: "dev-1a2b")
        XCTAssertEqual(AppState.allocatedCPUs(forStatsID: "dev-1a2b", containers: [], machines: [m]), 6)
        XCTAssertNil(AppState.allocatedCPUs(forStatsID: "other", containers: [], machines: [m]))
    }

    @MainActor
    func testMockMachineFilesGoThroughItsContainer() async throws {
        let mock = MockContainerRuntimeService()
        let machines = try await mock.listMachines()
        let machine = try XCTUnwrap(machines.first)
        let cid = try XCTUnwrap(machine.containerID)
        let entries = try await ContainerFileOperations(runtime: mock, containerID: cid).listDirectory("/")
        XCTAssertFalse(entries.isEmpty)
        let stats = try await mock.getContainerStats(ids: [cid])
        XCTAssertEqual(stats.first?.id, cid)
    }
}

final class CompletionKindTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(CompletionKind.of("FROM"), .instruction)
        XCTAssertEqual(CompletionKind.of("--from=builder"), .flag)
        XCTAssertEqual(CompletionKind.of("${HOME}"), .variable)
        XCTAssertEqual(CompletionKind.of("nginx:1.27-alpine"), .image)
        XCTAssertEqual(CompletionKind.of("8080/tcp"), .value)
    }
}
