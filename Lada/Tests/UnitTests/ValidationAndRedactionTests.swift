import XCTest
@testable import Lada

final class ValidationAndRedactionTests: XCTestCase {
    func testValidationOfResourceNamesCIDRsAndMACAddresses() {
        XCTAssertTrue(ValidationUtils.isValidContainerName("web-api-01"))
        XCTAssertFalse(ValidationUtils.isValidContainerName("-invalid-start"))
        XCTAssertFalse(ValidationUtils.isValidVolumeName("spaces not allowed"))

        XCTAssertNil(ValidationUtils.validateIPv4CIDR("192.168.64.0/24"))
        XCTAssertNotNil(ValidationUtils.validateIPv4CIDR("999.168.64.0/24"))
        XCTAssertNotNil(ValidationUtils.validateIPv4CIDR("192.168.64.0/35"))

        XCTAssertNil(ValidationUtils.validateIPv6CIDR("fd00:abcd::/64"))
        XCTAssertNotNil(ValidationUtils.validateIPv6CIDR("not-ipv6"))

        XCTAssertTrue(ValidationUtils.isValidMACAddress("02:42:ac:11:00:02"))
        XCTAssertFalse(ValidationUtils.isValidMACAddress("02:42:ac:11:00:ZZ"))
    }

    func testContainerRequestValidationDetectsDuplicatePortsInvalidEnvKeysAndUnsupportedRestartPolicy() {
        var req = ContainerCreateRequest(name: "valid-name", imageReference: "alpine:latest")
        req.publishedPorts = [
            PortMapping(hostAddress: "0.0.0.0", hostPort: 8080, containerPort: 80, proto: "tcp"),
            PortMapping(hostAddress: "0.0.0.0", hostPort: 8080, containerPort: 8080, proto: "tcp")
        ]
        req.environmentVariables = [
            KeyValueEntry(key: "123_INVALID_KEY", value: "val")
        ]
        req.requestedUnsupportedRestartPolicy = "always"

        let errors = ValidationUtils.validateContainerCreateRequest(req)
        XCTAssertTrue(errors.contains(where: { $0.contains("Duplicate published host port mapping") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("Environment variable key") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("not supported by Apple's `container` runtime") }))
    }

    func testSecretRedactorMasksEnvVarsTokensAndCLIArguments() {
        XCTAssertTrue(SecretRedactor.isSensitiveKey("DATABASE_PASSWORD"))
        XCTAssertTrue(SecretRedactor.isSensitiveKey("GITHUB_TOKEN"))
        XCTAssertTrue(SecretRedactor.isSensitiveKey("AWS_SECRET_ACCESS_KEY"))
        XCTAssertFalse(SecretRedactor.isSensitiveKey("PORT"))

        let rawText = """
        Launching with API_KEY=sk-live-987654321 and Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig
        """
        let redacted = SecretRedactor.redact(rawText)
        XCTAssertFalse(redacted.contains("sk-live-987654321"))
        XCTAssertFalse(redacted.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertTrue(redacted.contains("<REDACTED>"))

        let cliArgs = [
            "run",
            "-e", "POSTGRES_PASSWORD=supersecret",
            "-e", "APP_ENV=production",
            "postgres:16"
        ]
        let redactedArgs = SecretRedactor.redactArguments(cliArgs)
        XCTAssertEqual(redactedArgs, [
            "run",
            "-e", "POSTGRES_PASSWORD=<REDACTED>",
            "-e", "APP_ENV=production",
            "postgres:16"
        ])
    }

    func testCLIErrorClassificationAndRemediation() {
        let daemonStoppedErr = LadaError.classifyCLIError(
            command: ["container", "list"],
            exitStatus: 1,
            stderr: "Error: connection refused: apiserver is not running",
            stdout: ""
        )
        XCTAssertEqual(daemonStoppedErr.category, .apiServerFailure)
        XCTAssertFalse(daemonStoppedErr.suggestedRemediation.isEmpty)

        let authErr = LadaError.classifyCLIError(
            command: ["container", "image", "pull", "ghcr.io/org/private:latest"],
            exitStatus: 1,
            stderr: "Error: unauthorized: authentication required",
            stdout: ""
        )
        XCTAssertEqual(authErr.category, .registryAuthenticationError)
    }

    func testInMemoryCredentialStoreRoundTrip() throws {
        let store = InMemoryCredentialStore()
        try store.savePassword("token-xyz-123", for: "ghcr.io", account: "octocat")
        XCTAssertEqual(try store.loadPassword(for: "ghcr.io", account: "octocat"), "token-xyz-123")
        try store.deletePassword(for: "ghcr.io", account: "octocat")
        XCTAssertNil(try store.loadPassword(for: "ghcr.io", account: "octocat"))
    }
}
