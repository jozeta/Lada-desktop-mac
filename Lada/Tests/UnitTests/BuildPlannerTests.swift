import XCTest
@testable import Lada

final class BuildPlannerTests: XCTestCase {
    /// Output of a failing `container build --progress plain` on container 1.6.1.
    private let failedBuild = """
    #1 [resolver] fetching image...docker.io/library/alpine:latest
    #2 [internal] load build definition from Dockerfile
    #3 [internal] load .dockerignore
    #5 [linux/arm64 1/3] RUN echo step-one
    #6 [linux/arm64 2/3] RUN echo about-to-fail && exit 3
    #6 0.025 about-to-fail
    #6 ERROR: process "/bin/sh -c echo about-to-fail && exit 3" did not complete successfully: exit code: 3
     > [linux/arm64 2/3] RUN echo about-to-fail && exit 3:
    Error: unknown: "failed to solve: process "/bin/sh -c echo about-to-fail && exit 3" did not complete successfully: exit code: 3"
    """

    func testProgressAndFailureFromRealOutput() {
        XCTAssertEqual(BuildPlanner.progress(in: failedBuild), .init(step: 2, total: 3, description: "RUN echo about-to-fail && exit 3"))
        XCTAssertEqual(BuildPlanner.failureSummary(in: failedBuild), "process \"/bin/sh -c echo about-to-fail && exit 3\" did not complete successfully: exit code: 3")
        XCTAssertEqual(BuildPlanner.progress(in: "#6 [builder 3/7] RUN go build ./...")?.step, 3)
        XCTAssertNil(BuildPlanner.progress(in: "#2 [internal] load build definition"))
        XCTAssertEqual(BuildPlanner.failureSummary(in: "Error: no such file: Containerfile"), "no such file: Containerfile")
    }

    func testDetectsBuildFilesInPreferenceOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lada-build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(BuildPlanner.detectBuildFile(in: dir.path))
        try "FROM alpine".write(to: dir.appendingPathComponent("api.Dockerfile"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BuildPlanner.detectBuildFile(in: dir.path), dir.appendingPathComponent("api.Dockerfile").path)
        try "FROM alpine".write(to: dir.appendingPathComponent("Dockerfile"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BuildPlanner.detectBuildFile(in: dir.path), dir.appendingPathComponent("Dockerfile").path)
        try "FROM alpine".write(to: dir.appendingPathComponent("Containerfile"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BuildPlanner.detectBuildFile(in: dir.path), dir.appendingPathComponent("Containerfile").path)
    }

    func testRelativeBuildFileResolvesInsideTheFolder() {
        XCTAssertEqual(BuildPlanner.resolvedBuildFile("Containerfile", in: "/work/app"), "/work/app/Containerfile")
        XCTAssertEqual(BuildPlanner.resolvedBuildFile("/elsewhere/Dockerfile", in: "/work/app"), "/elsewhere/Dockerfile")
    }

    func testImageNames() {
        XCTAssertEqual(BuildPlanner.suggestedImageName(for: "/Users/dev/My Web App"), "local/my-web-app:latest")
        for ok in ["local/app:latest", "app", "ghcr.io/acme/tool:1.0", "localhost:5000/team/api:dev"] {
            XCTAssertNil(BuildPlanner.imageNameProblem(ok), ok)
        }
        for bad in ["", "My App", "local/App:latest", "app:", "-app"] {
            XCTAssertNotNil(BuildPlanner.imageNameProblem(bad), bad)
        }
    }
}
