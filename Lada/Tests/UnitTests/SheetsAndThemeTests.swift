import XCTest
import Combine
import SwiftUI
@testable import Lada

final class CreateSheetHelperTests: XCTestCase {
    func testSubnetOverlap() {
        XCTAssertTrue(IPv4.overlaps("192.168.64.0/24", "192.168.64.128/25"))
        XCTAssertTrue(IPv4.overlaps("10.0.0.0/8", "10.20.0.0/16"))
        XCTAssertFalse(IPv4.overlaps("192.168.64.0/24", "192.168.65.0/24"))
        XCTAssertFalse(IPv4.overlaps("garbage", "192.168.65.0/24"))
    }

    func testSuggestsTheFirstFreeSubnet() {
        XCTAssertEqual(SubnetSuggester.nextFree(avoiding: []), "192.168.70.0/24")
        XCTAssertEqual(SubnetSuggester.nextFree(avoiding: ["192.168.70.0/24", "192.168.71.0/24"]), "192.168.72.0/24")
        // A wide network blocks everything inside it.
        XCTAssertEqual(SubnetSuggester.nextFree(avoiding: ["192.168.64.0/20"]), "192.168.80.0/24")
    }

    func testByteSizeSpec() {
        XCTAssertEqual(ByteSizeSpec.bytes("512M"), 512 * 1024 * 1024)
        XCTAssertEqual(ByteSizeSpec.bytes("20g"), 20 * 1024 * 1024 * 1024)
        XCTAssertEqual(ByteSizeSpec.bytes("1.5T"), Int64(1.5 * 1024 * 1024 * 1024 * 1024))
        XCTAssertEqual(ByteSizeSpec.bytes("100MiB"), 100 * 1024 * 1024)
        XCTAssertEqual(ByteSizeSpec.bytes("4096"), 4096)
        XCTAssertNil(ByteSizeSpec.bytes("lots"))
        XCTAssertNil(ByteSizeSpec.bytes("5 GB please"))
    }

    func testNameTakenIgnoresCase() {
        XCTAssertTrue(CreateSheetChecks.nameTaken("PgData", in: ["pgdata"]))
        XCTAssertFalse(CreateSheetChecks.nameTaken("pgdata2", in: ["pgdata"]))
    }

    @MainActor
    func testRegistryHosts() {
        XCTAssertTrue(RegistriesView.isValidRegistryHost("ghcr.io"))
        XCTAssertTrue(RegistriesView.isValidRegistryHost("localhost:5000"))
        XCTAssertTrue(RegistriesView.isValidRegistryHost("10.0.0.5:443"))
        XCTAssertFalse(RegistriesView.isValidRegistryHost("https://ghcr.io"))
        XCTAssertFalse(RegistriesView.isValidRegistryHost("ghcr.io/owner"))
        XCTAssertFalse(RegistriesView.isValidRegistryHost("-bad.io"))
    }
}

@MainActor
final class ThemeAndDensityTests: XCTestCase {
    func testEveryAccentThemeHasDistinctColours() {
        let all = AccentThemeChoice.allCases.map { NordicTheme.accentRGB($0) }
        XCTAssertEqual(AccentThemeChoice.allCases.count, 10)
        for (i, a) in all.enumerated() {
            for b in all.dropFirst(i + 1) {
                XCTAssertFalse(a.0 == b.0 && a.1 == b.1, "two themes share colours")
            }
        }
    }

    func testDefaultAccentFollowsTheSavedChoice() {
        let key = "lada.accentThemeChoice"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.set(AccentThemeChoice.lingonberry.rawValue, forKey: key)
        XCTAssertEqual(AccentThemeChoice.current, .lingonberry)
        UserDefaults.standard.set("not-a-theme", forKey: key)
        XCTAssertEqual(AccentThemeChoice.current, .nordicFjord)
    }

    func testDensityValues() {
        XCTAssertEqual(UIDensityMode.compact.controlSize, .small)
        XCTAssertEqual(UIDensityMode.comfortable.controlSize, .regular)
        XCTAssertLessThan(UIDensityMode.compact.paddingScale, UIDensityMode.comfortable.paddingScale)
        XCTAssertLessThan(UIDensityMode.compact.minRowHeight, UIDensityMode.comfortable.minRowHeight)
    }

    /// Changing a setting must re-render the main window, not only the Settings page.
    func testPreferenceChangesRepublishAppState() {
        let prefs = AppPreferences()
        let state = AppState(preferences: prefs, injectedService: MockContainerRuntimeService())
        var published = 0
        let token = state.objectWillChange.sink { published += 1 }
        let original = prefs.uiDensityModeRaw
        defer { prefs.uiDensityModeRaw = original; token.cancel() }
        prefs.uiDensityModeRaw = original == "compact" ? "comfortable" : "compact"
        XCTAssertGreaterThan(published, 0)
    }
}
