import AppKit

/// Turns a `TerminalScreen` into styled text for the terminal view: a dark background, a
/// monospaced font, a 16-colour palette tuned to the Nordic theme (plus the xterm 256-colour
/// cube and true colour), and a block cursor.
enum TerminalScreenRenderer {
    static let background = NSColor(srgbRed: 0.075, green: 0.082, blue: 0.098, alpha: 1)   // #131519
    static let foreground = NSColor(srgbRed: 0.851, green: 0.871, blue: 0.894, alpha: 1)   // #D9DEE4
    static let cursorColor = NSColor(srgbRed: 0.533, green: 0.753, blue: 0.816, alpha: 1)  // #88C0D0

    static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    }

    static var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
    }

    /// Black, red, green, yellow, blue, magenta, cyan, white, then the bright variants.
    private static let ansi16: [NSColor] = [
        (0x3B, 0x42, 0x52), (0xE0, 0x6C, 0x75), (0x98, 0xC3, 0x79), (0xE5, 0xC0, 0x7B),
        (0x61, 0xAF, 0xEF), (0xC6, 0x78, 0xDD), (0x56, 0xB6, 0xC2), (0xD9, 0xDE, 0xE4),
        (0x6B, 0x73, 0x84), (0xF0, 0x83, 0x8C), (0xA8, 0xD5, 0x88), (0xF2, 0xD0, 0x8C),
        (0x82, 0xC1, 0xF5), (0xD6, 0x95, 0xE6), (0x75, 0xCC, 0xD6), (0xFF, 0xFF, 0xFF)
    ].map { NSColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }

    static func color(_ c: TerminalScreen.Color) -> NSColor {
        switch c {
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        case .indexed(let i) where i < 16:
            return ansi16[i]
        case .indexed(let i) where i < 232:
            // 6×6×6 colour cube.
            let n = i - 16
            let level: (Int) -> CGFloat = { $0 == 0 ? 0 : CGFloat(55 + $0 * 40) / 255 }
            return NSColor(srgbRed: level(n / 36), green: level((n / 6) % 6), blue: level(n % 6), alpha: 1)
        case .indexed(let i):
            let gray = CGFloat(8 + (min(i, 255) - 232) * 10) / 255
            return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
        }
    }

    /// Scrollback plus the screen down to the last used row (or the cursor), with the cursor drawn
    /// as an inverted block when the terminal is live.
    static func render(_ screen: TerminalScreen, showCursor: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lastUsed = screen.grid.lastIndex { $0.contains { $0.character != " " || $0.style.background != nil } } ?? 0
        let lastRow = max(lastUsed, screen.cursorRow)
        let lines = screen.scrollback + Array(screen.grid[0...lastRow])
        let cursorLine = screen.scrollback.count + screen.cursorRow
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.08

        for (index, line) in lines.enumerated() {
            let isCursorLine = showCursor && screen.cursorVisible && index == cursorLine
            // Trim trailing default blanks, but keep the cursor cell.
            var end = line.count
            while end > 0, line[end - 1] == .blank, !(isCursorLine && end - 1 <= screen.cursorColumn) { end -= 1 }
            if isCursorLine { end = max(end, screen.cursorColumn + 1) }

            var run = ""
            var runStyle: TerminalScreen.Style?
            var runIsCursor = false
            func flush() {
                guard !run.isEmpty, let s = runStyle else { return }
                out.append(NSAttributedString(string: run, attributes: attributes(for: s, cursor: runIsCursor, paragraph: paragraph)))
                run = ""
            }
            for col in 0..<min(end, line.count) {
                let cell = line[col]
                let isCursor = isCursorLine && col == screen.cursorColumn
                if cell.style != runStyle || isCursor != runIsCursor {
                    flush()
                    runStyle = cell.style
                    runIsCursor = isCursor
                }
                run.append(cell.character)
            }
            flush()
            if index < lines.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
            }
        }
        return out
    }

    private static func attributes(for style: TerminalScreen.Style, cursor: Bool, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var fg = style.foreground.map(color) ?? foreground
        var bg = style.background.map(color)
        if style.bold, case .indexed(let i)? = style.foreground, i < 8 { fg = ansi16[i + 8] } // bold → bright
        if style.dim { fg = fg.withAlphaComponent(0.6) }
        if style.inverse { (fg, bg) = (bg ?? background, fg) }
        if cursor { (fg, bg) = (background, cursorColor) }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: style.bold ? boldFont : font,
            .foregroundColor: fg,
            .paragraphStyle: paragraph
        ]
        if let bg { attrs[.backgroundColor] = bg }
        if style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }
}
