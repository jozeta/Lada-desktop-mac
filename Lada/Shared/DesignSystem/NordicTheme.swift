import SwiftUI
import AppKit

public enum NordicTheme {
    // MARK: - Adaptive Surface Colors

    public static var windowBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.078, green: 0.086, blue: 0.098, alpha: 1.0) // #141619
                : NSColor(srgbRed: 0.969, green: 0.965, blue: 0.953, alpha: 1.0) // #F7F6F3
        })
    }

    public static var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.106, green: 0.118, blue: 0.137, alpha: 1.0) // #1B1E23
                : NSColor(srgbRed: 0.937, green: 0.925, blue: 0.902, alpha: 1.0) // #EFECE6
        })
    }

    public static var contentSurface: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.118, green: 0.129, blue: 0.153, alpha: 1.0) // #1E2127
                : NSColor(srgbRed: 0.988, green: 0.984, blue: 0.976, alpha: 1.0) // #FCFBF9
        })
    }

    public static var surfaceBackground: Color { contentSurface }

    public static var elevatedSurface: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.145, green: 0.161, blue: 0.188, alpha: 1.0) // #252930
                : NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1.0) // #FFFFFF
        })
    }

    public static var codeSurface: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.063, green: 0.071, blue: 0.082, alpha: 1.0) // #101215
                : NSColor(srgbRed: 0.945, green: 0.941, blue: 0.929, alpha: 1.0) // #F1F0ED
        })
    }

    // MARK: - Text & Borders

    public static var primaryText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.925, green: 0.933, blue: 0.937, alpha: 1.0) // #ECEEEF
                : NSColor(srgbRed: 0.102, green: 0.114, blue: 0.129, alpha: 1.0) // #1A1D21
        })
    }

    public static var secondaryText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.557, green: 0.588, blue: 0.635, alpha: 1.0) // #8E96A2
                : NSColor(srgbRed: 0.361, green: 0.392, blue: 0.431, alpha: 1.0) // #5C646E
        })
    }

    public static var borderSubtle: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.173, green: 0.192, blue: 0.227, alpha: 1.0) // #2C313A
                : NSColor(srgbRed: 0.875, green: 0.867, blue: 0.843, alpha: 1.0) // #DFDDD7
        })
    }

    // MARK: - Accent & Operational Semantic Colors

    public static func accent(for choice: AccentThemeChoice = .nordicFjord) -> Color {
        switch choice {
        case .nordicFjord:
            return Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.353, green: 0.576, blue: 0.769, alpha: 1.0) // #5A93C4
                    : NSColor(srgbRed: 0.169, green: 0.357, blue: 0.518, alpha: 1.0) // #2B5B84
            })
        case .arcticTeal:
            return Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.271, green: 0.604, blue: 0.639, alpha: 1.0) // #459AA3
                    : NSColor(srgbRed: 0.129, green: 0.420, blue: 0.451, alpha: 1.0) // #216B73
            })
        case .slateSteel:
            return Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.490, green: 0.569, blue: 0.659, alpha: 1.0)
                    : NSColor(srgbRed: 0.255, green: 0.318, blue: 0.392, alpha: 1.0)
            })
        }
    }

    public static var statusGreen: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.278, green: 0.710, blue: 0.467, alpha: 1.0) // #47B577
                : NSColor(srgbRed: 0.173, green: 0.549, blue: 0.345, alpha: 1.0) // #2C8C58
        })
    }

    public static var statusAmber: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.878, green: 0.608, blue: 0.239, alpha: 1.0) // #E09B3D
                : NSColor(srgbRed: 0.722, green: 0.455, blue: 0.102, alpha: 1.0) // #B8741A
        })
    }

    public static var statusRed: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.878, green: 0.353, blue: 0.353, alpha: 1.0) // #E05A5A
                : NSColor(srgbRed: 0.722, green: 0.231, blue: 0.231, alpha: 1.0) // #B83B3B
        })
    }

    // MARK: - Typography

    public static let monoFontSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    public static let monoFontRegular = Font.system(size: 12, weight: .regular, design: .monospaced)
    public static let monoFontMedium = Font.system(size: 12, weight: .medium, design: .monospaced)
    public static let sectionHeaderFont = Font.system(size: 11, weight: .semibold, design: .default)
    public static let titleFont = Font.system(size: 18, weight: .semibold, design: .default)
    public static let subtitleFont = Font.system(size: 13, weight: .medium, design: .default)
}
