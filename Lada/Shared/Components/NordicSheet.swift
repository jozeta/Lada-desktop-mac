import SwiftUI
import AppKit

/// The shared layout of Låda's "create" sheets (network, volume, machine): an icon header, a
/// scrolling form of labelled fields, and a footer that says in plain words what still blocks
/// creating (the primary button stays disabled until it's resolved).
struct NordicSheet<Content: View>: View {
    let icon: LadaIconKind
    let title: String
    let subtitle: String
    let primaryTitle: String
    /// What blocks the primary action, or nil when it's ready.
    let problem: String?
    let width: CGFloat
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder let content: () -> Content

    init(icon: LadaIconKind, title: String, subtitle: String, primaryTitle: String, problem: String?,
         width: CGFloat = 580, onCancel: @escaping () -> Void, onPrimary: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.problem = problem
        self.width = width
        self.onCancel = onCancel
        self.onPrimary = onPrimary
        self.content = content
    }

    var body: some View {
        let accent = NordicTheme.accent()
        VStack(spacing: 0) {
            HStack(spacing: NordicTheme.Spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16))
                    LadaIcon(icon, size: 20).foregroundStyle(accent)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(NordicTheme.Spacing.l)
            Divider().overlay(NordicTheme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
                    content()
                }
                .padding(NordicTheme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(NordicTheme.borderSubtle)
            HStack(spacing: NordicTheme.Spacing.s) {
                if let problem {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(NordicTheme.statusAmber)
                    Text(problem)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NordicTheme.statusAmber)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding(NordicTheme.Spacing.l)
            .nordicBar()
        }
        .frame(width: width)
        .frame(minHeight: 420, idealHeight: 620, maxHeight: 760)
        .nordicPageBackground()
    }
}

/// One labelled field: title (with an optional ⓘ), the control, and a hint below.
struct NordicFormField<Content: View>: View {
    let title: String
    var hint: String? = nil
    var info: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                if let info { NordicInfoTip(info, title: title) }
            }
            content()
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A group of fields on a glass panel.
struct NordicFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
            Text(title.uppercased())
                .font(NordicTheme.sectionHeaderFont)
                .tracking(0.6)
                .foregroundStyle(NordicTheme.secondaryText)
            VStack(alignment: .leading, spacing: NordicTheme.Spacing.l) {
                content()
            }
            .padding(NordicTheme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nordicSurface()
        }
    }
}

/// The exact command a sheet will run, selectable, with a copy button. Secrets are redacted.
struct NordicCommandPreview: View {
    let arguments: [String]

    var body: some View {
        let command = SecretRedactor.formatCommandPreview(executable: "container", arguments: arguments)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("COMMAND")
                    .font(NordicTheme.sectionHeaderFont)
                    .tracking(0.6)
                    .foregroundStyle(NordicTheme.secondaryText)
                NordicInfoTip("Låda runs exactly this with Apple's `container` CLI, without a shell.", title: "Command")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Copy the command")
            }
            Text(command)
                .font(NordicTheme.monoFontSmall)
                .foregroundStyle(NordicTheme.primaryText)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nordicChip()
        }
    }
}

/// A row of selectable chips (presets such as sizes or subnets).
struct NordicChoiceChips: View {
    let options: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selected
                Button { onSelect(option) } label: {
                    Text(option)
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? NordicTheme.accent() : NordicTheme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: NordicTheme.Radius.control, style: .continuous)
                                .fill(isOn ? NordicTheme.accent().opacity(0.16) : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
