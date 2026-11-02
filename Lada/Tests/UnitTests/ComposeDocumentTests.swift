import XCTest
@testable import Lada

final class ComposeDocumentTests: XCTestCase {
    private let base = """
    name: shop
    # The shop's services
    services:
      db:
        image: postgres:17-alpine   # pinned
        environment:
          POSTGRES_PASSWORD: secret
        volumes:
          - pgdata:/var/lib/postgresql/data

      web:
        image: nginx:1.31-alpine
        ports:
          - "8080:80"
        depends_on:
          - db

    volumes:
      pgdata:
    """

    func testServiceFromFormRoundTripsThroughTheParser() throws {
        let svc = ComposeServiceSpec(
            serviceName: "api",
            containerName: "shop-api",
            imageReference: "node:24-alpine",
            publishedPorts: [PortMapping(hostAddress: "127.0.0.1", hostPort: 3000, containerPort: 3000, proto: "tcp"),
                             PortMapping(hostAddress: "0.0.0.0", hostPort: 5353, containerPort: 53, proto: "udp")],
            environment: [KeyValueEntry(key: "NODE_ENV", value: "production"), KeyValueEntry(key: "GREETING", value: "hej: world"), KeyValueEntry(key: "DEBUG", value: "true")],
            volumes: [MountAttachment(kind: .volume, source: "apidata", destination: "/data", readOnly: false, volumeName: "apidata"),
                      MountAttachment(kind: .bind, source: "/Users/dev/app", destination: "/app", readOnly: true)],
            commandOverride: "npm start",
            dependsOn: ["db"],
            networkAliases: ["api.shop.test"]
        )
        let yaml = ComposeDocument.upsert(svc, in: base)
        let parsed = ComposeParser.parse(yaml: yaml)
        let api = try XCTUnwrap(parsed.services.first { $0.serviceName == "api" })
        XCTAssertTrue(api.imageReference.hasSuffix("node:24-alpine"), api.imageReference)
        XCTAssertEqual(api.containerName, "shop-api")
        XCTAssertEqual(api.publishedPorts.map { "\($0.hostAddress):\($0.hostPort)->\($0.containerPort)/\($0.proto)" },
                       ["127.0.0.1:3000->3000/tcp", "0.0.0.0:5353->53/udp"])
        XCTAssertEqual(api.environment.map(\.key), ["NODE_ENV", "GREETING", "DEBUG"])
        XCTAssertEqual(api.environment.first { $0.key == "GREETING" }?.value, "hej: world")
        XCTAssertEqual(api.environment.first { $0.key == "DEBUG" }?.value, "true")
        XCTAssertEqual(api.volumes.map(\.destination), ["/data", "/app"])
        XCTAssertTrue(api.volumes[1].readOnly)
        XCTAssertEqual(api.commandOverride, "npm start")
        XCTAssertEqual(api.dependsOn, ["db"])
        XCTAssertEqual(api.networkAliases, ["api.shop.test"])
        XCTAssertTrue(parsed.declaredVolumes.contains("apidata"), "new named volume is declared")
        // Everything else is untouched, including comments.
        XCTAssertTrue(yaml.contains("# The shop's services"))
        XCTAssertTrue(yaml.contains("image: postgres:17-alpine   # pinned"))
        XCTAssertEqual(parsed.services.map(\.serviceName).sorted(), ["api", "db", "web"])
    }

    func testReplaceRenameAndRemove() throws {
        var web = try XCTUnwrap(ComposeParser.parse(yaml: base).services.first { $0.serviceName == "web" })
        web.serviceName = "frontend"
        web.containerName = "shop-frontend"
        web.publishedPorts = [PortMapping(hostAddress: "127.0.0.1", hostPort: 8443, containerPort: 443, proto: "tcp")]
        let renamed = ComposeDocument.upsert(web, replacing: "web", in: base)
        let parsed = ComposeParser.parse(yaml: renamed)
        XCTAssertEqual(parsed.services.map(\.serviceName).sorted(), ["db", "frontend"])
        XCTAssertEqual(parsed.services.first { $0.serviceName == "frontend" }?.publishedPorts.first?.hostPort, 8443)
        XCTAssertTrue(renamed.contains("image: postgres:17-alpine   # pinned"))

        let removed = ComposeDocument.remove(service: "db", from: renamed)
        let afterRemove = ComposeParser.parse(yaml: removed)
        XCTAssertEqual(afterRemove.services.map(\.serviceName), ["frontend"])
        XCTAssertEqual(afterRemove.services.first?.dependsOn, [], "references to the removed service are dropped")
        XCTAssertFalse(removed.contains("depends_on:"), "an empty depends_on is removed")
        XCTAssertTrue(removed.contains("volumes:\n  pgdata:"), "top-level volumes are left alone")
    }

    func testAddingToAnEmptyFileCreatesTheServicesSection() {
        let svc = ComposeServiceSpec(serviceName: "cache", containerName: "", imageReference: "valkey/valkey:9.0-alpine")
        let yaml = ComposeDocument.upsert(svc, in: "name: tiny\n")
        XCTAssertEqual(ComposeParser.parse(yaml: yaml).services.map(\.serviceName), ["cache"])
        XCTAssertFalse(yaml.contains("container_name"), "the default container name is not written out")
    }

    func testQuoting() {
        XCTAssertEqual(ComposeDocument.quoted("plain"), "plain")
        XCTAssertEqual(ComposeDocument.quoted("a: b"), "\"a: b\"")
        XCTAssertEqual(ComposeDocument.quoted("true"), "\"true\"")
        XCTAssertEqual(ComposeDocument.quoted("5432"), "\"5432\"")
        XCTAssertEqual(ComposeDocument.quoted(""), "\"\"")
    }

    func testTemplatesAreConsistentAndGetFreshSecrets() throws {
        XCTAssertGreaterThanOrEqual(ComposeStackTemplate.allTemplates.count, 9)
        for template in ComposeStackTemplate.allTemplates {
            let a = template.instantiate(), b = template.instantiate()
            XCTAssertFalse(a.contains("{{secret"), "\(template.id): placeholder left")
            if template.yamlContent.contains("{{secret") { XCTAssertNotEqual(a, b, "\(template.id): secrets are random per use") }
            let stack = ComposeParser.parse(yaml: a)
            XCTAssertEqual(stack.projectName, template.projectName, template.id)
            XCTAssertFalse(stack.services.isEmpty, template.id)
            let names = Set(stack.services.map(\.serviceName))
            for svc in stack.services {
                XCTAssertFalse(svc.imageReference.isEmpty, "\(template.id)/\(svc.serviceName)")
                for dep in svc.dependsOn { XCTAssertTrue(names.contains(dep), "\(template.id): \(svc.serviceName) waits for unknown \(dep)") }
                XCTAssertTrue(ValidationUtils.validateContainerCreateRequest(
                    ComposeParser.buildContainerRequest(for: svc, projectName: stack.projectName, networkName: "default", defaultCPUs: 2, defaultMemoryMB: 1024)
                ).isEmpty, "\(template.id)/\(svc.serviceName)")
            }
        }
        // Services that share a password get the same generated value.
        let wp = ComposeParser.parse(yaml: try XCTUnwrap(ComposeStackTemplate.allTemplates.first { $0.id == "wordpress-mysql" }).instantiate())
        let dbPassword = wp.services.first { $0.serviceName == "mysql" }?.environment.first { $0.key == "MYSQL_PASSWORD" }?.value
        let wpPassword = wp.services.first { $0.serviceName == "wordpress" }?.environment.first { $0.key == "WORDPRESS_DB_PASSWORD" }?.value
        XCTAssertNotNil(dbPassword)
        XCTAssertEqual(dbPassword, wpPassword)
        XCTAssertTrue(wp.services.first { $0.serviceName == "wordpress" }?.imageReference.contains("wordpress") == true, "WordPress runs the wordpress image, not nginx")
    }
}

