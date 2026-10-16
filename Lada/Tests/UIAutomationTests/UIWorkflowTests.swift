import XCTest
@testable import Lada

@MainActor
final class UIWorkflowTests: XCTestCase {
    private func makeTestAppState(firstLaunchCompleted: Bool = true) -> (AppState, MockContainerRuntimeService) {
        let preferences = AppPreferences()
        preferences.hasCompletedFirstLaunchSetup = firstLaunchCompleted
        let mockRuntime = MockContainerRuntimeService()
        let appState = AppState(
            preferences: preferences,
            injectedService: mockRuntime
        )
        return (appState, mockRuntime)
    }

    func testInitialRefreshPopulatesAllSectionsAndDashboardMetrics() async {
        let (appState, _) = makeTestAppState(firstLaunchCompleted: true)
        await appState.refreshAll(isUserInitiated: false)

        XCTAssertFalse(appState.showSetupWizard)
        XCTAssertEqual(appState.systemStatus.state, .running)
        XCTAssertEqual(appState.containers.count, 2)
        XCTAssertEqual(appState.containers.filter { $0.state == .running }.count, 1)
        XCTAssertEqual(appState.images.count, 3)
        XCTAssertEqual(appState.networks.count, 2)
        XCTAssertEqual(appState.volumes.count, 2)
        XCTAssertEqual(appState.machines.count, 1)
        XCTAssertGreaterThan(appState.diskUsage.totalBytes, 0)
        XCTAssertTrue(appState.builderStatus.isRunning)
    }

    func testFirstLaunchBootstrapPresentsSetupWizardWhenNotCompleted() async {
        let (appState, _) = makeTestAppState(firstLaunchCompleted: false)
        await appState.performInitialBootstrap()

        XCTAssertTrue(appState.showSetupWizard)
    }

    func testContainerCreateStartStopAndDeleteWorkflowsUpdateAppStateAndActivityHistory() async {
        let (appState, _) = makeTestAppState()
        await appState.refreshAll(isUserInitiated: false)

        let createReq = ContainerCreateRequest(
            name: "ui-test-service",
            imageReference: "docker.io/library/postgres:16-alpine"
        )
        await appState.performOperation(
            category: "Containers",
            title: "Create Container"
        ) {
            let id = try await appState.runtimeService.createOrRunContainer(request: createReq)
            return "Created container \(id)"
        }
        XCTAssertTrue(appState.containers.contains(where: { $0.id == "ui-test-service" }))

        await appState.performOperation(
            category: "Containers",
            title: "Stop Container"
        ) {
            try await appState.runtimeService.stopContainer(id: "ui-test-service", timeoutSeconds: 5)
            return "Stopped ui-test-service"
        }
        XCTAssertEqual(appState.containers.first(where: { $0.id == "ui-test-service" })?.state, .stopped)

        await appState.performOperation(
            category: "Containers",
            title: "Start Container"
        ) {
            try await appState.runtimeService.startContainer(id: "ui-test-service")
            return "Started ui-test-service"
        }
        XCTAssertEqual(appState.containers.first(where: { $0.id == "ui-test-service" })?.state, .running)

        await appState.performOperation(
            category: "Containers",
            title: "Delete Container"
        ) {
            try await appState.runtimeService.deleteContainer(id: "ui-test-service", force: true)
            return "Deleted ui-test-service"
        }
        XCTAssertFalse(appState.containers.contains(where: { $0.id == "ui-test-service" }))
        XCTAssertFalse(appState.activityEvents.isEmpty)
    }

    func testRegistryLoginAndRedactedDiagnosticReportGeneration() async {
        let (appState, _) = makeTestAppState()
        await appState.refreshAll(isUserInitiated: false)

        await appState.performOperation(
            category: "Registries",
            title: "Registry Login",
            redactedCommand: "container registry login --username platform-eng --password-stdin registry.example.com"
        ) {
            try await appState.runtimeService.loginRegistry(
                server: "registry.example.com",
                username: "platform-eng",
                password: "super-sensitive-pat-999",
                scheme: "https"
            )
            return "Authenticated with registry.example.com as platform-eng (TOKEN=super-sensitive-pat-999)"
        }

        XCTAssertTrue(appState.registries.contains(where: { $0.hostname == "registry.example.com" }))

        // Verify diagnostic report redacts secrets
        let report = appState.generateRedactedDiagnosticReport()
        XCTAssertFalse(report.contains("super-sensitive-pat-999"))
        XCTAssertTrue(report.contains("=== LÅDA DIAGNOSTIC REPORT ==="))
    }

    func testDockerfileParserExtractsAllInstructionsAndPrepopulatesCreateContainerRequest() {
        let sampleDockerfile = """
        # syntax=docker/dockerfile:1
        FROM --platform=linux/arm64 python:3.12-slim AS runtime
        WORKDIR /app
        RUN pip install --no-cache-dir uvicorn
        ENV PYTHONDONTWRITEBYTECODE=1 \\
            PORT=8000 \\
            API_SECRET_TOKEN=topsecret123
        EXPOSE 80/tcp 8000
        VOLUME ["/var/lib/data", "/app/uploads"]
        USER 10001:10001
        LABEL org.opencontainers.image.title="billing-api"
        ENTRYPOINT ["python3", "-m"]
        CMD ["http.server", "8000"]
        """

        let parsed = DockerfileParser.parse(content: sampleDockerfile)
        XCTAssertEqual(parsed.baseImage, "python:3.12-slim")
        XCTAssertEqual(parsed.workingDirectory, "/app")
        XCTAssertEqual(parsed.userSpec, "10001:10001")
        XCTAssertEqual(parsed.entrypointOverride, "python3")
        XCTAssertEqual(parsed.commandArguments, ["-m", "http.server", "8000"])
        XCTAssertEqual(parsed.exposedPorts.count, 2)
        // Privileged port 80 is mapped to unprivileged host port 8080 by default
        XCTAssertEqual(parsed.exposedPorts.first?.containerPort, 80)
        XCTAssertEqual(parsed.exposedPorts.first?.hostPort, 8080)
        XCTAssertEqual(parsed.exposedPorts.last?.containerPort, 8000)
        XCTAssertEqual(parsed.exposedPorts.last?.hostPort, 8000)
        XCTAssertEqual(parsed.mounts.count, 2)
        XCTAssertTrue(parsed.hasBuildInstructions)

        let secretEnv = parsed.environmentVariables.first(where: { $0.key == "API_SECRET_TOKEN" })
        XCTAssertNotNil(secretEnv)
        XCTAssertTrue(secretEnv?.isSecret == true)

        let req = DockerfileParser.buildContainerCreateRequest(
            content: sampleDockerfile,
            defaultCPUs: 4,
            defaultMemoryMB: 4096
        )
        XCTAssertEqual(req.name, "billing-api")
        XCTAssertEqual(req.dockerfileBaseImage, "python:3.12-slim")
        XCTAssertTrue(req.hasAttachedDockerfile)
        XCTAssertTrue(req.buildFromDockerfileBeforeRun)
        XCTAssertEqual(req.publishedPorts.count, 2)
        XCTAssertEqual(req.mounts.count, 2)
        XCTAssertEqual(req.cpus, 4)
        XCTAssertEqual(req.memoryMB, 4096)
    }

    func testDroppedDockerfilePopulatesCreateContainerSheetAndDeploysContainer() async {
        let (appState, _) = makeTestAppState()
        await appState.refreshAll(isUserInitiated: false)

        let dockerfileText = """
        FROM nginx:1.27-alpine
        RUN echo "custom static site" > /usr/share/nginx/html/index.html
        EXPOSE 80
        """

        appState.handleDroppedDockerfileText(dockerfileText)
        XCTAssertTrue(appState.showCreateContainerSheet)
        XCTAssertNotNil(appState.createContainerInitialRequest)
        XCTAssertTrue(appState.createContainerInitialRequest?.hasAttachedDockerfile == true)
        XCTAssertEqual(appState.createContainerInitialRequest?.publishedPorts.first?.containerPort, 80)
        XCTAssertEqual(appState.createContainerInitialRequest?.publishedPorts.first?.hostPort, 8080)

        guard var deployRequest = appState.createContainerInitialRequest else {
            XCTFail("Expected createContainerInitialRequest to be populated")
            return
        }
        deployRequest.name = "dropped-nginx-app"

        var completed = false
        await appState.buildAndDeployContainer(
            request: deployRequest,
            onProgressLine: { _ in },
            onComplete: { completed = true }
        )

        XCTAssertTrue(completed)
        XCTAssertTrue(appState.containers.contains(where: { $0.id == "dropped-nginx-app" }))
        XCTAssertTrue(appState.images.contains(where: { $0.fullReference == deployRequest.imageReference }))
    }

    func testDockerHubLibrarySearchAndDeployPrepopulation() async {
        let results = await DockerHubService.shared.searchRepositories(query: "postgres")
        XCTAssertFalse(results.isEmpty)
        guard let postgres = results.first(where: { $0.name == "postgres" }) else {
            XCTFail("Expected postgres in Docker Hub results")
            return
        }

        let deployReq = postgres.buildDeployRequest(
            selectedTag: "17-alpine",
            defaultCPUs: 2,
            defaultMemoryMB: 2048
        )
        XCTAssertEqual(deployReq.imageReference, "postgres:17-alpine")
        XCTAssertEqual(deployReq.publishedPorts.first?.containerPort, 5432)
        XCTAssertFalse(deployReq.environmentVariables.isEmpty)
        XCTAssertFalse(deployReq.mounts.isEmpty)
        XCTAssertTrue(deployReq.environmentVariables.contains(where: { $0.key == "PGDATA" && $0.value == "/var/lib/postgresql/data/pgdata" }))
        let cliArgs = deployReq.buildCLIArguments()
        XCTAssertTrue(cliArgs.contains("PGDATA=/var/lib/postgresql/data/pgdata"))
    }

    func testPortAndMountIdentityStabilityAndPerformanceTelemetryHistory() async {
        var port = PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80, proto: "tcp")
        let initialPortID = port.id
        port.hostPort = 8081
        port.containerPort = 3000
        XCTAssertEqual(port.id, initialPortID, "PortMapping.id must remain stable while editing ports so TextField never loses focus")
        XCTAssertEqual(String(port.hostPort), "8081")

        var mount = MountAttachment(kind: .volume, source: "data", destination: "/data")
        let initialMountID = mount.id
        mount.source = "pgdata"
        mount.destination = "/var/lib/postgresql/data"
        XCTAssertEqual(mount.id, initialMountID, "MountAttachment.id must remain stable while editing paths")

        let (appState, _) = makeTestAppState()
        await appState.refreshAll(isUserInitiated: false)
        guard let runningContainer = appState.containers.first(where: { $0.state == .running }) else {
            XCTFail("Expected a running container in mock state")
            return
        }

        await appState.sampleContainerTelemetry(for: runningContainer.id)
        let samples = appState.containerTelemetryHistory[runningContainer.id] ?? []
        XCTAssertGreaterThanOrEqual(samples.count, 2)
        XCTAssertGreaterThan(samples.last?.memoryUsageBytes ?? 0, 0)
        XCTAssertGreaterThan(samples.last?.totalNetworkRxBytes ?? 0, 0)
        XCTAssertGreaterThan(samples.last?.totalDiskReadBytes ?? 0, 0)
        XCTAssertFalse(appState.systemTelemetryHistory.isEmpty)

        // Verify name and port conflict resolution
        let conflictingReq = ContainerCreateRequest(
            name: runningContainer.id,
            imageReference: "nginx:latest",
            publishedPorts: runningContainer.configuration.publishedPorts
        )
        let resolvedReq = appState.resolveCreateRequestConflicts(conflictingReq)
        XCTAssertNotEqual(resolvedReq.name, runningContainer.id)
        if let firstOrigPort = runningContainer.configuration.publishedPorts.first?.hostPort,
           let firstResolvedPort = resolvedReq.publishedPorts.first?.hostPort {
            XCTAssertNotEqual(firstResolvedPort, firstOrigPort)
        }
    }

    func testComposeStackParserDockerfileLinterAndFileBrowserParsing() {
        // 1. ComposeParser topological sort and service extraction
        let tpl = ComposeStackTemplate.allTemplates[0]
        let parsedStack = ComposeParser.parse(yaml: tpl.yamlContent)
        XCTAssertEqual(parsedStack.projectName, "nordic-web")
        XCTAssertEqual(parsedStack.services.count, 3)
        let topoNames = parsedStack.topologicalServices.map(\.serviceName)
        // 'db' and 'redis' must come before 'web'
        if let webIdx = topoNames.firstIndex(of: "web"),
           let dbIdx = topoNames.firstIndex(of: "db"),
           let redisIdx = topoNames.firstIndex(of: "redis") {
            XCTAssertLessThan(dbIdx, webIdx)
            XCTAssertLessThan(redisIdx, webIdx)
        } else {
            XCTFail("Expected db, redis, and web in topologicalServices")
        }

        // 2. DockerfileLinter diagnostics and quick fixes
        let unpinnedPostgresDockerfile = """
        FROM postgres:latest
        COPY init.sql /docker-entrypoint-initdb.d/
        RUN apt-get update && apt-get install curl
        """
        let diags = DockerfileLinter.analyze(unpinnedPostgresDockerfile)
        XCTAssertTrue(diags.contains(where: { $0.id.hasPrefix("unpinned-from") }))
        XCTAssertTrue(diags.contains(where: { $0.id.hasPrefix("missing-workdir") }))
        XCTAssertTrue(diags.contains(where: { $0.id.hasPrefix("apt-no-y") }))
        XCTAssertTrue(diags.contains(where: { $0.id == "postgres-pgdata" }))
        XCTAssertTrue(diags.contains(where: { $0.id == "missing-expose" }))

        // 3. ContainerFileBrowserView ls -la output parser
        let sampleLs = """
        total 24
        drwxr-xr-x    1 root     root          4096 Oct 16 12:00 .
        drwxr-xr-x    1 root     root          4096 Oct 16 12:00 ..
        drwxr-xr-x    2 root     root          4096 Oct 16 12:01 conf.d
        -rw-r--r--    1 root     root          1024 Oct 16 12:02 nginx.conf
        lrwxrwxrwx    1 root     root            11 Oct 16 12:03 access.log -> /dev/stdout
        """
        let parsedEntries = ContainerFileBrowserView.parseLsOutput(sampleLs, basePath: "/etc/nginx")
        XCTAssertEqual(parsedEntries.count, 3)
        XCTAssertEqual(parsedEntries.first?.name, "conf.d")
        XCTAssertTrue(parsedEntries.first?.isDirectory == true)
        XCTAssertTrue(parsedEntries.contains(where: { $0.name == "nginx.conf" && $0.sizeBytes == 1024 }))
        XCTAssertTrue(parsedEntries.contains(where: { $0.name == "access.log" && $0.isSymlink && $0.symlinkTarget == "/dev/stdout" }))
    }
}


