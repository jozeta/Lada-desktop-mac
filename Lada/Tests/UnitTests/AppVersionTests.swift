import XCTest
@testable import Lada

/// The version lives in three places; `Scripts/bump-version.sh` updates them together.
final class AppVersionTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    func testInfoPlistMatchesAppVersion() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Lada/Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, AppVersion.marketing)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "\(AppVersion.build)")
    }

    func testXcodeProjectMatchesAppVersion() throws {
        let pbx = try String(contentsOf: root.appendingPathComponent("Lada.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(pbx.contains("MARKETING_VERSION = \(AppVersion.marketing);"))
        XCTAssertTrue(pbx.contains("CURRENT_PROJECT_VERSION = \(AppVersion.build);"))
        XCTAssertFalse(pbx.range(of: #"MARKETING_VERSION = (?!\#(NSRegularExpression.escapedPattern(for: AppVersion.marketing));)"#, options: .regularExpression) != nil)
    }

    func testInfoPlistBundleIDMatches() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Lada/Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, AppVersion.bundleIdentifier)
    }

    /// In a foreign bundle (the test runner, Xcode) the constants are shown, not that app's version.
    func testIgnoresOtherAppsBundles() {
        XCTAssertEqual(AppVersion.display(bundle: Bundle.main), "\(AppVersion.marketing) (\(AppVersion.build))")
    }

    func testChangelogHasASectionForThisVersion() throws {
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        XCTAssertTrue(changelog.contains("## [\(AppVersion.marketing)]"))
    }
}
