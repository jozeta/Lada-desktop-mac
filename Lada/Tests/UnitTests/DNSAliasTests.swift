import XCTest
@testable import Lada

/// DNS aliases on network attachments (`--network <name>,alias=<alias>`, container 1.6.0).
final class DNSAliasTests: XCTestCase {
    func testAliasValidation() {
        for ok in ["db.test", "api.example.test.", ".api.example.test", "db", "a-1.b2"] {
            XCTAssertTrue(ValidationUtils.isValidDNSAlias(ok), ok)
        }
        for bad in ["", ".", "-db.test", "db-.test", "db..test", "db,alias=x", "db=x", "with space.test", String(repeating: "a", count: 64) + ".test"] {
            XCTAssertFalse(ValidationUtils.isValidDNSAlias(bad), bad)
        }
        XCTAssertEqual(ValidationUtils.dnsLabelCount(".api.example.test"), 3)
        XCTAssertEqual(ValidationUtils.dnsLabelCount("db."), 1)
    }

    func testRequestValidationAndArguments() {
        var req = ContainerCreateRequest(name: "web", imageReference: "nginx:latest", networkName: "default", dnsAliases: ["web.test", ".web.test"])
        XCTAssertEqual(ValidationUtils.validateContainerCreateRequest(req), [])
        let args = req.buildCLIArguments()
        let netIndex = try? XCTUnwrap(args.firstIndex(of: "--network"))
        XCTAssertEqual(netIndex.map { args[$0 + 1] }, "default,alias=web.test,alias=.web.test")

        req.dnsAliases = ["web.test", "WEB.test", "bad,alias"]
        let issues = ValidationUtils.validateContainerCreateRequest(req)
        XCTAssertTrue(issues.contains { $0.contains("'bad,alias'") })
        XCTAssertTrue(issues.contains { $0.contains("only once") })

        req.dnsAliases = (0..<33).map { "a\($0).test" }
        XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(req).contains { $0.contains("At most 32") })
    }

    func testParsesAliasesFromContainerConfigurationAndKeepsThemWhenCloning() throws {
        // Shape of AttachmentConfiguration in container 1.6: aliases sit in `options` and the key is
        // omitted when empty.
        let json = #"""
        [{"configuration":{"id":"api","image":{"reference":"docker.io/library/nginx:latest"},
          "networks":[{"network":"default","options":{"hostname":"api","aliases":["api.test",".api.test"]}},
                      {"network":"backend","options":{"hostname":"api"}}],
          "resources":{"cpus":2,"memoryInBytes":1073741824}},
          "id":"api","status":{"state":"stopped"}}]
        """#
        let container = try XCTUnwrap(try ContainerOutputParser.parseContainers(jsonString: json).first)
        XCTAssertEqual(container.configuration.configuredNetworks, ["default", "backend"])
        XCTAssertEqual(container.configuration.networkAliases["default"], ["api.test", ".api.test"])
        XCTAssertNil(container.configuration.networkAliases["backend"])
    }

    // MARK: - Compose

    private let composeYAML = """
    name: shop
    services:
      api:
        image: docker.io/library/node:22-alpine
        networks:
          backend:
            aliases:
              - api.internal.test
              - Orders
      db:
        image: docker.io/library/postgres:17-alpine
        networks:
          backend:
            aliases: [database, pg.test]
      cache:
        image: docker.io/library/redis:7-alpine
        networks:
          - backend
    networks:
      backend:
    """

    func testComposeParsesNetworkAliasesInBlockAndFlowForm() throws {
        let stack = ComposeParser.parse(yaml: composeYAML)
        let api = try XCTUnwrap(stack.services.first { $0.serviceName == "api" })
        XCTAssertEqual(api.networks, ["backend"])
        XCTAssertEqual(api.networkAliases, ["api.internal.test", "orders"])
        let db = try XCTUnwrap(stack.services.first { $0.serviceName == "db" })
        XCTAssertEqual(db.networkAliases, ["database", "pg.test"])
        XCTAssertEqual(stack.services.first { $0.serviceName == "cache" }?.networks, ["backend"])
        XCTAssertEqual(stack.services.first { $0.serviceName == "cache" }?.networkAliases, [])
    }

    func testServiceAliasesWithDefaultDomain() throws {
        let db = try XCTUnwrap(ComposeParser.parse(yaml: composeYAML).services.first { $0.serviceName == "db" })
        let result = ComposeParser.serviceDNSAliases(for: db, defaultDNSDomain: "test", claimedNames: [])
        XCTAssertEqual(result.aliases, ["db", "database", "pg.test"])
        XCTAssertTrue(result.notes.isEmpty)

        let req = ComposeParser.buildContainerRequest(for: db, projectName: "shop", networkName: "default", defaultCPUs: 2, defaultMemoryMB: 1024, dnsAliases: result.aliases)
        XCTAssertTrue(req.buildCLIArguments().contains("default,alias=db,alias=database,alias=pg.test"))
    }

    func testSingleLabelAliasesAreSkippedWithoutDefaultDomain() throws {
        let db = try XCTUnwrap(ComposeParser.parse(yaml: composeYAML).services.first { $0.serviceName == "db" })
        let result = ComposeParser.serviceDNSAliases(for: db, defaultDNSDomain: nil, claimedNames: [])
        XCTAssertEqual(result.aliases, ["pg.test"])
        XCTAssertEqual(result.notes.count, 2)
        XCTAssertTrue(result.notes[0].contains("dns.domain"))
    }

    func testAliasesClaimedByOtherContainersAreSkipped() throws {
        let db = try XCTUnwrap(ComposeParser.parse(yaml: composeYAML).services.first { $0.serviceName == "db" })
        var cfg = ContainerConfigurationModel()
        cfg.networkAliases = ["default": ["db", "PG.test."]]
        let other = ContainerModel(id: "other-db", imageReference: "postgres", state: .running, rawState: "running", creationDate: Date(), startedDate: nil, configuration: cfg, networks: [], rawInspectJSON: nil)
        let claimed = ComposeParser.claimedDNSNames(in: [other], network: "default", defaultDNSDomain: "test", excluding: "shop-db")
        XCTAssertEqual(claimed, ["db.test", "pg.test"])
        let result = ComposeParser.serviceDNSAliases(for: db, defaultDNSDomain: "test", claimedNames: claimed)
        XCTAssertEqual(result.aliases, ["database"])
        XCTAssertEqual(result.notes.filter { $0.contains("already used") }.count, 2)
        // A container never conflicts with its own previous aliases.
        XCTAssertTrue(ComposeParser.claimedDNSNames(in: [other], network: "default", defaultDNSDomain: "test", excluding: "other-db").isEmpty)
    }
}
