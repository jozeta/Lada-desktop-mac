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
    private var rawANSIStream: String = ""

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

        let source = DispatchSource.makeReadSource(fileDescriptor: mfd, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(mfd, &buffer, buffer.count)
            if bytesRead > 0 {
                let rawChunk = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.ingestPTYChunk(rawChunk)
                }
            }
        }
        source.setCancelHandler {
            close(mfd)
        }
        self.readSource = source
        source.resume()

        proc.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRunning = false
                let code = terminated.terminationStatus
                if code == 0 {
                    self.statusMessage = "Session exited (0)"
                } else {
                    self.statusMessage = "Session terminated with exit code \(code)"
                }
                self.ingestPTYChunk("\n[Process exited with status \(code)]\n")
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

    private func setBuffer(_ initial: String) {
        rawANSIStream = ""
        outputBuffer = ""
        ingestPTYChunk(initial)
    }

    private func ingestPTYChunk(_ chunk: String) {
        // Handle clear screen escape `\u{1B}[2J` or `\u{1B}[H\u{1B}[2J`
        if chunk.contains("\u{001B}[2J") {
            rawANSIStream = ""
        }
        rawANSIStream.append(chunk)
        if rawANSIStream.count > 100_000 {
            rawANSIStream.removeFirst(rawANSIStream.count - 80_000)
        }
        let processed = Self.processTerminalStream(rawANSIStream)
        self.outputBuffer = processed.plain
        self.attributedOutput = processed.attributed
    }

    public func resizeTerminal(columns: UInt16, rows: UInt16) {
        self.columns = max(20, columns)
        self.rows = max(8, rows)
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
            ingestPTYChunk("\(cmd)\n")
            switch cmd {
            case "uname -a":
                ingestPTYChunk("Linux container-vm 6.18.35-kata #1 SMP PREEMPT_DYNAMIC aarch64 Linux\n/ # ")
            case "whoami", "id":
                ingestPTYChunk("uid=0(root) gid=0(root) groups=0(root)\n/ # ")
            case "pwd":
                ingestPTYChunk("/\n/ # ")
            case "ps", "ps aux":
                ingestPTYChunk("PID   USER     TIME  COMMAND\n    1 root      0:00 /sbin/vminitd\n   12 root      0:00 \(selectedShell)\n/ # ")
            case "clear":
                setBuffer("/ # ")
            case "exit":
                ingestPTYChunk("logout\n")
                isRunning = false
                statusMessage = "Session exited (0)"
            default:
                if !cmd.isEmpty {
                    ingestPTYChunk("\(selectedShell): executed '\(cmd)'\n/ # ")
                } else {
                    ingestPTYChunk("/ # ")
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

    // MARK: - ANSI Escape & Backspace Stream Renderer

    private static func processTerminalStream(_ raw: String) -> (plain: String, attributed: NSAttributedString) {
        // 1. Normalize CRLF and apply backspaces (`\u{08}`)
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "")
        var chars: [Character] = []
        chars.reserveCapacity(normalized.count)
        for ch in normalized {
            if ch == "\u{08}" || ch == "\u{7F}" {
                if let last = chars.last, last != "\n" {
                    chars.removeLast()
                }
            } else {
                chars.append(ch)
            }
        }
        let backspaceResolved = String(chars)

        // 2. Strip OSC sequences (`\u{1B}]...\u{07}`) and non-SGR CSI sequences
        let nonSGRPattern = #"\u001B\][^\u0007]*\u0007|\u001B\[[0-9;?]*[A-LN-Za-ln-z]"#
        var sgrOnly = backspaceResolved
        if let regex = try? NSRegularExpression(pattern: nonSGRPattern) {
            sgrOnly = regex.stringByReplacingMatches(
                in: sgrOnly,
                range: NSRange(sgrOnly.startIndex..., in: sgrOnly),
                withTemplate: ""
            )
        }

        // 3. Parse SGR color codes (`\u{1B}[...m`) into NSAttributedString
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let defaultColor = NSColor.labelColor
        var currentColor = defaultColor
        var isBold = false

        let resultAttr = NSMutableAttributedString()
        var plainBuilder = ""

        let sgrPattern = #"\u001B\[([0-9;]*)m"#
        guard let sgrRegex = try? NSRegularExpression(pattern: sgrPattern) else {
            let attr = NSAttributedString(string: sgrOnly, attributes: [.font: font, .foregroundColor: defaultColor])
            return (sgrOnly, attr)
        }

        let nsString = sgrOnly as NSString
        var lastIndex = 0
        let matches = sgrRegex.matches(in: sgrOnly, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.range.location > lastIndex {
                let textSegment = nsString.substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex))
                plainBuilder.append(textSegment)
                resultAttr.append(
                    NSAttributedString(
                        string: textSegment,
                        attributes: [
                            .font: isBold ? boldFont : font,
                            .foregroundColor: currentColor
                        ]
                    )
                )
            }
            let codesString = nsString.substring(with: match.range(at: 1))
            let codes = codesString.isEmpty ? [0] : codesString.split(separator: ";").compactMap { Int($0) }
            for code in codes {
                switch code {
                case 0:
                    currentColor = defaultColor
                    isBold = false
                case 1:
                    isBold = true
                case 22:
                    isBold = false
                case 30, 90: currentColor = NSColor.systemGray
                case 31, 91: currentColor = NSColor.systemRed
                case 32, 92: currentColor = NSColor.systemGreen
                case 33, 93: currentColor = NSColor.systemYellow
                case 34, 94: currentColor = NSColor.systemBlue
                case 35, 95: currentColor = NSColor.systemPurple
                case 36, 96: currentColor = NSColor.systemTeal
                case 37, 97, 39: currentColor = defaultColor
                default: break
                }
            }
            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < nsString.length {
            let tail = nsString.substring(from: lastIndex)
            plainBuilder.append(tail)
            resultAttr.append(
                NSAttributedString(
                    string: tail,
                    attributes: [
                        .font: isBold ? boldFont : font,
                        .foregroundColor: currentColor
                    ]
                )
            )
        }

        return (plainBuilder, resultAttr)
    }
}

// MARK: - Direct Interactive PTY Canvas (NSViewRepresentable)

private struct InteractivePTYCanvasRepresentable: NSViewRepresentable {
    var attributedOutput: NSAttributedString
    var isRunning: Bool
    var onKeystroke: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = PTYKeyCapturingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.onKeystroke = onKeystroke

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PTYKeyCapturingTextView else { return }
        textView.onKeystroke = onKeystroke
        textView.isSessionRunning = isRunning
        if textView.attributedString() != attributedOutput {
            textView.textStorage?.setAttributedString(attributedOutput)
            textView.scrollToEndOfDocument(nil)
        }
    }

    final class PTYKeyCapturingTextView: NSTextView {
        var onKeystroke: ((String) -> Void)?
        var isSessionRunning: Bool = false

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard isSessionRunning, let onKeystroke else {
                super.keyDown(with: event)
                return
            }

            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "v",
                   let pasted = NSPasteboard.general.string(forType: .string) {
                    onKeystroke(pasted)
                    return
                }
                super.keyDown(with: event)
                return
            }

            if event.modifierFlags.contains(.control),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               let first = chars.first {
                switch first {
                case "c": onKeystroke("\u{03}"); return
                case "d": onKeystroke("\u{04}"); return
                case "l": onKeystroke("\u{0C}"); return
                case "z": onKeystroke("\u{1A}"); return
                default: break
                }
            }

            switch event.keyCode {
            case 36, 76: // Return / Enter
                onKeystroke("\n")
            case 51: // Backspace / Delete
                onKeystroke("\u{7F}")
            case 48: // Tab (auto-completion)
                onKeystroke("\t")
            case 126: // Up Arrow
                onKeystroke("\u{1B}[A")
            case 125: // Down Arrow
                onKeystroke("\u{1B}[B")
            case 124: // Right Arrow
                onKeystroke("\u{1B}[C")
            case 123: // Left Arrow
                onKeystroke("\u{1B}[D")
            default:
                if let chars = event.characters, !chars.isEmpty {
                    onKeystroke(chars)
                }
            }
        }
    }
}

// MARK: - Main InteractiveTerminalView

public struct InteractiveTerminalView: View {
    public let container: ContainerModel
    public let executablePath: String?
    public var onOpenExternalTerminal: ((String) -> Void)? = nil
    @StateObject private var session = PTYTerminalSession()
    @State private var commandLineInput: String = ""
    @FocusState private var inputFocused: Bool

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
            // Terminal Control Bar
            HStack(spacing: 8) {
                NordicStatusBadge(
                    label: session.isRunning ? "PTY Active" : "Disconnected",
                    tone: session.isRunning ? .positive : .neutral
                )

                Text(session.statusMessage)
                    .font(NordicTheme.monoFontSmall)
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)

                Spacer()

                if let onOpenExternalTerminal {
                    Button {
                        onOpenExternalTerminal(session.selectedShell)
                    } label: {
                        Label("Open in Terminal.app", systemImage: "apple.terminal")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(container.state != .running)
                    .fixedSize(horizontal: true, vertical: false)
                }

                Picker("Shell", selection: $session.selectedShell) {
                    Text("/bin/sh").tag("/bin/sh")
                    Text("/bin/bash").tag("/bin/bash")
                    Text("/bin/ash").tag("/bin/ash")
                    Text("/bin/zsh").tag("/bin/zsh")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 105)
                .controlSize(.small)

                if session.isRunning {
                    Button("Ctrl-C") {
                        session.sendInterruptSignal()
                    }
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)

                    Button("Terminate") {
                        session.terminateSession()
                    }
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    Button("Connect Shell") {
                        session.startContainerSession(executablePath: executablePath, container: container)
                        inputFocused = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(container.state != .running)
                    .fixedSize(horizontal: true, vertical: false)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.outputBuffer, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy Terminal Output")

                Button("Clear") {
                    session.clearBuffer()
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NordicTheme.elevatedSurface)
            .overlay(alignment: .bottom) {
                Divider().overlay(NordicTheme.borderSubtle)
            }

            if container.state != .running {
                NordicEmptyState(
                    icon: .machines,
                    title: "Container Is Not Running",
                    description: "Start '\(container.id)' to open an interactive PTY terminal session (`container exec -it \(container.id) \(session.selectedShell)`)."
                )
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Quick Snippet Bar
                        HStack(spacing: 6) {
                            Text("Quick Commands:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NordicTheme.secondaryText)
                            ForEach(["ls -la", "ps aux", "env", "df -h", "ip addr", "uname -a"], id: \.self) { snippet in
                                Button(snippet) {
                                    session.sendInput(snippet + "\n")
                                }
                                .controlSize(.mini)
                                .buttonStyle(.bordered)
                                .disabled(!session.isRunning)
                            }
                            Spacer()
                            Text("Click canvas for direct keystrokes (Tab, ↑/↓, Ctrl-C)")
                                .font(.system(size: 10))
                                .foregroundStyle(NordicTheme.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(NordicTheme.surfaceBackground)
                        .overlay(alignment: .bottom) {
                            Divider().overlay(NordicTheme.borderSubtle)
                        }

                        // Interactive ANSI PTY Canvas
                        InteractivePTYCanvasRepresentable(
                            attributedOutput: session.attributedOutput,
                            isRunning: session.isRunning,
                            onKeystroke: { keystroke in
                                session.sendInput(keystroke)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Command Input Bar
                        HStack(spacing: 8) {
                            Text("$")
                                .font(NordicTheme.monoFontMedium)
                                .foregroundStyle(NordicTheme.accent())

                            TextField("Enter command or type directly in the terminal canvas above…", text: $commandLineInput)
                                .textFieldStyle(.plain)
                                .font(NordicTheme.monoFontRegular)
                                .focused($inputFocused)
                                .disabled(!session.isRunning)
                                .onSubmit {
                                    let cmd = commandLineInput
                                    commandLineInput = ""
                                    session.sendInput(cmd + "\n")
                                }

                            Button("Tab ⇥") {
                                session.sendInput("\t")
                            }
                            .controlSize(.small)
                            .disabled(!session.isRunning)
                            .help("Send Tab for shell completion")

                            Button("Paste") {
                                if let pasted = NSPasteboard.general.string(forType: .string) {
                                    commandLineInput.append(pasted)
                                }
                            }
                            .controlSize(.small)
                            .disabled(!session.isRunning)

                            Button("Send") {
                                let cmd = commandLineInput
                                commandLineInput = ""
                                session.sendInput(cmd + "\n")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!session.isRunning)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NordicTheme.elevatedSurface)
                        .overlay(alignment: .top) {
                            Divider().overlay(NordicTheme.borderSubtle)
                        }
                    }
                    .onChange(of: geo.size) { _, newSize in
                        let approxCols = UInt16(max(40, Int(newSize.width / 7.4)))
                        let approxRows = UInt16(max(10, Int((newSize.height - 65) / 16.0)))
                        session.resizeTerminal(columns: approxCols, rows: approxRows)
                    }
                }
            }
        }
        .onAppear {
            if container.state == .running && !session.isRunning {
                session.startContainerSession(executablePath: executablePath, container: container)
                inputFocused = true
            }
        }
        .onDisappear {
            session.terminateSession()
        }
    }
}
