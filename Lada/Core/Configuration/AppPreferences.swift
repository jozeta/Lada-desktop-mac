import Foundation
import SwiftUI

public enum AppAppearanceMode: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

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
    case comfortable = "comfortable"
    case compact = "compact"

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
    case nordicFjord = "nordicFjord"
    case arcticTeal = "arcticTeal"
    case slateSteel = "slateSteel"

    public var displayName: String {
        switch self {
        case .nordicFjord: return "Nordic Fjord Blue"
        case .arcticTeal: return "Arctic Teal"
        case .slateSteel: return "Slate Steel"
        }
    }
}

public enum NavigationSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case containers = "Containers"
    case stacks = "Compose Stacks"
    case images = "Images"
    case imageLibrary = "Image Library"
    case dockerfileEditor = "Dockerfile Editor"
    case builds = "Builds"
    case networks = "Networks"
    case volumes = "Volumes"
    case machines = "Machines"
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
