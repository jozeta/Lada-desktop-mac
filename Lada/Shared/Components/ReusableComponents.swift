import SwiftUI
import AppKit

// MARK: - Operational Status Badge

public enum OperationalBadgeTone: Sendable {
    case positive
    case warning
    case critical
    case neutral
    case accent

    public var color: Color {
        switch self {
        case .positive: return NordicTheme.statusGreen
        case .warning: return NordicTheme.statusAmber
        case .critical: return NordicTheme.statusRed
        case .neutral: return NordicTheme.secondaryText
        case .accent: return NordicTheme.accent()
        }
    }
}

public struct NordicStatusBadge: View {
    public let label: String
    public let tone: OperationalBadgeTone
    public var showDot: Bool = true

    public init(label: String, tone: OperationalBadgeTone, showDot: Bool = true) {
        self.label = label
        self.tone = tone
        self.showDot = showDot
    }

    public init(containerState: ContainerState) {
        self.label = containerState.displayTitle
        switch containerState {
        case .running: self.tone = .positive
        case .stopping, .created: self.tone = .warning
        case .stopped, .exited: self.tone = .neutral
        case .unknown: self.tone = .critical
        }
    }

    public init(prerequisiteStatus: PrerequisiteStatus) {
        self.label = prerequisiteStatus.displayLabel
        switch prerequisiteStatus {
        case .ready: self.tone = .positive
        case .checking: self.tone = .accent
        case .needsAttention, .missing: self.tone = .warning
        case .incompatible, .failed: self.tone = .critical
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle()
                    .fill(tone.color)
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tone.color)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(tone.color.opacity(0.12)))
        .animation(NordicTheme.Motion.quick, value: label)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(label)")
    }
}

// MARK: - Section & Detail Headers

public struct NordicSectionHeader: View {
    public let title: String
    public var subtitle: String?
    public var trailingText: String?

    public init(_ title: String, subtitle: String? = nil, trailingText: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(NordicTheme.sectionHeaderFont)
                    .tracking(0.6)
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
        }
    }
}

public struct NordicDetailHeader<Actions: View>: View {
    public let title: String
    public let subtitle: String?
    public let badge: NordicStatusBadge?
    @ViewBuilder public let actions: () -> Actions

    public init(
        title: String,
        subtitle: String? = nil,
        badge: NordicStatusBadge? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.actions = actions
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(NordicTheme.titleFont)
                        .foregroundStyle(NordicTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let badge {
                        badge
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(NordicTheme.monoFontSmall)
                        .foregroundStyle(NordicTheme.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .frame(minWidth: 180, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            // Full labels when there is room, icon-only buttons (titles stay as tooltips and
            // accessibility labels) when the inspector is narrow, so the title is never squeezed.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { actions() }
                    .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 6) { actions() }
                    .labelStyle(.iconOnly)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .nordicBar()
        .overlay(alignment: .bottom) {
            Divider().overlay(NordicTheme.borderSubtle)
        }
    }
}

// MARK: - Expandable Error Banner

public struct NordicErrorBanner: View {
    public let error: LadaError
    public var onRetry: (() -> Void)?
    public var onDismiss: (() -> Void)?
    @State private var showTechnicalDetails = true

    public init(error: LadaError, onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NordicTheme.statusRed)
                    .font(.system(size: 14))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(error.category.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NordicTheme.primaryText)
                        if let code = error.exitStatus {
                            Text(verbatim: "Exit \(code)")
                                .font(NordicTheme.monoFontSmall)
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                    }
                    Text(error.explanation)
                        .font(.system(size: 12))
                        .foregroundStyle(NordicTheme.primaryText)
                    Text(error.suggestedRemediation)
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)

                    if let diag = error.diagnosticOutput, !diag.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTechnicalDetails.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showTechnicalDetails ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text(showTechnicalDetails ? "Hide Technical Details" : "Show Technical Details")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NordicTheme.accent())
                        .padding(.top, 2)

                        if showTechnicalDetails {
                            ScrollView {
                                Text(diag)
                                    .font(NordicTheme.monoFontSmall)
                                    .foregroundStyle(NordicTheme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(8)
                            }
                            .frame(maxHeight: 110)
                            .background(NordicTheme.codeSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(NordicTheme.borderSubtle, lineWidth: 1)
                            )
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if let docURL = error.documentationURL {
                        Link("Docs", destination: docURL)
                            .font(.system(size: 11, weight: .medium))
                    }
                    if error.isRetryable, let onRetry {
                        Button("Retry", action: onRetry)
                            .controlSize(.small)
                    }
                    if let onDismiss {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NordicTheme.secondaryText)
                        .accessibilityLabel("Dismiss Error")
                    }
                }
            }
        }
        .padding(12)
        .background(NordicTheme.statusRed.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NordicTheme.statusRed.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Empty State View

public struct NordicEmptyState: View {
    public let icon: LadaIconKind
    public let title: String
    public let description: String
    public var primaryActionTitle: String?
    public var onPrimaryAction: (() -> Void)?
    public var secondaryActionTitle: String?
    public var onSecondaryAction: (() -> Void)?

    public init(
        icon: LadaIconKind,
        title: String,
        description: String,
        primaryActionTitle: String? = nil,
        onPrimaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        onSecondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.primaryActionTitle = primaryActionTitle
        self.onPrimaryAction = onPrimaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.onSecondaryAction = onSecondaryAction
    }

    public var body: some View {
        VStack(spacing: 12) {
            LadaIcon(icon, size: 34, strokeWidth: 1.5)
                .foregroundStyle(NordicTheme.secondaryText)
                .padding(.bottom, 4)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NordicTheme.primaryText)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(NordicTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if primaryActionTitle != nil || secondaryActionTitle != nil {
                HStack(spacing: 10) {
                    if let primaryActionTitle, let onPrimaryAction {
                        Button(primaryActionTitle, action: onPrimaryAction)
                            .buttonStyle(.borderedProminent)
                            .tint(NordicTheme.accent())
                    }
                    if let secondaryActionTitle, let onSecondaryAction {
                        Button(secondaryActionTitle, action: onSecondaryAction)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Key-Value Editor Component

public struct NordicKeyValueEditor: View {
    public let title: String
    public let keyPlaceholder: String
    public let valuePlaceholder: String
    public var allowSecretMasking: Bool
    @Binding public var entries: [KeyValueEntry]
    @State private var revealedIDs: Set<UUID> = []

    public init(
        title: String,
        keyPlaceholder: String = "KEY",
        valuePlaceholder: String = "Value",
        allowSecretMasking: Bool = false,
        entries: Binding<[KeyValueEntry]>
    ) {
        self.title = title
        self.keyPlaceholder = keyPlaceholder
        self.valuePlaceholder = valuePlaceholder
        self.allowSecretMasking = allowSecretMasking
        self._entries = entries
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NordicTheme.primaryText)
                Spacer()
                Button {
                    entries.append(KeyValueEntry())
                } label: {
                    Label("Add Entry", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            }

            if entries.isEmpty {
                Text("No entries configured.")
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .padding(.vertical, 4)
            } else {
                ForEach($entries) { $entry in
                    HStack(spacing: 6) {
                        TextField(keyPlaceholder, text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .font(NordicTheme.monoFontSmall)
                            .frame(maxWidth: 190)
                            .onChange(of: entry.key) { _, newKey in
                                if allowSecretMasking && SecretRedactor.isSensitiveKey(newKey) {
                                    entry.isSecret = true
                                }
                            }

                        Text("=")
                            .font(NordicTheme.monoFontSmall)
                            .foregroundStyle(NordicTheme.secondaryText)

                        if allowSecretMasking && entry.isSecret && !revealedIDs.contains(entry.id) {
                            SecureField(valuePlaceholder, text: $entry.value)
                                .textFieldStyle(.roundedBorder)
                                .font(NordicTheme.monoFontSmall)
                        } else {
                            TextField(valuePlaceholder, text: $entry.value)
                                .textFieldStyle(.roundedBorder)
                                .font(NordicTheme.monoFontSmall)
                        }

                        if allowSecretMasking {
                            Button {
                                if entry.isSecret {
                                    if revealedIDs.contains(entry.id) {
                                        revealedIDs.remove(entry.id)
                                    } else {
                                        revealedIDs.insert(entry.id)
                                    }
                                } else {
                                    entry.isSecret = true
                                }
                            } label: {
                                Image(systemName: (entry.isSecret && !revealedIDs.contains(entry.id)) ? "eye.slash" : "eye")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help(entry.isSecret ? "Toggle secret visibility" : "Mask as secret")

                            if entry.isSecret {
                                Button {
                                    entry.value = SecretGenerator.password()
                                } label: {
                                    Image(systemName: "key")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .help("Generate a random 24-character value")
                            }
                        }

                        Button {
                            entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(NordicTheme.statusRed)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove Entry")
                    }
                }
            }
        }
    }
}

// MARK: - Safe Plain-Text Log Viewer

public struct NordicLogViewer: View {
    public let rawLogText: String
    @Binding public var searchText: String
    @Binding public var isPaused: Bool
    @Binding public var autoScroll: Bool
    public var onRefresh: (() -> Void)?
    @State private var wrapLines: Bool = true

    public init(
        rawLogText: String,
        searchText: Binding<String>,
        isPaused: Binding<Bool>,
        autoScroll: Binding<Bool>,
        onRefresh: (() -> Void)? = nil
    ) {
        self.rawLogText = rawLogText
        self._searchText = searchText
        self._isPaused = isPaused
        self._autoScroll = autoScroll
        self.onRefresh = onRefresh
    }

    private static func sanitizeLogText(_ raw: String) -> String {
        // 1. Normalize CRLF (\r\n) and standalone CR (\r) to LF (\n) so .components doesn't create empty lines between every CRLF pair
        var cleaned = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
        // 2. Strip ANSI CSI escape codes (e.g. \u{001B}[32m)
        if cleaned.contains("\u{001B}") {
            cleaned = cleaned.replacingOccurrences(
                of: "\\u{001B}\\[[0-9;?]*[A-Za-z]",
                with: "",
                options: .regularExpression
            )
        }
        return cleaned
    }

    private var filteredLines: [(index: Int, line: String, isErrorLine: Bool, isWarningLine: Bool)] {
        let normalized = Self.sanitizeLogText(rawLogText)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lines.enumerated().compactMap { idx, line in
            if !query.isEmpty && !line.lowercased().contains(query) {
                return nil
            }
            let lower = line.lowercased()
            let isErr = lower.contains("error") || lower.contains("stderr") || lower.contains("fatal") || lower.contains("panic") || lower.contains("emerg")
            let isWarn = !isErr && (lower.contains("warn") || lower.contains("notice"))
            return (idx + 1, line, isErr, isWarn)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(NordicTheme.secondaryText)
                        .font(.system(size: 11))
                    TextField("Search log output…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: 110, maxWidth: 190)
                .nordicPageBackground()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))

                Toggle("Wrap", isOn: $wrapLines)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: true, vertical: false)

                Toggle("Follow", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Auto-scroll to newest log lines")

                Button {
                    isPaused.toggle()
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)

                if let onRefresh {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                    .help("Refresh log output")
                }

                Spacer(minLength: 4)

                Text(verbatim: "\(filteredLines.count) lines")
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.sanitizeLogText(rawLogText), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    exportLogFile()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .nordicBar()
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            // Safe plain-text log canvas
            if filteredLines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundStyle(NordicTheme.secondaryText.opacity(0.6))
                    Text(searchText.isEmpty ? "No log output emitted yet." : "No log lines match '\(searchText)'.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NordicTheme.codeSurface)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(wrapLines ? [.vertical] : [.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredLines, id: \.index) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(verbatim: "\(item.index)")
                                        .font(NordicTheme.monoFontSmall)
                                        .foregroundStyle(NordicTheme.secondaryText.opacity(0.6))
                                        .frame(width: 42, alignment: .trailing)
                                        .padding(.vertical, 3)

                                    Divider()
                                        .overlay(NordicTheme.borderSubtle.opacity(0.5))

                                    Text(verbatim: item.line.isEmpty ? " " : item.line)
                                        .font(NordicTheme.monoFontRegular)
                                        .foregroundStyle(
                                            item.isErrorLine
                                                ? NordicTheme.statusRed
                                                : (item.isWarningLine ? NordicTheme.statusAmber : NordicTheme.primaryText)
                                        )
                                        .lineLimit(wrapLines ? nil : 1)
                                        .fixedSize(horizontal: !wrapLines, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 3)
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 10)
                                .background(
                                    item.isErrorLine
                                        ? NordicTheme.statusRed.opacity(0.08)
                                        : (item.index.isMultiple(of: 2) ? Color.primary.opacity(0.02) : Color.clear)
                                )
                                .id(item.index)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(NordicTheme.codeSurface)
                    .onChange(of: rawLogText) { _, _ in
                        if autoScroll && !isPaused, let last = filteredLines.last {
                            proxy.scrollTo(last.index, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func exportLogFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "container-logs-\(Int(Date().timeIntervalSince1970)).log"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? Self.sanitizeLogText(rawLogText).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Surface Card Container

public struct NordicCard<Content: View>: View {
    @ViewBuilder public let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .nordicPanel()
    }
}

// MARK: - Plain Port & Integer TextFields (No Thousand Separator, Stable Focus)

public struct NordicPortTextField: View {
    public let placeholder: String
    @Binding public var port: UInt16
    @State private var text: String
    @FocusState private var isFocused: Bool

    public init(_ placeholder: String, port: Binding<UInt16>) {
        self.placeholder = placeholder
        self._port = port
        self._text = State(initialValue: port.wrappedValue == 0 ? "" : String(port.wrappedValue))
    }

    public var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(NordicTheme.monoFontSmall)
            .focused($isFocused)
            .onChange(of: text) { _, newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                if digitsOnly != newValue {
                    text = digitsOnly
                }
                if let parsed = UInt16(digitsOnly), parsed > 0 {
                    if port != parsed {
                        port = parsed
                    }
                }
            }
            .onChange(of: port) { _, newPort in
                if !isFocused {
                    let formatted = newPort == 0 ? "" : String(newPort)
                    if text != formatted {
                        text = formatted
                    }
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    if let parsed = UInt16(text.filter(\.isNumber)), parsed > 0 {
                        port = parsed
                        text = String(parsed)
                    } else {
                        text = String(port)
                    }
                }
            }
    }
}

public struct NordicIntegerTextField: View {
    public let placeholder: String
    @Binding public var value: Int
    public let range: ClosedRange<Int>
    @State private var text: String
    @FocusState private var isFocused: Bool

    public init(_ placeholder: String, value: Binding<Int>, range: ClosedRange<Int> = 1...65536) {
        self.placeholder = placeholder
        self._value = value
        self.range = range
        self._text = State(initialValue: String(value.wrappedValue))
    }

    public var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(NordicTheme.monoFontRegular)
            .focused($isFocused)
            .onChange(of: text) { _, newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                if digitsOnly != newValue {
                    text = digitsOnly
                }
                if let parsed = Int(digitsOnly), range.contains(parsed) {
                    if value != parsed {
                        value = parsed
                    }
                }
            }
            .onChange(of: value) { _, newInt in
                if !isFocused {
                    let formatted = String(newInt)
                    if text != formatted {
                        text = formatted
                    }
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    if let parsed = Int(text.filter(\.isNumber)) {
                        let clamped = min(range.upperBound, max(range.lowerBound, parsed))
                        value = clamped
                        text = String(clamped)
                    } else {
                        text = String(value)
                    }
                }
            }
    }
}

// MARK: - Live Performance Telemetry Chart Card

public struct NordicPerformanceChartCard: View {
    public let title: String
    public let iconName: String
    public let primaryMetricText: String
    public let secondaryMetricText: String
    public let primarySeries: [Double]
    public let secondarySeries: [Double]?
    public let primaryLegend: String?
    public let secondaryLegend: String?
    public let fixedMaxY: Double?
    /// Shown instead of the chart while there are fewer than two points.
    public let placeholder: String
    public let primaryColor: Color
    public let secondaryColor: Color
    /// When each point was measured (same count as the series); drives the time axis and hover.
    public let timestamps: [Date]
    /// Formats axis labels, the hover readout and peak/average (e.g. "45%", "1.2 MB/s").
    public let valueFormatter: (Double) -> String
    @State private var hoverIndex: Int?

    public init(
        title: String,
        iconName: String,
        primaryMetricText: String,
        secondaryMetricText: String,
        primarySeries: [Double],
        secondarySeries: [Double]? = nil,
        primaryLegend: String? = nil,
        secondaryLegend: String? = nil,
        fixedMaxY: Double? = nil,
        placeholder: String = "Collecting…",
        primaryColor: Color = NordicTheme.accent(),
        secondaryColor: Color = NordicTheme.statusGreen,
        timestamps: [Date] = [],
        valueFormatter: @escaping (Double) -> String = NordicPerformanceChartCard.formatPlain
    ) {
        self.title = title
        self.iconName = iconName
        self.primaryMetricText = primaryMetricText
        self.secondaryMetricText = secondaryMetricText
        self.primarySeries = primarySeries
        self.secondarySeries = secondarySeries
        self.primaryLegend = primaryLegend
        self.secondaryLegend = secondaryLegend
        self.fixedMaxY = fixedMaxY
        self.placeholder = placeholder
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.timestamps = timestamps
        self.valueFormatter = valueFormatter
    }

    // MARK: Formatters

    public nonisolated static func formatPlain(_ v: Double) -> String { String(format: v < 10 ? "%.1f" : "%.0f", v) }

    public nonisolated static func formatPercent(_ v: Double) -> String { String(format: v < 10 ? "%.1f%%" : "%.0f%%", v) }

    /// Bytes per second with binary units.
    public nonisolated static func formatRate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1024 { return String(format: "%.0f B/s", v) }
        if v < 1024 * 1024 { return String(format: v < 10 * 1024 ? "%.1f KB/s" : "%.0f KB/s", v / 1024) }
        if v < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", v / (1024 * 1024)) }
        return String(format: "%.2f GB/s", v / (1024 * 1024 * 1024))
    }

    /// "now", "45s", "4m 58s" for the time axis and hover readout.
    public nonisolated static func formatAgo(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 2 { return "now" }
        if s < 60 { return "\(s)s ago" }
        return s % 60 == 0 ? "\(s / 60)m ago" : "\(s / 60)m \(s % 60)s ago"
    }

    private var summaryText: String? {
        guard primarySeries.count >= 2 else { return nil }
        let peak = primarySeries.max() ?? 0
        let avg = primarySeries.reduce(0, +) / Double(primarySeries.count)
        return "peak \(valueFormatter(peak)) · avg \(valueFormatter(avg))"
    }

    private var spanText: String? {
        guard let first = timestamps.first, let last = timestamps.last, timestamps.count >= 2 else { return nil }
        return "−" + Self.formatAgo(last.timeIntervalSince(first)).replacingOccurrences(of: " ago", with: "")
    }

    private var computedMaxY: Double {
        if let fixedMaxY, fixedMaxY > 0 {
            return fixedMaxY
        }
        let maxPrimary = primarySeries.max() ?? 0
        let maxSecondary = secondarySeries?.max() ?? 0
        let peak = max(maxPrimary, maxSecondary)
        return peak > 0 ? Self.niceCeiling(peak * 1.15) : 100.0
    }

    /// Rounds up to 1, 2, 2.5 or 5 × 10ⁿ so axis labels are readable values.
    nonisolated static func niceCeiling(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(v)))
        for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * magnitude >= v {
            return step * magnitude
        }
        return 10 * magnitude
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Card Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(primaryColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                if let primaryLegend {
                    HStack(spacing: 4) {
                        Circle().fill(primaryColor).frame(width: 6, height: 6)
                        Text(primaryLegend)
                            .font(.system(size: 10))
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
                if let secondaryLegend, secondarySeries != nil {
                    HStack(spacing: 4) {
                        Circle().fill(secondaryColor).frame(width: 6, height: 6)
                        Text(secondaryLegend)
                            .font(.system(size: 10))
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
            }

            // Live Values (stacked on two lines so neither truncates)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryMetricText)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NordicTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .nordicMotion(NordicTheme.Motion.data, value: primaryMetricText)
                Text(secondaryMetricText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Area / Line Graph Canvas
            GeometryReader { geo in
                let size = geo.size
                let maxY = computedMaxY

                ZStack(alignment: .topLeading) {
                    // Grid at 0, ½ and the top of the scale, matching the plotted y range.
                    Path { path in
                        for fraction in [0.0, 0.5, 1.0] {
                            let y = plotY(fraction, height: size.height)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(NordicTheme.borderSubtle.opacity(0.8), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

                    if primarySeries.count >= 2 {
                        ForEach([1.0, 0.5], id: \.self) { fraction in
                            Text(valueFormatter(maxY * fraction))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(NordicTheme.secondaryText.opacity(0.85))
                                .padding(.horizontal, 3)
                                .background(NordicTheme.elevatedSurface.opacity(0.75))
                                // Top label just inside the chart, the middle one above its line.
                                .offset(x: 2, y: plotY(fraction, height: size.height) + (fraction == 1 ? 1 : -13))
                        }
                    }

                    // Secondary Series (if present, e.g. TX or Disk Write)
                    if let secondary = secondarySeries, secondary.count >= 2 {
                        seriesAreaPath(values: secondary, in: size, maxY: maxY)
                            .fill(
                                LinearGradient(
                                    colors: [secondaryColor.opacity(0.22), secondaryColor.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        seriesLinePath(values: secondary, in: size, maxY: maxY)
                            .stroke(secondaryColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }

                    // Primary Series
                    if primarySeries.count >= 2 {
                        seriesAreaPath(values: primarySeries, in: size, maxY: maxY)
                            .fill(
                                LinearGradient(
                                    colors: [primaryColor.opacity(0.28), primaryColor.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        seriesLinePath(values: primarySeries, in: size, maxY: maxY)
                            .stroke(primaryColor, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                    }

                    if let index = hoverIndex, primarySeries.count >= 2, index < primarySeries.count {
                        hoverOverlay(index: index, size: size, maxY: maxY)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard primarySeries.count >= 2 else { hoverIndex = nil; return }
                    switch phase {
                    case .active(let location):
                        let step = size.width / CGFloat(primarySeries.count - 1)
                        hoverIndex = max(0, min(primarySeries.count - 1, Int((location.x / step).rounded())))
                    case .ended:
                        hoverIndex = nil
                    }
                }
                .overlay {
                    // Rates need two snapshots; say so instead of drawing a flat line.
                    if primarySeries.count < 2 {
                        Text(placeholder)
                            .font(.system(size: 11))
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
            }
            .frame(height: 96)

            // Time span · peak and average · now
            if primarySeries.count >= 2 {
                HStack(spacing: 6) {
                    if let spanText { Text(spanText) }
                    Spacer(minLength: 4)
                    if let summaryText { Text(summaryText).lineLimit(1) }
                    Spacer(minLength: 4)
                    Text("now")
                }
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(NordicTheme.secondaryText)
            }
        }
        .padding(NordicTheme.Spacing.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nordicSurface()
    }

    /// Y position for a fraction of the scale, using the same 3 pt margins as the plotted points.
    private func plotY(_ fraction: Double, height: CGFloat) -> CGFloat {
        height - CGFloat(fraction) * (height - 6) - 3
    }

    @ViewBuilder
    private func hoverOverlay(index: Int, size: CGSize, maxY: Double) -> some View {
        let step = size.width / CGFloat(primarySeries.count - 1)
        let x = CGFloat(index) * step
        let primaryY = plotY(max(0, min(1, primarySeries[index] / maxY)), height: size.height)
        let secondaryValue = secondarySeries.flatMap { index < $0.count ? $0[index] : nil }
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(NordicTheme.secondaryText.opacity(0.5), lineWidth: 0.75)
        Circle().fill(primaryColor).frame(width: 6, height: 6).position(x: x, y: primaryY)
        if let secondaryValue {
            Circle().fill(secondaryColor).frame(width: 6, height: 6)
                .position(x: x, y: plotY(max(0, min(1, secondaryValue / maxY)), height: size.height))
        }
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(primaryColor).frame(width: 5, height: 5)
                Text("\(primaryLegend.map { "\($0) " } ?? "")\(valueFormatter(primarySeries[index]))")
            }
            if let secondaryValue {
                HStack(spacing: 4) {
                    Circle().fill(secondaryColor).frame(width: 5, height: 5)
                    Text("\(secondaryLegend.map { "\($0) " } ?? "")\(valueFormatter(secondaryValue))")
                }
            }
            if index < timestamps.count, let last = timestamps.last {
                Text(Self.formatAgo(last.timeIntervalSince(timestamps[index])))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(NordicTheme.primaryText)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(NordicTheme.borderSubtle, lineWidth: 1))
        .fixedSize()
        // Keep the readout inside the chart: flip to the left of the crosshair near the right edge.
        .offset(x: x > size.width * 0.6 ? x - 110 : x + 8, y: 2)
    }

    private func seriesPoints(values: [Double], in size: CGSize, maxY: Double) -> [CGPoint] {
        let padded: [Double]
        if values.count == 1 {
            padded = [values[0], values[0]]
        } else {
            padded = values
        }
        guard padded.count >= 2 else { return [] }
        let stepX = size.width / CGFloat(max(1, padded.count - 1))
        return padded.enumerated().map { index, val in
            let normalized = max(0.0, min(1.0, val / max(maxY, 0.0001)))
            let x = CGFloat(index) * stepX
            let y = size.height - (CGFloat(normalized) * (size.height - 6)) - 3
            return CGPoint(x: x, y: y)
        }
    }

    private func seriesLinePath(values: [Double], in size: CGSize, maxY: Double) -> Path {
        var path = Path()
        Self.addSmoothCurve(through: seriesPoints(values: values, in: size, maxY: maxY), to: &path, moveToStart: true)
        return path
    }

    private func seriesAreaPath(values: [Double], in size: CGSize, maxY: Double) -> Path {
        let pts = seriesPoints(values: values, in: size, maxY: maxY)
        var path = Path()
        guard let first = pts.first, let last = pts.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        Self.addSmoothCurve(through: pts, to: &path, moveToStart: false)
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }

    /// Monotone cubic interpolation (Fritsch–Carlson): smooth curves that never overshoot the
    /// samples, so a rate never appears to dip below zero or peak above what was measured.
    nonisolated static func addSmoothCurve(through pts: [CGPoint], to path: inout Path, moveToStart: Bool) {
        guard let first = pts.first else { return }
        if moveToStart { path.move(to: first) }
        guard pts.count > 2 else {
            if pts.count == 2 { path.addLine(to: pts[1]) }
            return
        }
        let n = pts.count
        var slopes = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = pts[i + 1].x - pts[i].x
            slopes[i] = dx == 0 ? 0 : (pts[i + 1].y - pts[i].y) / dx
        }
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
        }
        for i in 0..<(n - 1) where slopes[i] == 0 {
            tangents[i] = 0
            tangents[i + 1] = 0
        }
        for i in 0..<(n - 1) where slopes[i] != 0 {
            let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
            let h = a * a + b * b
            if h > 9 {
                let t = 3 / h.squareRoot()
                tangents[i] = t * a * slopes[i]
                tangents[i + 1] = t * b * slopes[i]
            }
        }
        for i in 0..<(n - 1) {
            let dx = (pts[i + 1].x - pts[i].x) / 3
            path.addCurve(
                to: pts[i + 1],
                control1: CGPoint(x: pts[i].x + dx, y: pts[i].y + tangents[i] * dx),
                control2: CGPoint(x: pts[i + 1].x - dx, y: pts[i + 1].y - tangents[i + 1] * dx)
            )
        }
    }
}


