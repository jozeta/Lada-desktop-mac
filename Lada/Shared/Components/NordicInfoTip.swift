import SwiftUI

/// A small ⓘ that explains a function or setting. Hovering for a moment (or clicking) opens a
/// frosted card with the explanation; moving away closes it. VoiceOver reads the text as a hint.
public struct NordicInfoTip: View {
    let title: String?
    let text: String
    @State private var isHovering = false
    @State private var anchor = ScreenAnchor()

    public init(_ text: String, title: String? = nil) {
        self.text = text
        self.title = title
    }

    public var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isHovering ? NordicTheme.accent() : NordicTheme.secondaryText)
            .padding(2)
            .contentShape(Rectangle())
            .background(ScreenAnchorReader(anchor: anchor))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    // A short delay so sweeping the pointer across the UI doesn't flash cards.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        if isHovering { InfoTipPresenter.shared.show(title: title, text: text, below: anchor) }
                    }
                } else {
                    InfoTipPresenter.shared.hide(for: anchor)
                }
            }
            .onTapGesture { InfoTipPresenter.shared.toggle(title: title, text: text, below: anchor) }
            .onDisappear { InfoTipPresenter.shared.hide(for: anchor) }
            .accessibilityElement()
            .accessibilityLabel(title.map { "About \($0)" } ?? "More information")
            .accessibilityHint(text)
            .accessibilityAddTraits(.isButton)
    }
}

/// Shows the one info card that can be open at a time: a light frosted panel that appears at
/// once under the ⓘ (no popover animation) and never takes keyboard focus.
@MainActor
final class InfoTipPresenter {
    static let shared = InfoTipPresenter()

    final class Model: ObservableObject {
        @Published var title: String?
        @Published var text = ""
    }

    private let model = Model()
    private weak var owner: ScreenAnchor?
    private lazy var panel = FloatingGlassPanel(material: .fullScreenUI) { [unowned self] in
        InfoTipCardHost(model: self.model)
    }

    static let width: CGFloat = 300

    func show(title: String?, text: String, below anchor: ScreenAnchor) {
        guard let frame = anchor.screenFrame, let window = anchor.window else { return }
        model.title = title
        model.text = text
        owner = anchor
        let size = NSSize(width: Self.width, height: Self.height(title: title, text: text))
        panel.show(topLeft: NSPoint(x: frame.midX - 24, y: frame.minY - 4), size: size, parent: window, flipAbove: frame.maxY + 4)
    }

    func toggle(title: String?, text: String, below anchor: ScreenAnchor) {
        if panel.isVisible && owner === anchor { hide(for: anchor) } else { show(title: title, text: text, below: anchor) }
    }

    /// Hides the card if `anchor` opened it (another tip may already show its own).
    func hide(for anchor: ScreenAnchor) {
        guard owner === anchor else { return }
        panel.hide()
        owner = nil
    }

    /// Height that fits the text at the card's width.
    static func height(title: String?, text: String) -> CGFloat {
        let inner = width - 28
        let body = (text as NSString).boundingRect(
            with: NSSize(width: inner, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        ).height
        let heading: CGFloat = title == nil ? 0 : 22
        return ceil(body + heading + 28)
    }
}

private struct InfoTipCardHost: View {
    @ObservedObject var model: InfoTipPresenter.Model
    var body: some View {
        NordicInfoCard(title: model.title, text: model.text)
    }
}

/// The card's content (the floating panel supplies the frosted glass).
struct NordicInfoCard: View {
    let title: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(NordicTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: InfoTipPresenter.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

public extension View {
    /// Puts an ⓘ with a hover card after this view (labels, toggles, pickers).
    func nordicInfo(_ text: String, title: String? = nil) -> some View {
        HStack(spacing: 5) {
            self
            NordicInfoTip(text, title: title)
        }
    }
}
