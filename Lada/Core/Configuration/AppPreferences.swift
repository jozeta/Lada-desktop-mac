import Foundation
import SwiftUI

public enum AppAppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum UIDensityMode: String, Codable, CaseIterable, Sendable {
    case comfortable
    case compact

    public var displayName: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }

    public var rowVerticalPadding: CGFloat {
        switch self {
        case .comfortable: return 8
        case .compact: return 4
        }
    }
}

public enum AccentThemeChoice: String, Codable, CaseIterable, Sendable {
    case nordicFjord
    case arcticTeal
    case slateSteel
    case frostCyan
    case auroraGreen
    case auroraViolet
    case lingonberry
    case cloudberry
    case birchGold
    case midnightIndigo

    public var displayName: String {
        switch self {
        case .nordicFjord: return "Nordic Fjord Blue"
        case .arcticTeal: return "Arctic Teal"
        case .slateSteel: return "Slate Steel"
        case .frostCyan: return "Frost Cyan"
        case .auroraGreen: return "Aurora Green"
        case .auroraViolet: return "Aurora Violet"
        case .lingonberry: return "Lingonberry Red"
        case .cloudberry: return "Cloudberry Orange"
        case .birchGold: return "Birch Gold"
        case .midnightIndigo: return "Midnight Indigo"
        }
    }

    /// One distinct word for the swatch label.
    public var shortName: String {
        switch self {
        case .nordicFjord: return "Fjord"
        case .arcticTeal: return "Teal"
        case .slateSteel: return "Slate"
        case .frostCyan: return "Frost"
        case .auroraGreen: return "Green"
        case .auroraViolet: return "Violet"
        case .lingonberry: return "Lingonberry"
        case .cloudberry: return "Cloudberry"
        case .birchGold: return "Birch"
        case .midnightIndigo: return "Indigo"
        }
    }

    /// The choice saved in Settings (read directly, so any view can use it).
    public static var current: AccentThemeChoice {
        UserDefaults.standard.string(forKey: "lada.accentThemeChoice").flatMap(AccentThemeChoice.init(rawValue:)) ?? .nordicFjord
    }
}

public enum NavigationSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case containers = "Containers"
    case stacks = "Compose Stacks"
    case images = "Images"
    case imageLibrary = "Image Library"
    case dockerfileEditor = "Dockerfile Editor"
    case networks = "Networks"
    case volumes = "Volumes"
    case machines = "Machines"
    case nodeGraph = "Node Graph"
    case registries = "Registries"
    case activity = "Activity"
    case settings = "Settings"

    public var id: String { rawValue }
}

@MainActor
public final class AppPreferences: ObservableObject {
    @AppStorage("lada.hasCompletedFirstLaunchSetup") public var hasCompletedFirstLaunchSetup: Bool = false
    @AppStorage("lada.defaultLandingSection") public var defaultLandingSectionRaw: String = NavigationSection.overview.rawValue
    @AppStorage("lada.appearanceMode") public var appearanceModeRaw: String = AppAppearanceMode.system.rawValue
    @AppStorage("lada.uiDensityMode") public var uiDensityModeRaw: String = UIDensityMode.comfortable.rawValue
    @AppStorage("lada.accentThemeChoice") public var accentThemeChoiceRaw: String = AccentThemeChoice.nordicFjord.rawValue
    @AppStorage("lada.confirmDestructiveActions") public var confirmDestructiveActions: Bool = true
    @AppStorage("lada.confirmStopContainer") public var confirmStopContainer: Bool = false
    @AppStorage("lada.autoRefreshIntervalSeconds") public var autoRefreshIntervalSeconds: Int = 10
    @AppStorage("lada.customCLIExecutablePath") public var customCLIExecutablePath: String = ""
    @AppStorage("lada.defaultContainerCPUs") public var defaultContainerCPUs: Int = 4
    @AppStorage("lada.defaultContainerMemoryMB") public var defaultContainerMemoryMB: Int = 1024
    @AppStorage("lada.defaultBuildCPUs") public var defaultBuildCPUs: Int = 2
    @AppStorage("lada.defaultBuildMemoryMB") public var defaultBuildMemoryMB: Int = 2048
    @AppStorage("lada.notifyBuildCompletion") public var notifyBuildCompletion: Bool = true
    @AppStorage("lada.notifyContainerFailures") public var notifyContainerFailures: Bool = true
    @AppStorage("lada.notifyRuntimeFailures") public var notifyRuntimeFailures: Bool = true
    @AppStorage("lada.enableExperimentalPathMasking") public var enableExperimentalPathMasking: Bool = false
    @AppStorage("lada.enableDeveloperLogging") public var enableDeveloperLogging: Bool = false
    @AppStorage("lada.useSimulationWhenCLIMissing") public var useSimulationWhenCLIMissing: Bool = false

    public init() {}

    public var appearanceMode: AppAppearanceMode {
        get { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    public var uiDensityMode: UIDensityMode {
        get { UIDensityMode(rawValue: uiDensityModeRaw) ?? .comfortable }
        set { uiDensityModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    public var accentThemeChoice: AccentThemeChoice {
        get { AccentThemeChoice(rawValue: accentThemeChoiceRaw) ?? .nordicFjord }
        set { accentThemeChoiceRaw = newValue.rawValue; objectWillChange.send() }
    }

    public var defaultLandingSection: NavigationSection {
        get { NavigationSection(rawValue: defaultLandingSectionRaw) ?? .overview }
        set { defaultLandingSectionRaw = newValue.rawValue; objectWillChange.send() }
    }

    public var ladaDataDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath)
        return appSupport.appendingPathComponent("com.lada.desktop", isDirectory: true)
    }
}
