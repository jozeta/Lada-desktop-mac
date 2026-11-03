import Foundation

/// Låda's version. `Scripts/bump-version.sh` keeps this, `Lada/Resources/Info.plist` and the
/// Xcode project in step (a test checks they match); every commit bumps it.
public enum AppVersion {
    public static let marketing = "1.7.2"
    public static let build = 154

    static let bundleIdentifier = "app.lada.desktop"

    /// The packaged app's Info.plist when Låda runs as its own bundle, otherwise the constants
    /// above (`swift run` has no bundle; tests run inside another app's bundle).
    public static var display: String {
        display(bundle: Bundle.main)
    }

    static func display(bundle: Bundle) -> String {
        guard bundle.bundleIdentifier == bundleIdentifier, let info = bundle.infoDictionary else {
            return "\(marketing) (\(build))"
        }
        let version = info["CFBundleShortVersionString"] as? String ?? marketing
        let buildNumber = info["CFBundleVersion"] as? String ?? "\(build)"
        return "\(version) (\(buildNumber))"
    }
}
