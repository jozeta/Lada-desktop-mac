import XCTest
@testable import Lada

final class SecretHandlingTests: XCTestCase {
    func testSecretValuesNeverAppearInArguments() {
        let req = ContainerCreateRequest(
            name: "db", imageReference: "postgres:17-alpine",
            environmentVariables: [
                KeyValueEntry(key: "POSTGRES_PASSWORD", value: "hunter2-hunter2", isSecret: true),
                KeyValueEntry(key: "API_TOKEN", value: "tok-123"),            // sensitive by name
                KeyValueEntry(key: "POSTGRES_DB", value: "appdb")
            ]
        )
        let args = req.buildCLIArguments()
        XCTAssertFalse(args.contains { $0.contains("hunter2") || $0.contains("tok-123") })
        XCTAssertTrue(args.contains("POSTGRES_PASSWORD"))
        XCTAssertTrue(args.contains("API_TOKEN"))
        XCTAssertTrue(args.contains("POSTGRES_DB=appdb"))
        XCTAssertEqual(req.secretEnvironment(), ["POSTGRES_PASSWORD": "hunter2-hunter2", "API_TOKEN": "tok-123"])
    }

    func testEmptyValueIsSetEmptyNotInheritedFromHost() {
        let req = ContainerCreateRequest(name: "x", imageReference: "alpine:latest", environmentVariables: [KeyValueEntry(key: "HOME", value: "")])
        let args = req.buildCLIArguments()
        XCTAssertTrue(args.contains("HOME="))
        XCTAssertFalse(zip(args, args.dropFirst()).contains { $0 == "-e" && $1 == "HOME" })
    }

    func testNoWellKnownPasswordIsInjected() {
        let req = ContainerCreateRequest(name: "db", imageReference: "docker.io/library/postgres:17")
        let args = req.buildCLIArguments()
        XCTAssertFalse(args.contains { $0.hasPrefix("POSTGRES_PASSWORD") })
        XCTAssertTrue(args.contains("PGDATA=/var/lib/postgresql/data/pgdata"), "ext4 lost+found workaround stays")
        XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(req).contains { $0.contains("POSTGRES_PASSWORD") })

        let mysql = ContainerCreateRequest(name: "m", imageReference: "mariadb:11.8")
        XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(mysql).contains { $0.contains("root password") })
    }

    func testSubstringImageNamesAreNotTreatedAsDatabases() {
        let exporter = ContainerCreateRequest(name: "exp", imageReference: "prometheuscommunity/postgres-exporter:latest")
        XCTAssertFalse(exporter.buildCLIArguments().contains { $0.hasPrefix("PGDATA") })
        XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(exporter).isEmpty)
    }

    func testPresetsGetFreshRandomSecrets() throws {
        let postgres = try XCTUnwrap(DockerHubService.curatedCatalog.first { $0.slug == "postgres" })
        let a = postgres.buildDeployRequest(selectedTag: "17-alpine")
        let b = postgres.buildDeployRequest(selectedTag: "17-alpine")
        let pa = try XCTUnwrap(a.environmentVariables.first { $0.key == "POSTGRES_PASSWORD" })
        let pb = try XCTUnwrap(b.environmentVariables.first { $0.key == "POSTGRES_PASSWORD" })
        XCTAssertNotEqual(pa.value, pb.value)
        XCTAssertEqual(pa.value.count, 24)
        XCTAssertTrue(pa.isSecret)
        XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(a).isEmpty)
        for item in DockerHubService.curatedCatalog {
            let req = item.buildDeployRequest(selectedTag: item.availableTags.first ?? "latest")
            XCTAssertFalse(req.environmentVariables.contains { $0.isSecret && $0.value == "generated-on-deploy" }, item.slug)
            XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(req).isEmpty, "\(item.slug): \(ValidationUtils.validateContainerCreateRequest(req))")
        }
    }

    func testGeneratorAlphabetAndUniqueness() {
        var seen = Set<String>()
        for _ in 0..<200 {
            let p = SecretGenerator.password()
            XCTAssertEqual(p.count, 24)
            XCTAssertTrue(p.allSatisfy { $0.isLetter || $0.isNumber })
            XCTAssertTrue(seen.insert(p).inserted)
        }
        XCTAssertEqual(SecretGenerator.password(length: 7).count, 7)
    }
}
