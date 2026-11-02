import XCTest
@testable import Lada

final class StackTemplateTests: XCTestCase {
    func testEveryTemplateParsesWithPinnedImagesAndNoLeftoverPlaceholders() {
        XCTAssertGreaterThanOrEqual(ComposeStackTemplate.allTemplates.count, 25)
        XCTAssertEqual(Set(ComposeStackTemplate.allTemplates.map(\.id)).count, ComposeStackTemplate.allTemplates.count, "duplicate template id")
        for template in ComposeStackTemplate.allTemplates {
            let yaml = template.instantiate()
            XCTAssertFalse(yaml.contains("{{"), "\(template.id) left a placeholder")
            let parsed = ComposeParser.parse(yaml: yaml)
            XCTAssertEqual(parsed.projectName, template.projectName, template.id)
            XCTAssertFalse(parsed.services.isEmpty, template.id)
            for svc in parsed.services {
                XCTAssertTrue(svc.imageReference.contains(":"), "\(template.id)/\(svc.serviceName) has no tag")
                XCTAssertFalse(svc.imageReference.hasSuffix(":latest"), "\(template.id)/\(svc.serviceName) floats on :latest")
                for dep in svc.dependsOn {
                    XCTAssertTrue(parsed.services.contains { $0.serviceName == dep }, "\(template.id): unknown dependency \(dep)")
                }
            }
        }
    }

    /// Templates don't claim each other's Mac ports, except the well-known database ports that
    /// several stacks publish on purpose (only one of them runs at a time).
    func testHostPortsDontCollideAcrossTemplates() {
        let shared: Set<UInt16> = [5432, 6379, 5000, 2222, 3000, 3001, 8000, 4222, 8222, 1025, 8025, 8200, 9090]
        var owner: [UInt16: String] = [:]
        for template in ComposeStackTemplate.allTemplates {
            for svc in ComposeParser.parse(yaml: template.instantiate()).services {
                for port in svc.publishedPorts where !shared.contains(port.hostPort) {
                    if let other = owner[port.hostPort], other != template.id {
                        XCTFail("\(template.id) and \(other) both publish \(port.hostPort)")
                    }
                    owner[port.hostPort] = template.id
                }
            }
        }
    }

    func testSecretsAreGeneratedPerUse() {
        let template = ComposeStackTemplate.allTemplates.first { $0.id == "mongo-express" }!
        let a = template.instantiate(), b = template.instantiate()
        XCTAssertNotEqual(a, b)
        // The same placeholder gets the same value inside one stack (the UI uses the DB password).
        let parsed = ComposeParser.parse(yaml: a)
        let root = parsed.services.first { $0.serviceName == "mongo" }!.environment.first { $0.key == "MONGO_INITDB_ROOT_PASSWORD" }!.value
        let url = parsed.services.first { $0.serviceName == "mongo-express" }!.environment.first { $0.key == "ME_CONFIG_MONGODB_URL" }!.value
        XCTAssertTrue(url.contains(root))
    }
}

final class ComposeCommandTests: XCTestCase {
    func testShellWords() {
        XCTAssertEqual(ShellWords.split(#"sh -c "echo '<?php phpinfo();' > x && run""#), ["sh", "-c", "echo '<?php phpinfo();' > x && run"])
        XCTAssertEqual(ShellWords.split("a  'b c'  d\\ e"), ["a", "b c", "d e"])
        XCTAssertEqual(ShellWords.split(#"say "a \"quoted\" word""#), ["say", #"a "quoted" word"#])
        XCTAssertEqual(ShellWords.split("''"), [""])
        XCTAssertEqual(ShellWords.split("   "), [])
    }

    func testListForm() {
        XCTAssertEqual(ShellWords.composeCommand(#"["sh", "-c", "echo hi"]"#), ["sh", "-c", "echo hi"])
    }

    /// `command:` replaces CMD and keeps the image's entrypoint (so init scripts still run).
    func testCommandKeepsTheEntrypoint() {
        let yaml = ComposeStackTemplate.allTemplates.first { $0.id == "keycloak-postgres" }!.instantiate()
        let svc = ComposeParser.parse(yaml: yaml).services.first { $0.serviceName == "keycloak" }!
        let req = ComposeParser.buildContainerRequest(for: svc, projectName: "keycloak", networkName: "default", defaultCPUs: 2, defaultMemoryMB: 1024)
        XCTAssertEqual(req.entrypointOverride, "")
        XCTAssertEqual(req.commandArguments, ["start-dev"])

        let lamp = ComposeParser.parse(yaml: ComposeStackTemplate.allTemplates.first { $0.id == "lamp" }!.instantiate())
        let web = lamp.services.first { $0.serviceName == "web" }!
        let webReq = ComposeParser.buildContainerRequest(for: web, projectName: "lamp", networkName: "default", defaultCPUs: 2, defaultMemoryMB: 1024)
        XCTAssertEqual(webReq.commandArguments.count, 3)
        XCTAssertEqual(webReq.commandArguments.first, "sh")
        XCTAssertTrue(webReq.commandArguments.last!.hasSuffix("exec apache2-foreground"))
    }
}

final class ComposeResourceTests: XCTestCase {
    func testMemLimitAndCpus() {
        let yaml = """
        name: res
        services:
          app:
            image: example/app:1
            mem_limit: 1536m
            cpus: "1.5"
        """
        let svc = ComposeParser.parse(yaml: yaml).services[0]
        XCTAssertEqual(svc.memoryLimitMB, 1536)
        XCTAssertEqual(svc.cpuLimit, 2)
        let req = ComposeParser.buildContainerRequest(for: svc, projectName: "res", networkName: "default", defaultCPUs: 4, defaultMemoryMB: 1024)
        XCTAssertEqual(req.memoryMB, 1536)
        XCTAssertEqual(req.cpus, 2)
        // Written back by the stack builder in the same form.
        let block = ComposeDocument.serviceBlock(svc, projectName: "res")
        XCTAssertTrue(block.contains("mem_limit: 1536m"))
        XCTAssertTrue(block.contains("cpus: 2"))
        XCTAssertEqual(ComposeParser.parse(yaml: "name: res\nservices:\n" + block).services[0].memoryLimitMB, 1536)
    }

    func testDefaultsWithoutLimits() {
        let svc = ComposeParser.parse(yaml: "services:\n  app:\n    image: example/app:1\n").services[0]
        let req = ComposeParser.buildContainerRequest(for: svc, projectName: "x", networkName: "default", defaultCPUs: 4, defaultMemoryMB: 1024)
        XCTAssertEqual(req.memoryMB, 1024)
        XCTAssertEqual(req.cpus, 4)
    }

    func testMetabaseGetsEnoughMemory() {
        let parsed = ComposeParser.parse(yaml: ComposeStackTemplate.allTemplates.first { $0.id == "metabase-postgres" }!.instantiate())
        XCTAssertEqual(parsed.services.first { $0.serviceName == "metabase" }?.memoryLimitMB, 2048)
    }
}
