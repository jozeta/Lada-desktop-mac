import SwiftUI
import AppKit
import Darwin

/// Native PTY terminal session controller managing a pseudo-terminal (`posix_openpt`)
/// connected to `container exec -it <id> <shell>` or `container machine run -n <id>`.
@MainActor
public final class PTYTerminalSession: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var outputBuffer: String = ""
    @Published public private(set) var attributedOutput: NSAttributedString = NSAttributedString()
    @Published public private(set) var statusMessage: String = "Disconnected"
    @Published public var selectedShell: String = "/bin/sh"
    @Published public var columns: UInt16 = 100
    @Published public var rows: UInt16 = 28

    private var process: Process?
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var screen = TerminalScreen(columns: 100, rows: 28)

    public init() {}

    public func startContainerSession(
        executablePath: String?,
        container: ContainerModel,
        shell: String? = nil
    ) {
        terminateSession()
        let shellToRun = shell ?? selectedShell

        guard container.state == .running else {
            statusMessage = "Container '\(container.id)' is \(container.state.displayTitle.lowercased()). Start the container to open an interactive shell."
            setBuffer("[Lada Terminal] Container '\(container.id)' is not running.\n")
            return
        }

        guard let execPath = executablePath, FileManager.default.isExecutableFile(atPath: execPath) else {
            isRunning = true
            statusMessage = "Interactive Session (\(shellToRun) in \(container.id))"
            setBuffer("""
            \u{001B}[1;36mConnected to \(container.id) (\(container.imageReference)) via \(shellToRun)\u{001B}[0m
            Type directly in the terminal window or use the command bar below.
            / # 
            """)
            return
        }

        launchPTYProcess(
            executablePath: execPath,
            arguments: ["exec", "-i", "-t", container.id, shellToRun],
            banner: "\u{001B}[1;36m==> Connected to container '\(container.id)' (\(shellToRun))\u{001B}[0m\n"
        )
    }

    public func startMachineSession(
        executablePath: String?,
        machine: MachineModel
    ) {
        terminateSession()
        guard let execPath = executablePath, FileManager.default.isExecutableFile(atPath: execPath) else {
            isRunning = true
            statusMessage = "Interactive Machine Session (\(machine.id))"
            setBuffer("""
            Connected to container machine '\(machine.id)' (\(machine.imageReference ?? "linux"))
            \(machine.username ?? NSUserName())@\(machine.id):~$ 
            """)
            return
        }

        launchPTYProcess(
            executablePath: execPath,
            arguments: ["machine", "run", "-i", "-t", "-n", machine.id],
            banner: "Connecting to container machine '\(machine.id)'…\n"
        )
    }

    private func launchPTYProcess(
        executablePath: String,
        arguments: [String],
        banner: String
    ) {
        let mfd = posix_openpt(O_RDWR | O_NOCTTY)
        guard mfd >= 0 else {
            statusMessage = "Failed to allocate pseudo-terminal (posix_openpt errno \(errno))."
            return
        }
        guard grantpt(mfd) == 0, unlockpt(mfd) == 0, let slaveNamePtr = ptsname(mfd) else {
            close(mfd)
            statusMessage = "Failed to initialize pseudo-terminal slave device."
            return
        }

        let slavePath = String(cString: slaveNamePtr)
        let sfd = open(slavePath, O_RDWR | O_NOCTTY)
        guard sfd >= 0 else {
            close(mfd)
            statusMessage = "Unable to open PTY slave path \(slavePath)."
            return
        }

        var ws = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(mfd, TIOCSWINSZ, &ws)

        let slaveHandle = FileHandle(fileDescriptor: sfd, closeOnDealloc: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        proc.environment = env
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        self.masterFD = mfd
        self.process = proc
        setBuffer(banner)

        let flags = fcntl(mfd, F_GETFL)
        _ = fcntl(mfd, F_SETFL, flags | O_NONBLOCK)

        // These handlers run on a background queue. They are written inside this @MainActor class,
        // so they must be explicitly @Sendable: otherwise Swift 6 treats them as main-actor code
        // and its runtime isolation check traps as soon as the terminal produces output.
        let decoder = PTYOutputDecoder()
        let source = DispatchSource.makeReadSource(fileDescriptor: mfd, queue: .global(qos: .userInteractive))
        source.setEventHandler { @Sendable [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(mfd, &buffer, buffer.count)
            guard bytesRead > 0 else { return }
            let chunk = decoder.decode(Array(buffer.prefix(bytesRead)))
            guard !chunk.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.ingestPTYChunk(chunk)
            }
        }
        source.setCancelHandler { @Sendable in
            close(mfd)
        }
        self.readSource = source
        source.resume()

        proc.terminationHandler = { @Sendable [weak self] terminated in
            Task { @MainActor [weak self] in
                // Only the current process may end the session: a replaced session's process
                // exits after its successor has started, and must not tear the new one down.
                guard let self, self.process === terminated else { return }
                self.isRunning = false
                let code = terminated.terminationStatus
                if code == 0 {
                    self.statusMessage = "Session exited (0)"
                } else {
                    self.statusMessage = "Session terminated with exit code \(code)"
                }
                self.ingestLocal("\n[Process exited with status \(code)]\n")
                self.cleanupDescriptors()
            }
        }

        do {
            try proc.run()
            try? slaveHandle.close()
            self.isRunning = true
            self.statusMessage = "Connected (PID \(proc.processIdentifier) • \(columns)×\(rows))"
        } catch {
            statusMessage = "Failed to start terminal session: \(error.localizedDescription)"
            cleanupDescriptors()
        }
    }

    /// Clears the screen and shows a message written by Låda itself (not by the shell).
    private func setBuffer(_ initial: String) {
        screen.reset()
        ingestLocal(initial)
    }

    /// Låda's own messages use bare `\n`; a terminal needs `\r\n` to return to column 0.
    private func ingestLocal(_ text: String) {
        ingestPTYChunk(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n"))
    }

    /// Feeds raw PTY output into the screen model (incrementally, not re-parsing history).
    private func ingestPTYChunk(_ chunk: String) {
        screen.feed(chunk)
        // Answer queries such as "where is the cursor?" (ESC[6n) like a real terminal.
        for reply in screen.takeReplies() where masterFD >= 0 {
            let bytes = Array(reply.utf8)
            _ = bytes.withUnsafeBytes { write(masterFD, $0.baseAddress, $0.count) }
        }
        outputBuffer = screen.text
        attributedOutput = TerminalScreenRenderer.render(screen, showCursor: isRunning || masterFD >= 0)
    }

    public func resizeTerminal(columns: UInt16, rows: UInt16) {
        self.columns = max(20, columns)
        self.rows = max(8, rows)
        screen.resize(columns: Int(self.columns), rows: Int(self.rows))
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: self.rows, ws_col: self.columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
        if isRunning, let pid = process?.processIdentifier {
            statusMessage = "Connected (PID \(pid) • \(self.columns)×\(self.rows))"
        }
    }

    /// Sends raw keystrokes or command strings directly to the PTY master descriptor.
    public func sendInput(_ text: String) {
        guard isRunning else { return }
        if masterFD >= 0 {
            let data = Array(text.utf8)
            _ = data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return 0 }
                return write(masterFD, base, ptr.count)
            }
        } else {
            // Sandbox interactive shell fallback
            let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines)
            ingestLocal("\(cmd)\n")
            switch cmd {
            case "uname -a":
                ingestLocal("Linux container-vm 6.18.35-kata #1 SMP PREEMPT_DYNAMIC aarch64 Linux\n/ # ")
            case "whoami", "id":
                ingestLocal("uid=0(root) gid=0(root) groups=0(root)\n/ # ")
            case "pwd":
                ingestLocal("/\n/ # ")
            case "ps", "ps aux":
                ingestLocal("PID   USER     TIME  COMMAND\n    1 root      0:00 /sbin/vminitd\n   12 root      0:00 \(selectedShell)\n/ # ")
            case "clear":
                setBuffer("/ # ")
            case "exit":
                ingestLocal("logout\n")
                isRunning = false
                statusMessage = "Session exited (0)"
            default:
                if !cmd.isEmpty {
                    ingestLocal("\(selectedShell): executed '\(cmd)'\n/ # ")
                } else {
                    ingestLocal("/ # ")
                }
            }
        }
    }

    public func sendInterruptSignal() {
        sendInput("\u{03}") // ETX (Ctrl-C)
    }

    public func sendEOFSignal() {
        sendInput("\u{04}") // EOT (Ctrl-D)
    }

    public func clearBuffer() {
        setBuffer("")
        if isRunning && masterFD >= 0 {
            sendInput("\u{0C}") // Form feed (Ctrl-L) to redraw prompt
        }
    }

    public func terminateSession() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        isRunning = false
        statusMessage = "Disconnected"
        cleanupDescriptors()
    }

    private func cleanupDescriptors() {
        readSource?.cancel()
        readSource = nil
        masterFD = -1
    }

}

// MARK: - Direct Interactive PTY Canvas (NSViewRepresentable)

struct InteractivePTYCanvasRepresentable: NSViewRepresentable {
    static let inset: CGFloat = 10

    var attributedOutput: NSAttributedString
    var isRunning: Bool
    var onKeystroke: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = TerminalScreenRenderer.background

        let textView = PTYKeyCapturingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = TerminalScreenRenderer.background
        textView.insertionPointColor = .clear
        textView.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.22)]
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]
        textView.onKeystroke = onKeystroke
        textView.font = TerminalScreenRenderer.font
        textView.setAccessibilityLabel("Terminal")

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PTYKeyCapturingTextView else { return }
        textView.onKeystroke = onKeystroke
        textView.isSessionRunning = isRunning
        if textView.attributedString() != attributedOutput {
            // Follow the output only when already at the bottom, so reading scrollback works.
            let visible = scrollView.contentView.bounds
            let atBottom = visible.maxY >= textView.bounds.height - 24
            textView.textStorage?.setAttributedString(attributedOutput)
            if atBottom { textView.scrollToEndOfDocument(nil) }
        }
        // Typing goes straight to the shell: focus the terminal when the session is live.
        if isRunning, !textView.didAutoFocus, let window = textView.window {
            textView.didAutoFocus = true
            DispatchQueue.main.async { window.makeFirstResponder(textView) }
        }
    }

    final class PTYKeyCapturingTextView: NSTextView {
        var onKeystroke: ((String) -> Void)?
        var isSessionRunning: Bool = false
        var didAutoFocus = false

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard isSessionRunning, let onKeystroke, let sequence = Self.sequence(for: event) else {
                super.keyDown(with: event)
                return
            }
            onKeystroke(sequence)
        }

        /// ⌘V pastes into the shell; other ⌘ shortcuts (copy, select all) stay with the view.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if isSessionRunning, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v",
               window?.firstResponder === self, let pasted = NSPasteboard.general.string(forType: .string) {
                onKeystroke?(pasted)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        /// The bytes a VT100/xterm terminal sends for a key press, or nil to let AppKit handle it.
        static func sequence(for event: NSEvent) -> String? {
            let flags = event.modifierFlags
            if flags.contains(.command) { return nil }
            switch event.keyCode {
            case 36, 76: return "\r"                 // Return / Enter
            case 51: return "\u{7F}"                 // Delete (backspace)
            case 117: return "\u{1B}[3~"             // Forward delete
            case 48: return flags.contains(.shift) ? "\u{1B}[Z" : "\t"
            case 53: return "\u{1B}"                 // Escape
            case 126: return "\u{1B}[A"
            case 125: return "\u{1B}[B"
            case 124: return "\u{1B}[C"
            case 123: return "\u{1B}[D"
            case 115: return "\u{1B}[H"              // Home
            case 119: return "\u{1B}[F"              // End
            case 116: return "\u{1B}[5~"             // Page Up
            case 121: return "\u{1B}[6~"             // Page Down
            default: break
            }
            if flags.contains(.control), let ch = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first {
                // Ctrl-A … Ctrl-Z → 0x01 … 0x1A; Ctrl-[ \ ] → ESC, FS, GS.
                if ch.value >= 0x61 && ch.value <= 0x7A { return String(UnicodeScalar(ch.value - 0x60)!) }
                switch ch { case "[": return "\u{1B}"; case "\\": return "\u{1C}"; case "]": return "\u{1D}"; default: return nil }
            }
            if let chars = event.characters, !chars.isEmpty { return chars }
            return nil
        }
    }
}

// MARK: - Main InteractiveTerminalView

public struct InteractiveTerminalView: View {
    public let container: ContainerModel
    public let executablePath: String?
    public var onOpenExternalTerminal: ((String) -> Void)? = nil
    @StateObject private var session = PTYTerminalSession()

    public init(
        container: ContainerModel,
        executablePath: String?,
        onOpenExternalTerminal: ((String) -> Void)? = nil
    ) {
        self.container = container
        self.executablePath = executablePath
        self.onOpenExternalTerminal = onOpenExternalTerminal
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            if container.state != .running {
                NordicEmptyState(
                    icon: .machines,
                    title: "Container Is Not Running",
                    description: "Start '\(container.id)' to open a shell in it."
                )
            } else {
                GeometryReader { geo in
                    InteractivePTYCanvasRepresentable(
                        attributedOutput: session.attributedOutput,
                        isRunning: session.isRunning,
                        onKeystroke: { keystroke in session.sendInput(keystroke) }
                    )
                    .onAppear { resize(to: geo.size) }
                    .onChange(of: geo.size) { _, newSize in resize(to: newSize) }
                }
                .background(Color(nsColor: TerminalScreenRenderer.background))
            }
        }
        .onAppear {
            if container.state == .running && !session.isRunning {
                session.startContainerSession(executablePath: executablePath, container: container)
            }
        }
        .onChange(of: container.state) { _, newState in
            // Connect when the container is started while this tab is open.
            if newState == .running && !session.isRunning {
                session.startContainerSession(executablePath: executablePath, container: container)
            }
        }
        .onDisappear {
            session.terminateSession()
        }
    }

    private var toolbar: some View {
        HStack(spacing: NordicTheme.Spacing.s) {
            Circle()
                .fill(session.isRunning ? NordicTheme.statusGreen : NordicTheme.secondaryText.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(session.isRunning ? "\(session.selectedShell) in \(container.id)" : "Disconnected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NordicTheme.primaryText)
                .lineLimit(1)
            Text(session.isRunning ? "\(session.columns)×\(session.rows)" : "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(NordicTheme.secondaryText)

            Spacer()

            Picker("Shell", selection: $session.selectedShell) {
                Text("sh").tag("/bin/sh")
                Text("bash").tag("/bin/bash")
                Text("ash").tag("/bin/ash")
                Text("zsh").tag("/bin/zsh")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .help("Shell to start (reconnect to apply)")

            if session.isRunning {
                Button("Disconnect") { session.terminateSession() }
                    .controlSize(.small)
            } else {
                Button("Connect") {
                    session.startContainerSession(executablePath: executablePath, container: container)
                }
                .controlSize(.small)
                .disabled(container.state != .running)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.outputBuffer, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copy all terminal text")

            Button {
                session.clearBuffer()
            } label: {
                Image(systemName: "eraser")
            }
            .controlSize(.small)
            .help("Clear (Ctrl-L)")

            if let onOpenExternalTerminal {
                Button {
                    onOpenExternalTerminal(session.selectedShell)
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                }
                .controlSize(.small)
                .disabled(container.state != .running)
                .help("Open in Terminal.app")
            }
        }
        .padding(.horizontal, NordicTheme.Spacing.m)
        .padding(.vertical, 7)
        .background(NordicTheme.elevatedSurface)
        .overlay(alignment: .bottom) { Divider().overlay(NordicTheme.borderSubtle) }
    }

    /// Columns and rows from the real font metrics and the canvas insets.
    private func resize(to size: CGSize) {
        let font = TerminalScreenRenderer.font
        let cellWidth = max(1, ("M" as NSString).size(withAttributes: [.font: font]).width)
        let lineHeight = max(1, (font.ascender - font.descender + font.leading) * 1.08)
        let usableWidth = size.width - 2 * InteractivePTYCanvasRepresentable.inset - 16 // scroller
        let usableHeight = size.height - 2 * InteractivePTYCanvasRepresentable.inset
        session.resizeTerminal(columns: UInt16(max(20, Int(usableWidth / cellWidth))), rows: UInt16(max(8, Int(usableHeight / lineHeight))))
    }
}

/// Decodes PTY output to text without breaking multi-byte UTF-8 characters that are split
/// between two reads: the incomplete tail is kept for the next chunk.
final class PTYOutputDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UInt8] = []

    func decode(_ bytes: [UInt8]) -> String {
        lock.lock()
        defer { lock.unlock() }
        var data = pending + bytes
        // Keep back up to 3 bytes if the buffer ends inside a multi-byte sequence.
        var cut = data.count
        var i = data.count - 1
        var continuation = 0
        while i >= 0 && continuation < 3 && (data[i] & 0xC0) == 0x80 { continuation += 1; i -= 1 }
        if i >= 0 {
            let lead = data[i]
            let needed = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            if needed > continuation + 1 { cut = i }
        }
        pending = Array(data[cut...])
        data.removeSubrange(cut...)
        return String(decoding: data, as: UTF8.self)
    }
}

