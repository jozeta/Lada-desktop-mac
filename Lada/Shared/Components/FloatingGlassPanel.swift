import SwiftUI
import AppKit

/// A borderless frosted-glass panel that floats above a window (completion lists, search
/// results). It never becomes key, so the text field or editor that opened it keeps the keyboard.
@MainActor
final class FloatingGlassPanel {
    private var panel: NSPanel?
    private let makeContent: () -> AnyView

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self.makeContent = { AnyView(content()) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Places the panel's top-left at `topLeft` (screen coordinates), flipping above `flipAbove`
    /// when it would run off the bottom of the screen.
    func show(topLeft: NSPoint, size: NSSize, parent: NSWindow, flipAbove: CGFloat? = nil) {
        let panel = self.panel ?? makePanel()
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        if let screen = parent.screen?.visibleFrame {
            if origin.y < screen.minY, let flipAbove { origin.y = flipAbove }
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true

        // Real frosted glass: blurs whatever is under the panel.
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = NordicTheme.Radius.card
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let host = NSHostingView(rootView: makeContent())
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        panel.contentView = glass
        self.panel = panel
        return panel
    }
}

/// Remembers the AppKit view behind a SwiftUI view, to position a floating panel under it.
final class ScreenAnchor {
    fileprivate weak var view: NSView?

    /// The view's frame in screen coordinates.
    @MainActor var screenFrame: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    @MainActor var window: NSWindow? { view?.window }
}

struct ScreenAnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}
