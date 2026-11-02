import SwiftUI

/// Image reference text field with inline autocomplete (local images, then the curated catalog).
///
/// Suggestions appear under the field while it has focus. ↑/↓ move the highlight, Return or Tab
/// accepts it, Esc closes the list. Accepting a repository suggestion that ends in a tag leaves the
/// cursor after it, so typing `:` again switches to tag completion.
public struct ImageReferenceField: View {
    @Binding var text: String
    let placeholder: String
    let localReferences: [String]
    let accent: Color

    @FocusState private var isFocused: Bool
    @State private var highlighted = 0
    @State private var dismissed = false

    public init(text: Binding<String>, placeholder: String, localReferences: [String], accent: Color) {
        self._text = text
        self.placeholder = placeholder
        self.localReferences = localReferences
        self.accent = accent
    }

    private var suggestions: [ImageReferenceSuggester.Suggestion] {
        ImageReferenceSuggester.suggestions(for: text, localReferences: localReferences, catalog: DockerHubService.curatedCatalog, limit: 7)
    }

    private var showsList: Bool { isFocused && !dismissed && !suggestions.isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(NordicTheme.monoFontRegular)
                .focused($isFocused)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.imageReferenceField)
                .onChange(of: text) { _, _ in
                    highlighted = 0
                    dismissed = false
                }
                .onKeyPress(.downArrow) {
                    guard showsList else { return .ignored }
                    highlighted = min(highlighted + 1, suggestions.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard showsList else { return .ignored }
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) { accept(at: highlighted) }
                .onKeyPress(.tab) { accept(at: highlighted) }
                .onKeyPress(.escape) {
                    guard showsList else { return .ignored }
                    dismissed = true
                    return .handled
                }

            if showsList {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            _ = accept(at: index)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: suggestion.source == .local ? "internaldrive" : "square.stack.3d.up")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(index == highlighted ? accent : NordicTheme.secondaryText)
                                    .frame(width: 14)
                                Text(suggestion.reference)
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.primaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(suggestion.source == .local ? "Local" : suggestion.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(index == highlighted ? accent.opacity(0.14) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = index } }
                    }
                }
                .padding(3)
                .background(NordicTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsList)
    }

    private func accept(at index: Int) -> KeyPress.Result {
        guard showsList, suggestions.indices.contains(index) else { return .ignored }
        text = suggestions[index].reference
        dismissed = true
        return .handled
    }
}
