import SwiftUI
import AppKit

/// The toolbar search's results: a frosted panel under the search field listing every matching
/// resource with its type, where it lives and its state. The field keeps the keyboard: ↑/↓ move,
/// Return opens, Esc clears.
@MainActor
final class UniversalSearchPanel: ObservableObject {
    final class Model: ObservableObject {
        @Published var query = ""
        @Published var results: [UniversalSearchResult] = []
        @Published var selection = 0
    }

    let model = Model()
    var onOpen: ((UniversalSearchResult) -> Void)?
    private lazy var panel = FloatingGlassPanel { [unowned self] in
        UniversalSearchResultsView(model: self.model) { [weak self] index in
            self?.model.selection = index
            self?.openSelection()
        }
    }

    static let rowHeight: CGFloat = 46
    static let maxVisibleRows = 8
    static let chromeHeight: CGFloat = 64   // header, footer and insets
    static let width: CGFloat = 540

    var isVisible: Bool { panel.isVisible }

    func update(query: String, inputs: UniversalSearch.Inputs, anchor: ScreenAnchor) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let frame = anchor.screenFrame, let window = anchor.window else { hide(); return }
        let results = UniversalSearch.results(for: trimmed, in: inputs)
        model.query = trimmed
        if model.results != results {
            model.results = results
            model.selection = 0
        }
        let rows = CGFloat(max(1, min(results.count, Self.maxVisibleRows)))
        panel.show(
            topLeft: NSPoint(x: frame.minX, y: frame.minY - 6),
            size: NSSize(width: Self.width, height: rows * Self.rowHeight + Self.chromeHeight),
            parent: window
        )
    }

    func hide() { panel.hide() }

    func moveSelection(by delta: Int) {
        guard !model.results.isEmpty else { return }
        model.selection = (model.selection + delta + model.results.count) % model.results.count
    }

    func openSelection() {
        guard model.results.indices.contains(model.selection) else { return }
        let result = model.results[model.selection]
        hide()
        onOpen?(result)
    }
}

private struct UniversalSearchResultsView: View {
    @ObservedObject var model: UniversalSearchPanel.Model
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.results.isEmpty ? "No matches for “\(model.query)”" : "\(model.results.count) results for “\(model.query)”")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if model.results.isEmpty {
                Text("Search finds containers, stacks, images, machines, volumes, networks, registries, Image Library presets and pages.")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: UniversalSearchPanel.rowHeight)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                row(result, selected: index == model.selection)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onPick(index) }
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .onChange(of: model.selection) { _, new in proxy.scrollTo(new) }
                }
            }

            Divider().overlay(NordicTheme.borderSubtle)
            HStack(spacing: 12) {
                hint("↑↓", "move")
                hint("↩", "open")
                hint("esc", "clear")
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 26)
        }
    }

    private func row(_ result: UniversalSearchResult, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: result.kind))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? NordicTheme.accent() : NordicTheme.secondaryText)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                        .lineLimit(1)
                    Text(result.kind.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .nordicChip(cornerRadius: 4)
                }
                Text(result.location)
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !result.detail.isEmpty {
                Text(result.detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: UniversalSearchPanel.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous)
                .fill(selected ? NordicTheme.accent().opacity(0.18) : .clear)
        )
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .nordicChip(cornerRadius: 3)
            Text(label).font(.system(size: 10.5))
        }
        .foregroundStyle(NordicTheme.secondaryText)
    }

    static func symbol(for kind: UniversalSearchResult.Kind) -> String {
        switch kind {
        case .container: return "shippingbox"
        case .stack: return "square.stack.3d.up"
        case .image: return "square.3.layers.3d"
        case .machine: return "desktopcomputer"
        case .volume: return "externaldrive"
        case .network: return "network"
        case .registry: return "server.rack"
        case .libraryImage: return "books.vertical"
        case .section: return "sidebar.left"
        }
    }
}
