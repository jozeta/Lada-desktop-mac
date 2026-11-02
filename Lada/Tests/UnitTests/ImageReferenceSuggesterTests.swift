import XCTest
@testable import Lada

final class ImageReferenceSuggesterTests: XCTestCase {
    private let catalog = DockerHubService.curatedCatalog
    private let local = ["docker.io/library/nginx:latest", "docker.io/library/alpine:latest", "localhost:5000/team/api:dev"]

    func testRepositoryPrefixSuggestsLocalFirstThenCatalog() {
        let s = ImageReferenceSuggester.suggestions(for: "ngi", localReferences: local, catalog: catalog)
        XCTAssertEqual(s.first?.reference, "docker.io/library/nginx:latest")
        XCTAssertEqual(s.first?.source, .local)
        XCTAssertTrue(s.contains { $0.source == .catalog && $0.reference.hasPrefix("nginx:") })
    }

    func testPrefixMatchesRankAboveSubstringMatches() {
        let s = ImageReferenceSuggester.suggestions(for: "post", localReferences: [], catalog: catalog)
        XCTAssertEqual(s.first.map { ImageReferenceSuggester.shortName($0.reference) }, "postgres")
    }

    func testNamespacedRepositories() {
        let s = ImageReferenceSuggester.suggestions(for: "graf", localReferences: [], catalog: catalog)
        XCTAssertTrue(s.contains { $0.reference.hasPrefix("grafana/grafana:") })
        let valkey = ImageReferenceSuggester.suggestions(for: "valkey/valkey:9", localReferences: [], catalog: catalog)
        XCTAssertEqual(valkey.map(\.reference), ["valkey/valkey:9.0-alpine"])
    }

    func testTagCompletion() {
        let s = ImageReferenceSuggester.suggestions(for: "postgres:1", localReferences: [], catalog: catalog)
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.allSatisfy { $0.reference.hasPrefix("postgres:1") })
    }

    func testRegistryPortIsNotATag() {
        let s = ImageReferenceSuggester.suggestions(for: "localhost:5000/te", localReferences: local, catalog: catalog)
        XCTAssertEqual(s.first?.reference, "localhost:5000/team/api:dev")
    }

    func testExactMatchAndEmptyQueryGiveNothing() {
        XCTAssertTrue(ImageReferenceSuggester.suggestions(for: "", localReferences: local, catalog: catalog).isEmpty)
        XCTAssertFalse(ImageReferenceSuggester.suggestions(for: "nginx:latest", localReferences: [], catalog: catalog).contains { $0.reference == "nginx:latest" })
    }

    func testShortNames() {
        XCTAssertEqual(ImageReferenceSuggester.shortName("docker.io/library/nginx:1.31"), "nginx")
        XCTAssertEqual(ImageReferenceSuggester.shortName("ghcr.io/acme/tool:1"), "acme/tool")
        XCTAssertEqual(ImageReferenceSuggester.shortName("alpine@sha256:abc"), "alpine")
        XCTAssertEqual(ImageReferenceSuggester.shortName("localhost:5000/team/api"), "team/api")
    }
}
