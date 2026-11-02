import Foundation

/// A small VT100/xterm screen model for the in-app terminal.
///
/// It keeps a grid of character cells with a cursor and scrollback, and interprets the control
/// sequences shells and common tools emit: CR/LF/BS/TAB, cursor movement and positioning,
/// erase in line/display, insert/delete characters and lines, scroll regions, the alternate
/// screen (used by `vi`, `top`, `less`), SGR colours (16, 256 and true colour, bold, dim,
/// underline, inverse) and OSC titles (ignored). Output is rendered by `TerminalScreenRenderer`.
public struct TerminalScreen: Sendable {
    public enum Color: Equatable, Sendable {
        case indexed(Int)          // 0–255
        case rgb(UInt8, UInt8, UInt8)
    }

    public struct Style: Equatable, Sendable {
        public var foreground: Color?
        public var background: Color?
        public var bold = false
        public var dim = false
        public var underline = false
        public var inverse = false
    }

    public struct Cell: Equatable, Sendable {
        public var character: Character
        public var style: Style
        static let blank = Cell(character: " ", style: Style())
    }

    public private(set) var columns: Int
    public private(set) var rows: Int
    /// Lines that scrolled off the top of the main screen, oldest first.
    public private(set) var scrollback: [[Cell]] = []
    public private(set) var grid: [[Cell]]
    public private(set) var cursorRow = 0
    public private(set) var cursorColumn = 0
    public private(set) var cursorVisible = true
    public private(set) var isAlternateScreen = false
    /// Replies the terminal must send back to the program (e.g. cursor position reports).
    public private(set) var pendingReplies: [String] = []

    public let maxScrollback: Int

    private var style = Style()
    private var wrapPending = false
    private var scrollTop = 0
    private var scrollBottom: Int
    private var savedCursor: (row: Int, column: Int, style: Style) = (0, 0, Style())
    private var savedMainGrid: [[Cell]]?
    private var parser = ParserState.ground

    private enum ParserState: Sendable {
        case ground
        case escape
        case escapeCharset          // ESC ( / ESC ) — skip the next character
        case csi(params: String, isPrivate: Bool)
        case osc(sawEscape: Bool)
    }

    public init(columns: Int = 100, rows: Int = 28, maxScrollback: Int = 2000) {
        self.columns = max(2, columns)
        self.rows = max(2, rows)
        self.maxScrollback = maxScrollback
        self.grid = Array(repeating: Array(repeating: .blank, count: max(2, columns)), count: max(2, rows))
        self.scrollBottom = max(2, rows) - 1
    }

    // MARK: - Input

    public mutating func feed(_ text: String) {
        for scalar in text.unicodeScalars {
            process(scalar)
        }
    }

    /// Returns and clears the replies queued for the program.
    public mutating func takeReplies() -> [String] {
        defer { pendingReplies.removeAll() }
        return pendingReplies
    }

    public mutating func reset() {
        self = TerminalScreen(columns: columns, rows: rows, maxScrollback: maxScrollback)
    }

    public mutating func resize(columns newColumns: Int, rows newRows: Int) {
        let c = max(2, newColumns), r = max(2, newRows)
        guard c != columns || r != rows else { return }
        var lines = grid.map { line -> [Cell] in
            if line.count >= c { return Array(line.prefix(c)) }
            return line + Array(repeating: .blank, count: c - line.count)
        }
        if lines.count > r {
            // Keep the rows around the cursor; push the rest into scrollback.
            let overflow = min(lines.count - r, max(0, cursorRow - r + 1))
            if overflow > 0 {
                if !isAlternateScreen { appendScrollback(Array(lines.prefix(overflow))) }
                lines.removeFirst(overflow)
                cursorRow -= overflow
            }
            lines = Array(lines.prefix(r))
        } else if lines.count < r {
            lines += Array(repeating: Array(repeating: .blank, count: c), count: r - lines.count)
        }
        grid = lines
        columns = c
        rows = r
        scrollTop = 0
        scrollBottom = r - 1
        cursorRow = min(cursorRow, r - 1)
        cursorColumn = min(cursorColumn, c - 1)
        wrapPending = false
    }

    // MARK: - Parser

    private mutating func process(_ scalar: Unicode.Scalar) {
        switch parser {
        case .ground:
            ground(scalar)
        case .escape:
            escape(scalar)
        case .escapeCharset:
            parser = .ground
        case .csi(let params, let isPrivate):
            let v = scalar.value
            if v >= 0x40 && v <= 0x7E {
                parser = .ground
                csi(final: Character(scalar), params: params, isPrivate: isPrivate)
            } else if scalar == "?" || scalar == ">" || scalar == "=" {
                parser = .csi(params: params, isPrivate: true)
            } else if v == 0x1B {
                parser = .escape
            } else {
                parser = .csi(params: params + String(scalar), isPrivate: isPrivate)
            }
        case .osc(let sawEscape):
            if scalar.value == 0x07 || (sawEscape && scalar == "\\") {
                parser = .ground
            } else {
                parser = .osc(sawEscape: scalar.value == 0x1B)
            }
        }
    }

    private mutating func ground(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x1B: parser = .escape
        case 0x0D: cursorColumn = 0; wrapPending = false
        case 0x0A, 0x0B, 0x0C: lineFeed()
        case 0x08:
            wrapPending = false
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:
            wrapPending = false
            cursorColumn = min(columns - 1, (cursorColumn / 8 + 1) * 8)
        case 0x00..<0x20, 0x7F:
            break // BEL and other controls: ignored
        default:
            put(Character(scalar))
        }
    }

    private mutating func escape(_ scalar: Unicode.Scalar) {
        parser = .ground
        switch scalar {
        case "[": parser = .csi(params: "", isPrivate: false)
        case "]": parser = .osc(sawEscape: false)
        case "(", ")", "*", "+": parser = .escapeCharset
        case "7": saveCursor()
        case "8": restoreCursor()
        case "D": lineFeed()
        case "E": cursorColumn = 0; lineFeed()
        case "M": reverseIndex()
        case "c": reset()
        default: break // ESC = / ESC > keypad modes and others: ignored
        }
    }

    // MARK: - Cells

    private mutating func put(_ ch: Character) {
        if wrapPending {
            wrapPending = false
            cursorColumn = 0
            lineFeed()
        }
        grid[cursorRow][cursorColumn] = Cell(character: ch, style: style)
        if cursorColumn == columns - 1 {
            wrapPending = true
        } else {
            cursorColumn += 1
        }
    }

    private mutating func lineFeed() {
        wrapPending = false
        if cursorRow == scrollBottom {
            scrollUp(1)
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }

    private mutating func reverseIndex() {
        if cursorRow == scrollTop {
            scrollDown(1)
        } else if cursorRow > 0 {
            cursorRow -= 1
        }
    }

    private var blankLine: [Cell] {
        Array(repeating: Cell(character: " ", style: Style(background: style.background)), count: columns)
    }

    private mutating func scrollUp(_ n: Int) {
        for _ in 0..<max(1, n) {
            let removed = grid.remove(at: scrollTop)
            if scrollTop == 0 && !isAlternateScreen { appendScrollback([removed]) }
            grid.insert(blankLine, at: scrollBottom)
        }
    }

    private mutating func scrollDown(_ n: Int) {
        for _ in 0..<max(1, n) {
            grid.remove(at: scrollBottom)
            grid.insert(blankLine, at: scrollTop)
        }
    }

    private mutating func appendScrollback(_ lines: [[Cell]]) {
        scrollback.append(contentsOf: lines)
        if scrollback.count > maxScrollback {
            scrollback.removeFirst(scrollback.count - maxScrollback)
        }
    }

    private mutating func saveCursor() {
        savedCursor = (cursorRow, cursorColumn, style)
    }

    private mutating func restoreCursor() {
        cursorRow = min(savedCursor.row, rows - 1)
        cursorColumn = min(savedCursor.column, columns - 1)
        style = savedCursor.style
        wrapPending = false
    }

    // MARK: - CSI

    private mutating func csi(final: Character, params raw: String, isPrivate: Bool) {
        let params = raw.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        func p(_ i: Int, _ def: Int) -> Int {
            guard i < params.count, let v = params[i], v > 0 else { return def }
            return v
        }
        if isPrivate {
            if final == "h" || final == "l" { setPrivateModes(params.compactMap { $0 }, enabled: final == "h") }
            return
        }
        wrapPending = false
        switch final {
        case "A": cursorRow = max(scrollTopFor(cursorRow), cursorRow - p(0, 1))
        case "B", "e": cursorRow = min(scrollBottomFor(cursorRow), cursorRow + p(0, 1))
        case "C", "a": cursorColumn = min(columns - 1, cursorColumn + p(0, 1))
        case "D": cursorColumn = max(0, cursorColumn - p(0, 1))
        case "E": cursorColumn = 0; cursorRow = min(rows - 1, cursorRow + p(0, 1))
        case "F": cursorColumn = 0; cursorRow = max(0, cursorRow - p(0, 1))
        case "G", "`": cursorColumn = min(columns - 1, p(0, 1) - 1)
        case "d": cursorRow = min(rows - 1, p(0, 1) - 1)
        case "H", "f":
            cursorRow = min(rows - 1, p(0, 1) - 1)
            cursorColumn = min(columns - 1, p(1, 1) - 1)
        case "J": eraseDisplay(params.first.flatMap { $0 } ?? 0)
        case "K": eraseLine(params.first.flatMap { $0 } ?? 0)
        case "L": if (scrollTop...scrollBottom).contains(cursorRow) { insertLines(p(0, 1)) }
        case "M": if (scrollTop...scrollBottom).contains(cursorRow) { deleteLines(p(0, 1)) }
        case "@": insertCharacters(p(0, 1))
        case "P": deleteCharacters(p(0, 1))
        case "X":
            for c in cursorColumn..<min(columns, cursorColumn + p(0, 1)) { grid[cursorRow][c] = .blank }
        case "S": scrollUp(p(0, 1))
        case "T": scrollDown(p(0, 1))
        case "m": applySGR(params.map { $0 ?? 0 })
        case "r":
            let top = p(0, 1) - 1, bottom = min(rows, p(1, rows)) - 1
            if top < bottom { scrollTop = top; scrollBottom = bottom }
            cursorRow = 0; cursorColumn = 0
        case "s": saveCursor()
        case "u": restoreCursor()
        case "n":
            if p(0, 0) == 6 { pendingReplies.append("\u{1B}[\(cursorRow + 1);\(cursorColumn + 1)R") }
            else if p(0, 0) == 5 { pendingReplies.append("\u{1B}[0n") }
        case "c": pendingReplies.append("\u{1B}[?1;2c") // "VT100 with advanced video"
        default: break
        }
    }

    private func scrollTopFor(_ row: Int) -> Int { row >= scrollTop ? scrollTop : 0 }
    private func scrollBottomFor(_ row: Int) -> Int { row <= scrollBottom ? scrollBottom : rows - 1 }

    private mutating func setPrivateModes(_ modes: [Int], enabled: Bool) {
        for mode in modes {
            switch mode {
            case 25: cursorVisible = enabled
            case 47, 1047, 1049:
                if enabled && !isAlternateScreen {
                    if mode == 1049 { saveCursor() }
                    savedMainGrid = grid
                    grid = Array(repeating: Array(repeating: .blank, count: columns), count: rows)
                    isAlternateScreen = true
                } else if !enabled && isAlternateScreen {
                    grid = savedMainGrid ?? grid
                    savedMainGrid = nil
                    isAlternateScreen = false
                    if mode == 1049 { restoreCursor() }
                }
            default: break // bracketed paste (2004), mouse modes, app cursor keys: ignored
            }
        }
    }

    private mutating func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for r in (cursorRow + 1)..<rows { grid[r] = blankLine }
        case 1:
            for r in 0..<cursorRow { grid[r] = blankLine }
            eraseLine(1)
        case 2:
            // Like xterm, keep what was on screen in scrollback when clearing (e.g. `clear`).
            if !isAlternateScreen {
                let used = grid.lastIndex { $0.contains { $0.character != " " } }
                if let used { appendScrollback(Array(grid[0...used])) }
            }
            grid = Array(repeating: blankLine, count: rows)
        case 3:
            scrollback.removeAll()
        default: break
        }
    }

    private mutating func eraseLine(_ mode: Int) {
        let range: Range<Int>
        switch mode {
        case 0: range = cursorColumn..<columns
        case 1: range = 0..<min(columns, cursorColumn + 1)
        default: range = 0..<columns
        }
        for c in range { grid[cursorRow][c] = Cell(character: " ", style: Style(background: style.background)) }
    }

    private mutating func insertLines(_ n: Int) {
        for _ in 0..<n {
            grid.remove(at: scrollBottom)
            grid.insert(blankLine, at: cursorRow)
        }
    }

    private mutating func deleteLines(_ n: Int) {
        for _ in 0..<n {
            grid.remove(at: cursorRow)
            grid.insert(blankLine, at: scrollBottom)
        }
    }

    private mutating func insertCharacters(_ n: Int) {
        var line = grid[cursorRow]
        for _ in 0..<min(n, columns - cursorColumn) {
            line.insert(.blank, at: cursorColumn)
            line.removeLast()
        }
        grid[cursorRow] = line
    }

    private mutating func deleteCharacters(_ n: Int) {
        var line = grid[cursorRow]
        for _ in 0..<min(n, columns - cursorColumn) {
            line.remove(at: cursorColumn)
            line.append(.blank)
        }
        grid[cursorRow] = line
    }

    private mutating func applySGR(_ codes: [Int]) {
        let codes = codes.isEmpty ? [0] : codes
        var i = 0
        while i < codes.count {
            let code = codes[i]
            switch code {
            case 0: style = Style()
            case 1: style.bold = true
            case 2: style.dim = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22: style.bold = false; style.dim = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .indexed(code - 30)
            case 39: style.foreground = nil
            case 40...47: style.background = .indexed(code - 40)
            case 49: style.background = nil
            case 90...97: style.foreground = .indexed(code - 90 + 8)
            case 100...107: style.background = .indexed(code - 100 + 8)
            case 38, 48:
                var color: Color?
                if i + 2 < codes.count, codes[i + 1] == 5 {
                    color = .indexed(max(0, min(255, codes[i + 2]))); i += 2
                } else if i + 4 < codes.count, codes[i + 1] == 2 {
                    color = .rgb(UInt8(clamping: codes[i + 2]), UInt8(clamping: codes[i + 3]), UInt8(clamping: codes[i + 4])); i += 4
                }
                if code == 38 { style.foreground = color } else { style.background = color }
            default: break
            }
            i += 1
        }
    }

    // MARK: - Text

    /// Plain text of scrollback and screen, without trailing blank lines (for tests and copying).
    public var text: String {
        let lines = (scrollback + grid).map { String($0.map(\.character)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        var trimmed = lines
        while let last = trimmed.last, last.isEmpty { trimmed.removeLast() }
        return trimmed.joined(separator: "\n")
    }
}
