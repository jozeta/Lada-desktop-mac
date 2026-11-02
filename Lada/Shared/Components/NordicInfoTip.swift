import SwiftUI

/// A small ⓘ that explains a function or setting. Hovering for a moment (or clicking) opens a
/// frosted card with the explanation; moving away closes it. VoiceOver reads the text as a hint.
public struct NordicInfoTip: View {
    let title: String?
    let text: String
    @State private var isHovering = false
    @State private var isShowing = false

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
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    // A short delay so sweeping the pointer across the UI doesn't flash cards.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        if isHovering { isShowing = true }
                    }
                } else {
                    isShowing = false
                }
            }
            .onTapGesture { isShowing.toggle() }
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                NordicInfoCard(title: title, text: text)
            }
            .accessibilityElement()
            .accessibilityLabel(title.map { "About \($0)" } ?? "More information")
            .accessibilityHint(text)
            .accessibilityAddTraits(.isButton)
    }
}

/// The card inside an info popover (the popover itself supplies the frosted material).
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
        .frame(width: 280, alignment: .leading)
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
