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
                ? NSColor(srgbRed: 0.059, green: 0.071, blue: 0.090, alpha: 1.0) // #0F1217 cool slate
                : NSColor(srgbRed: 0.961, green: 0.969, blue: 0.980, alpha: 1.0) // #F5F7FA cool snow
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

    /// The accent colour. Without an argument it is the theme chosen in Settings.
    public static func accent(for choice: AccentThemeChoice? = nil) -> Color {
        let (dark, light) = accentRGB(choice ?? .current)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// (dark mode, light mode) sRGB per theme: lighter in dark mode, deeper in light mode, so
    /// each keeps contrast against its backdrop.
    static func accentRGB(_ choice: AccentThemeChoice) -> ((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat)) {
        switch choice {
        case .nordicFjord:   return ((0.353, 0.576, 0.769), (0.169, 0.357, 0.518))   // #5A93C4 / #2B5B84
        case .arcticTeal:    return ((0.271, 0.604, 0.639), (0.129, 0.420, 0.451))   // #459AA3 / #216B73
        case .slateSteel:    return ((0.490, 0.569, 0.659), (0.255, 0.318, 0.392))
        case .frostCyan:     return ((0.533, 0.753, 0.816), (0.165, 0.447, 0.533))   // #88C0D0 / #2A7288
        case .auroraGreen:   return ((0.639, 0.745, 0.549), (0.271, 0.463, 0.243))   // #A3BE8C / #45763E
        case .auroraViolet:  return ((0.706, 0.557, 0.678), (0.443, 0.302, 0.533))   // #B48EAD / #714D88
        case .lingonberry:   return ((0.851, 0.431, 0.459), (0.659, 0.208, 0.255))   // #D96E75 / #A83541
        case .cloudberry:    return ((0.878, 0.569, 0.361), (0.698, 0.361, 0.118))   // #E0915C / #B25C1E
        case .birchGold:     return ((0.882, 0.737, 0.427), (0.565, 0.427, 0.090))   // #E1BC6D / #906D17
        case .midnightIndigo: return ((0.553, 0.584, 0.890), (0.255, 0.278, 0.612))  // #8D95E3 / #41479C
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

// MARK: - Syntax Colours

/// Code highlighting tuned for contrast on `codeSurface` in each appearance (Nord-inspired), used
/// instead of the bright system colours, which are hard to read on a light editor.
public enum NordicSyntax {
    public struct Palette {
        public let text: NSColor
        public let keyword: NSColor
        public let alias: NSColor
        public let flag: NSColor
        public let string: NSColor
        public let variable: NSColor
        public let comment: NSColor
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    /// Concrete colours for an appearance. Highlighting resolves them from the text view's own
    /// appearance (and re-runs when it changes), so colours never come out in the other mode's
    /// variant.
    public static func palette(for appearance: NSAppearance) -> Palette {
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // Brightened Nord: snow-white text and lifted accents, so code reads crisply on glass.
            return Palette(text: rgb(0xF2, 0xF4, 0xF8), keyword: rgb(0x9C, 0xD6, 0xE8), alias: rgb(0xD3, 0xA8, 0xCB),
                           flag: rgb(0xA6, 0xDB, 0xD5), string: rgb(0xBC, 0xD9, 0x9E), variable: rgb(0xEB, 0xA2, 0x84),
                           comment: rgb(0x9A, 0xA4, 0xB4))
        }
        return Palette(text: rgb(0x0F, 0x14, 0x1A), keyword: rgb(0x1B, 0x4B, 0x76), alias: rgb(0x66, 0x3A, 0x8A),
                       flag: rgb(0x10, 0x5E, 0x66), string: rgb(0x2E, 0x66, 0x33), variable: rgb(0x92, 0x47, 0x10),
                       comment: rgb(0x5B, 0x64, 0x70))
    }
}

// MARK: - Layout & Motion Tokens

public extension NordicTheme {
    /// 4-pt spacing scale. Use these instead of ad-hoc paddings.
    enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    enum Radius {
        /// Buttons, fields, badges, list rows.
        public static let control: CGFloat = 6
        /// Panels and cards.
        public static let card: CGFloat = 10
    }

    /// Short, calm animations. Views that move content check Reduce Motion (`motion(_:)`).
    enum Motion {
        /// Hover, highlight and colour changes.
        public static let quick = Animation.easeOut(duration: 0.14)
        /// Layout and state changes.
        public static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86)
        /// Numbers and charts settling to new values.
        public static let data = Animation.easeInOut(duration: 0.35)
    }
}

// MARK: - Panels

public extension View {
    /// The standard Låda panel: frosted glass with continuous 10 pt corners, a fine light edge and
    /// a soft shadow (solid when Reduce Transparency is on).
    func nordicPanel(padding: CGFloat = NordicTheme.Spacing.l) -> some View {
        self
            .modifier(DensityPadding(base: padding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .nordicSurface()
    }

    /// The panel look (surface, continuous corners, hairline border) without padding or sizing,
    /// for views that lay out their own insets.
    func nordicSurface(cornerRadius: CGFloat = NordicTheme.Radius.card) -> some View {
        modifier(NordicGlassSurface(cornerRadius: cornerRadius))
    }

    /// Small chips and pills inside panels (ports, tags, completions): a light translucent tint
    /// rather than an opaque fill, so they sit on the glass instead of punching holes in it.
    func nordicChip(cornerRadius: CGFloat = NordicTheme.Radius.control) -> some View {
        background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Tables and lists on glass: no opaque system background and no striped filler rows.
    func nordicTransparentTable() -> some View {
        self
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
    }

    /// Page and sheet background: the calm Nordic backdrop the glass panels frost.
    func nordicPageBackground() -> some View {
        background(NordicBackdrop().ignoresSafeArea())
    }

    /// Toolbars and section headers: a thin bar material, so content scrolls under frosted glass.
    func nordicBar() -> some View {
        background(.bar)
    }

    /// Hover feedback for clickable cards: the border picks up the accent and the card lifts a
    /// little. No movement with Reduce Motion.
    func nordicHoverHighlight(accent: Color = NordicTheme.accent()) -> some View {
        modifier(NordicHoverHighlight(accent: accent))
    }

    /// Applies `animation` unless the user has turned on Reduce Motion.
    func nordicMotion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(NordicReducibleAnimation(animation: animation, value: value))
    }

    /// A settings form drawn as a Nordic panel. `.columns` (labels in a leading column) instead of
    /// `.grouped`, whose system-drawn translucent inset box did not match the rest of the app.
    func nordicFormPanel() -> some View {
        self
            .formStyle(.columns)
            .nordicPanel(padding: 16)
    }
}

private struct NordicHoverHighlight: ViewModifier {
    let accent: Color
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: NordicTheme.Radius.card, style: .continuous)
                    .strokeBorder(accent.opacity(hovered ? 0.45 : 0), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovered && !reduceMotion ? 0.08 : 0), radius: 8, y: 3)
            .offset(y: hovered && !reduceMotion ? -1 : 0)
            .onHover { hovered = $0 }
            .animation(NordicTheme.Motion.quick, value: hovered)
    }
}

private struct NordicReducibleAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Shared value formatting.
public enum NordicFormat {
    /// Like `ByteCountFormatter.string(fromByteCount:countStyle:)` but always numeric
    /// ("0 KB", never "Zero KB").
    public static func bytes(fromByteCount count: Int64, countStyle: ByteCountFormatter.CountStyle) -> String {
        let f = ByteCountFormatter()
        f.countStyle = countStyle
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: count)
    }
}

// MARK: - Glass

/// Frosted glass for panels: system material (which turns solid with Reduce Transparency), a fine
/// highlight on the edge and a soft shadow that lifts the panel off the backdrop.
private struct NordicGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Thin material: more of the backdrop shows through, so the frost reads as glass. Reduce
        // Transparency still makes it solid.
        content
            .background(.thinMaterial, in: shape)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.14), Color.white.opacity(0.04)]
                            : [Color.white.opacity(0.85), Color.black.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.07), radius: 10, y: 4)
    }
}

/// A calm, softly tinted backdrop: a fjord-to-sand gradient with two faint glows. Glass panels
/// above it pick up the tint; with Reduce Transparency the panels are solid anyway.
public struct NordicBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            // The desktop and windows behind Låda, blurred (behind-window vibrancy). The tint
            // below is partly transparent so they show through; Reduce Transparency turns this
            // layer solid and the backdrop becomes the plain gradient.
            NordicWindowMaterial()
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.067, green: 0.082, blue: 0.106), Color(red: 0.094, green: 0.106, blue: 0.129)]
                    : [Color(red: 0.918, green: 0.941, blue: 0.961), Color(red: 0.953, green: 0.961, blue: 0.973)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(Self.tintOpacity(dark: dark))
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.58, blue: 0.77).opacity(dark ? 0.30 : 0.26), .clear],
                center: .topLeading, startRadius: 0, endRadius: 700
            )
            RadialGradient(
                colors: [Color(red: 0.53, green: 0.75, blue: 0.82).opacity(dark ? 0.18 : 0.22), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 600
            )
        }
    }
}

extension NordicBackdrop {
    /// How much of the Nordic tint covers the blurred desktop: low enough to see what's behind,
    /// high enough that text on the page keeps its contrast.
    static func tintOpacity(dark: Bool) -> Double { dark ? 0.55 : 0.5 }
}

/// Blurred view of what is behind the window, under the page backdrop.
public struct NordicWindowMaterial: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Behind-window vibrancy (the translucent sidebar of Finder or Mail).
public struct NordicSidebarMaterial: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}



// MARK: - Density

private struct NordicDensityKey: EnvironmentKey {
    static let defaultValue: UIDensityMode = .comfortable
}

public extension EnvironmentValues {
    /// Settings → Appearance → Interface Density, set once at the window root.
    var nordicDensity: UIDensityMode {
        get { self[NordicDensityKey.self] }
        set { self[NordicDensityKey.self] = newValue }
    }
}

public extension UIDensityMode {
    /// Multiplier for panel insets.
    var paddingScale: CGFloat { self == .compact ? 0.65 : 1 }
    var minRowHeight: CGFloat { self == .compact ? 20 : 28 }
    var controlSize: ControlSize { self == .compact ? .small : .regular }
}

/// Panel padding that follows the density setting.
private struct DensityPadding: ViewModifier {
    let base: CGFloat
    @Environment(\.nordicDensity) private var density
    func body(content: Content) -> some View {
        content.padding(base * density.paddingScale)
    }
}

public extension View {
    /// Applies Interface Density to everything below: control size, list row height, and
    /// (through `nordicPanel`) panel insets.
    func nordicDensity(_ density: UIDensityMode) -> some View {
        self
            .environment(\.nordicDensity, density)
            .environment(\.defaultMinListRowHeight, density.minRowHeight)
            .controlSize(density.controlSize)
    }
}
