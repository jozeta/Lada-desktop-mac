import SwiftUI

/// A row's selection checkbox. Ticking adds the row to the list's selection (like ⌘-click), so
/// several rows can be picked without the keyboard.
struct SelectionCheckbox: View {
    let isOn: Bool
    let title: String
    let toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.small)
            .help(isOn ? "Deselect \(title)" : "Select \(title) (⌘-click or ⇧-click rows to select several)")
            .accessibilityLabel(isOn ? "Deselect \(title)" : "Select \(title)")
    }
}

/// Fixed-size slot for a row action icon, so the same action lines up in every row even when a
/// row has a spinner or no button in that slot. Fill an unused slot with `Color.clear`, not
/// `EmptyView()`: an EmptyView ignores the frame and the slot collapses.
struct ActionSlot<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: 18, height: 18)
    }
}

/// Replaces a list's toolbar while several rows are selected: the count and the bulk actions.
struct BulkSelectionBar<Actions: View>: View {
    let count: Int
    let noun: String
    let onSelectAll: (() -> Void)?
    let onClear: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(NordicTheme.accent())
            Text("\(count) \(count == 1 ? noun : noun + "s") selected")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(NordicTheme.primaryText)
                .fixedSize()
            if let onSelectAll {
                Button("Select All", action: onSelectAll)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .fixedSize()
            }
            Button("Clear", action: onClear)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .fixedSize()
            Spacer(minLength: 8)
            actions()
        }
    }
}

/// The inspector while several rows are selected: what is selected, and the bulk actions.
struct BulkSelectionItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let isActive: Bool
}

struct BulkSelectionPanel<Actions: View>: View {
    let icon: LadaIconKind
    let noun: String
    let items: [BulkSelectionItem]
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        let accent = NordicTheme.accent()
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
            HStack(spacing: NordicTheme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16))
                    LadaIcon(icon, size: 20).foregroundStyle(accent)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(items.count) \(items.count == 1 ? noun : noun + "s") selected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text("Actions apply to every selected \(noun). ⌘-click or ⇧-click rows to change the selection.")
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: NordicTheme.Spacing.s) { actions() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.isActive ? NordicTheme.statusGreen : NordicTheme.secondaryText.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NordicTheme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(NordicTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        if item.id != items.last?.id { Divider().overlay(NordicTheme.borderSubtle) }
                    }
                }
                .nordicSurface()
            }
        }
        .padding(NordicTheme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
