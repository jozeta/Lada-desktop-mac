import XCTest
@testable import Lada

final class TerminalScreenTests: XCTestCase {
    /// Raw output captured from `container exec -i -t nginx /bin/sh` on container 1.6.1.
    private let realSession = "# ls -la /etc | head -4\r\r\ntotal 276\r\r\ndrwxr-xr-x 33 root root    4096 Nov  2 18:32 .\r\r\ndrwxr-xr-x 19 root root    4096 Nov  2 17:51 ..\r\r\n-rw-------  1 root root       0 Oct 27 00:00 .pwd.lock\r\r\n# printf '\\033[1;31mred\\033[0m plain \\033[32mgreen\\033[0m\\n'\r\r\n\u{1B}[1;31mred\u{1B}[0m plain \u{1B}[32mgreen\u{1B}[0m\r\r\n# echo abc\u{08} \u{08}\u{08} \u{08}xyz\r\r\naxyz\r\r\n# exit\r\r\n\u{1B}[?25l\u{1B}[?25h"

    func testRealShellSessionRendersCleanly() {
        var screen = TerminalScreen(columns: 80, rows: 24)
        screen.feed(realSession)
        let lines = screen.text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "# ls -la /etc | head -4")
        XCTAssertEqual(lines[1], "total 276")
        XCTAssertEqual(lines[6], "red plain green", "colour codes are not printed")
        XCTAssertEqual(lines[7], "# echo axyz", "backspace-erase is applied")
        XCTAssertEqual(lines[8], "axyz")
        XCTAssertFalse(screen.text.contains("\u{1B}"))
        XCTAssertEqual(screen.grid[6][0].style.foreground, .indexed(1))
        XCTAssertTrue(screen.grid[6][0].style.bold)
        XCTAssertEqual(screen.grid[6][10].style.foreground, .indexed(2))
    }

    func testCarriageReturnOverwritesLikeAProgressBar() {
        var screen = TerminalScreen(columns: 40, rows: 5)
        screen.feed("Downloading 10%\rDownloading 55%\rDone\u{1B}[K\r\n$ ")
        XCTAssertEqual(screen.text, "Done\n$")
        XCTAssertEqual(screen.cursorRow, 1)
        XCTAssertEqual(screen.cursorColumn, 2)
    }

    func testCursorPositioningAndEraseDisplay() {
        var screen = TerminalScreen(columns: 20, rows: 4)
        screen.feed("aaaa\r\nbbbb\r\ncccc")
        screen.feed("\u{1B}[2;3HX")          // row 2, column 3
        XCTAssertEqual(screen.text, "aaaa\nbbXb\ncccc")
        screen.feed("\u{1B}[H\u{1B}[2J$ ")     // `clear`
        XCTAssertTrue(screen.grid[0].starts(with: [TerminalScreen.Cell(character: "$", style: .init())]))
        XCTAssertEqual(screen.scrollback.count, 3, "cleared screen goes to scrollback like xterm")
    }

    func testLineWrapAndScrollIntoScrollback() {
        var screen = TerminalScreen(columns: 5, rows: 2)
        screen.feed("12345678\r\nnext\r\nlast")
        XCTAssertEqual(screen.text, "12345\n678\nnext\nlast")
        XCTAssertEqual(screen.scrollback.count, 2)
    }

    func testAlternateScreenRestoresShell() {
        var screen = TerminalScreen(columns: 20, rows: 3)
        screen.feed("$ vi file\r\n")
        screen.feed("\u{1B}[?1049h\u{1B}[H\u{1B}[2Jfull screen app")
        XCTAssertTrue(screen.isAlternateScreen)
        XCTAssertEqual(screen.text, "full screen app")
        screen.feed("\u{1B}[?1049l")
        XCTAssertFalse(screen.isAlternateScreen)
        XCTAssertEqual(screen.text, "$ vi file")
    }

    func testEraseLineInsertDeleteAndTitleSequences() {
        var screen = TerminalScreen(columns: 20, rows: 3)
        screen.feed("\u{1B}]0;nginx: /etc\u{07}hello world")
        XCTAssertEqual(screen.text, "hello world", "OSC window title is not printed")
        screen.feed("\u{1B}[6D\u{1B}[K")
        XCTAssertEqual(screen.text, "hello")
        screen.feed("\u{1B}[1G\u{1B}[2P")
        XCTAssertEqual(screen.text, "llo")
        screen.feed("\u{1B}[2@ab")
        XCTAssertEqual(screen.text, "abllo")
    }

    func testColourVariantsAndCursorReport() {
        var screen = TerminalScreen(columns: 20, rows: 3)
        screen.feed("\u{1B}[38;5;208mo\u{1B}[38;2;1;2;3mt\u{1B}[0m\u{1B}[6n")
        XCTAssertEqual(screen.grid[0][0].style.foreground, .indexed(208))
        XCTAssertEqual(screen.grid[0][1].style.foreground, .rgb(1, 2, 3))
        XCTAssertEqual(screen.takeReplies(), ["\u{1B}[1;3R"])
        XCTAssertTrue(screen.takeReplies().isEmpty)
    }

    func testResizeKeepsContentAndCursor() {
        var screen = TerminalScreen(columns: 10, rows: 4)
        screen.feed("a\r\nb\r\nc\r\nd")
        screen.resize(columns: 20, rows: 2)
        XCTAssertEqual(screen.rows, 2)
        XCTAssertEqual(screen.text, "a\nb\nc\nd")
        XCTAssertEqual(screen.cursorRow, 1)
    }

    func testRendererProducesNoEscapeCodesAndMarksCursor() {
        var screen = TerminalScreen(columns: 20, rows: 3)
        screen.feed("\u{1B}[1;32mok\u{1B}[0m $ ")
        let rendered = TerminalScreenRenderer.render(screen, showCursor: true)
        XCTAssertEqual(rendered.string, "ok $  ")
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: rendered.length - 1, effectiveRange: nil), "cursor cell is highlighted")
    }

    func testKeyEncodingForCommonKeys() throws {
        func key(_ code: UInt16, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> String? {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            return InteractivePTYCanvasRepresentable.PTYKeyCapturingTextView.sequence(for: e)
        }
        XCTAssertEqual(key(36, "\r"), "\r")
        XCTAssertEqual(key(51), "\u{7F}")
        XCTAssertEqual(key(126), "\u{1B}[A")
        XCTAssertEqual(key(8, "c", .control), "\u{03}")
        XCTAssertEqual(key(2, "d", .control), "\u{04}")
        XCTAssertEqual(key(0, "a"), "a")
        XCTAssertNil(key(8, "c", .command), "⌘C stays with the view (copy)")
    }
}
