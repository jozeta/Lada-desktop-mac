import SwiftUI
import AppKit

/// The Dockerfile Editor's completion list: a borderless frosted-glass panel under the caret,
/// styled like the rest of Låda. The text view keeps keyboard focus; it forwards ↑/↓, Return/Tab
/// (accept) and Esc (close) while the list is open. Clicking a row accepts it too.
@MainActor
final class CompletionPopupController {
    final class Model: ObservableObject {
        @Published var items: [String] = []
        /// Reference for each item (IntelliSense), shown beside the list for the selected one.
        @Published var docs: [DockerfileDoc?] = []
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
    static let docWidth: CGFloat = 340
    static let docMinHeight: CGFloat = 300
    static let maxVisibleRows = 8
    static let inset: CGFloat = 6

    var isVisible: Bool { panel.isVisible }
    var selectedItem: String? { model.items.indices.contains(model.selection) ? model.items[model.selection] : nil }

    /// Shows (or updates) the list below `caretRect` (screen coordinates).
    func show(items: [String], lineBeforeCursor: String = "", caretRect: NSRect, parent: NSWindow, onPick: @escaping (String) -> Void) {
        guard !items.isEmpty else { hide(); return }
        self.onPick = onPick
        if model.items != items {
            model.items = items
            model.docs = items.map { DockerfileDocs.doc(for: $0, lineBeforeCursor: lineBeforeCursor) }
            model.selection = 0
        }
        var size = Self.size(for: items)
        if model.docs.contains(where: { $0 != nil }) {
            // Room for the reference pane beside the list.
            size.width += Self.docWidth
            size.height = max(size.height, Self.docMinHeight)
        }
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
        HStack(spacing: 0) {
            list
            if model.docs.contains(where: { $0 != nil }) {
                Divider().overlay(NordicTheme.borderSubtle)
                Group {
                    if model.docs.indices.contains(model.selection), let doc = model.docs[model.selection] {
                        DockerfileDocPane(doc: doc)
                    } else {
                        Text("No reference for this suggestion.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(NordicTheme.secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: CompletionPopupController.docWidth)
            }
        }
    }

    private var list: some View {
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


/// The reference pane: what the instruction does, how it works, syntax, parameters (the one
/// being completed highlighted) and an example.
private struct DockerfileDocPane: View {
    let doc: DockerfileDoc

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(doc.instruction)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(NordicTheme.accent())
                    Text("instruction")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                Text(doc.summary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(doc.howItWorks)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                section("Syntax") {
                    ForEach(doc.syntax, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(NordicTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !doc.parameters.isEmpty {
                    section("Parameters") {
                        ForEach(doc.parameters, id: \.name) { param in
                            let on = param.name == doc.highlighted
                            VStack(alignment: .leading, spacing: 2) {
                                Text(param.name)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(on ? NordicTheme.accent() : NordicTheme.primaryText)
                                Text(param.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(NordicTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous)
                                    .fill(on ? NordicTheme.accent().opacity(0.14) : .clear)
                            )
                        }
                    }
                }
                section("Example") {
                    Text(doc.example)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NordicTheme.primaryText)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nordicChip()
                }
            }
            .padding(12)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(NordicTheme.secondaryText)
            content()
        }
    }
}
