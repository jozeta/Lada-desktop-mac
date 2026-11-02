import SwiftUI
import AppKit

/// The Dockerfile Editor's completion list: a borderless frosted-glass panel under the caret,
/// styled like the rest of Låda. The text view keeps keyboard focus; it forwards ↑/↓, Return/Tab
/// (accept) and Esc (close) while the list is open. Clicking a row accepts it too.
@MainActor
final class CompletionPopupController {
    final class Model: ObservableObject {
        @Published var items: [String] = []
        @Published var selection = 0
    }

    private let model = Model()
    private lazy var panel = FloatingGlassPanel { [unowned self] in
        CompletionListView(model: self.model) { [weak self] index in
            self?.model.selection = index
            self?.acceptSelection()
        }
    }
    private var onPick: ((String) -> Void)?

    static let rowHeight: CGFloat = 28
    static let maxVisibleRows = 8
    static let inset: CGFloat = 6

    var isVisible: Bool { panel.isVisible }
    var selectedItem: String? { model.items.indices.contains(model.selection) ? model.items[model.selection] : nil }

    /// Shows (or updates) the list below `caretRect` (screen coordinates).
    func show(items: [String], caretRect: NSRect, parent: NSWindow, onPick: @escaping (String) -> Void) {
        guard !items.isEmpty else { hide(); return }
        self.onPick = onPick
        if model.items != items {
            model.items = items
            model.selection = 0
        }
        let size = Self.size(for: items)
        panel.show(
            topLeft: NSPoint(x: caretRect.minX - Self.inset - 8, y: caretRect.minY - 4),
            size: size, parent: parent, flipAbove: caretRect.maxY + 4
        )
    }

    func hide() { panel.hide() }

    func moveSelection(by delta: Int) {
        guard !model.items.isEmpty else { return }
        model.selection = (model.selection + delta + model.items.count) % model.items.count
    }

    func acceptSelection() {
        guard let item = selectedItem else { return }
        hide()
        onPick?(item)
    }

    /// Width fits the longest suggestion (within limits); height fits up to 8 rows.
    static func size(for items: [String]) -> NSSize {
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let longest = items.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = min(520, max(260, longest + 130))
        let rows = CGFloat(min(items.count, maxVisibleRows))
        return NSSize(width: width, height: rows * rowHeight + inset * 2)
    }
}

/// What a suggestion is, for the label on the right of each row.
enum CompletionKind: String {
    case instruction = "Instruction", flag = "Flag", variable = "Variable", image = "Image", value = "Value"

    static func of(_ item: String) -> CompletionKind {
        if DockerfileCompletionEngine.instructions.contains(item) || item == "AS" { return .instruction }
        if item.hasPrefix("--") { return .flag }
        if item.hasPrefix("$") { return .variable }
        if item.contains(":") && !item.contains("=") && !item.hasPrefix("[") && !item.contains("/tcp") && !item.contains("/udp") { return .image }
        return .value
    }
}

private struct CompletionListView: View {
    @ObservedObject var model: CompletionPopupController.Model
    let onPick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                        let selected = index == model.selection
                        HStack(spacing: 10) {
                            Text(item)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(NordicTheme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(CompletionKind.of(item).rawValue)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(selected ? NordicTheme.accent() : NordicTheme.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: CompletionPopupController.rowHeight)
                        .background(
                            RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous)
                                .fill(selected ? NordicTheme.accent().opacity(0.20) : .clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onPick(index) }
                        .id(index)
                    }
                }
                .padding(CompletionPopupController.inset)
            }
            .onChange(of: model.selection) { _, new in proxy.scrollTo(new) }
        }
    }
}
