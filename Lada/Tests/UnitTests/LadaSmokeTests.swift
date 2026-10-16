import Testing
@testable import Lada

@Suite("Låda Smoke Tests")
struct LadaSmokeTests {
    @Test("Semantic version comparison")
    func semanticVersionComparison() {
        let v1 = SemanticVersion(parsing: "1.5.0")
        let v2 = SemanticVersion(parsing: "1.4.2")
        #expect(v1 != nil)
        #expect(v2 != nil)
        #expect(v1! > v2!)
    }
}
