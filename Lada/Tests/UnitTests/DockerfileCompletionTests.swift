import XCTest
import AppKit
@testable import Lada

final class DockerfileCompletionTests: XCTestCase {
    private func complete(_ line: String, previous: String? = nil, doc: String? = nil, images: [String] = []) -> [String] {
        DockerfileCompletionEngine.suggestions(lineBeforeCursor: line, previousLine: previous, document: doc ?? line, localImages: images, catalog: DockerHubService.curatedCatalog)
    }

    func testInstructionsAtLineStartAreCaseInsensitive() {
        XCTAssertEqual(complete("WO"), ["WORKDIR"])
        XCTAssertEqual(complete("ex"), ["EXPOSE"])
        XCTAssertTrue(complete("").contains("FROM"))
    }

    func testNoInstructionsInsideAContinuedShellCommand() {
        XCTAssertEqual(complete("    ap", previous: "RUN apt-get update && \\"), [])
    }

    func testFromSuggestsLocalImagesShortenedAndThenAS() {
        let s = complete("FROM ngi", images: ["docker.io/library/nginx:1.27-alpine"])
        XCTAssertEqual(s.first, "nginx:1.27-alpine")
        XCTAssertEqual(complete("FROM nginx:1.27 a"), ["AS"])
        XCTAssertTrue(complete("FROM --pl").contains("--platform=linux/arm64"))
    }

    func testCopyFromOffersStagesDefinedEarlier() {
        let doc = "FROM golang:1.23 AS builder\nRUN go build\nFROM alpine\nCOPY --fr"
        XCTAssertEqual(complete("COPY --fr", doc: doc).first, "--from=builder")
    }

    func testVariablesFromArgAndEnv() {
        let doc = "ARG VERSION=1\nENV APP_HOME=/app PORT=8080\nRUN echo ${AP"
        XCTAssertEqual(complete("RUN echo ${AP", doc: doc), ["${APP_HOME}"])
        XCTAssertTrue(complete("WORKDIR \"/x/$VE", doc: doc).contains("$VERSION"))
    }

    func testArgumentsForCommonInstructions() {
        XCTAssertTrue(complete("EXPOSE 54").contains("5432/tcp"))
        XCTAssertTrue(complete("HEALTHCHECK --int").contains("--interval=30s"))
        XCTAssertTrue(complete("STOPSIGNAL SIGT").contains("SIGTERM"))
        XCTAssertTrue(complete("WORKDIR /u", doc: "WORKDIR /usr/local/app\nWORKDIR /u").first == "/usr/local/app")
    }

    func testExactMatchIsNotSuggested() {
        XCTAssertEqual(complete("FROM"), [])
    }

    func testTokenStartFollowsTheEngineRules() {
        XCTAssertEqual(DockerfileCompletionEngine.tokenStart(in: "COPY --from=bu"), 5)
        XCTAssertEqual(DockerfileCompletionEngine.tokenStart(in: "RUN echo \"/a/${VE"), 13)
        XCTAssertEqual(DockerfileCompletionEngine.tokenStart(in: "FR"), 0)
        XCTAssertEqual(DockerfileCompletionEngine.tokenStart(in: "FROM "), 5)
    }
}

@MainActor
final class DockerfileEditorViewTests: XCTestCase {
    func testCompletionRangeCoversFlagsAndVariables() {
        let tv = DockerfileNSTextView()
        tv.string = "FROM alpine\nCOPY --from=bu"
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        XCTAssertEqual((tv.string as NSString).substring(with: tv.rangeForUserCompletion), "--from=bu")
    }

    /// Colours come from the view's own appearance, not the app's, and dark text is bright.
    func testSyntaxPalettePerAppearance() throws {
        let dark = NordicSyntax.palette(for: try XCTUnwrap(NSAppearance(named: .darkAqua)))
        let light = NordicSyntax.palette(for: try XCTUnwrap(NSAppearance(named: .aqua)))
        XCTAssertGreaterThan(try XCTUnwrap(dark.text.usingColorSpace(.sRGB)).brightnessComponent, 0.9)
        XCTAssertLessThan(try XCTUnwrap(light.text.usingColorSpace(.sRGB)).brightnessComponent, 0.15)

        let tv = DockerfileNSTextView()
        tv.appearance = NSAppearance(named: .darkAqua)
        tv.string = "FROM alpine"
        let coordinator = DockerfileCodeEditorRepresentable.Coordinator(
            DockerfileCodeEditorRepresentable(text: .constant(""), cursorLine: .constant(1), currentWordPrefix: .constant(""), pendingInsertion: .constant(nil))
        )
        coordinator.applySyntaxHighlighting(to: tv)
        let keywordColor = tv.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(keywordColor, dark.keyword)
    }
}

final class DockerfileDocsTests: XCTestCase {
    func testEveryInstructionHasAReference() {
        for instruction in DockerfileCompletionEngine.instructions {
            let doc = DockerfileDocs.doc(for: instruction, lineBeforeCursor: "")
            XCTAssertEqual(doc?.instruction, instruction)
            XCTAssertFalse(doc?.syntax.isEmpty ?? true, instruction)
            XCTAssertFalse(doc?.example.isEmpty ?? true, instruction)
            XCTAssertNil(doc?.highlighted, "an instruction's own page highlights nothing")
        }
    }

    func testFlagsHighlightTheirParameter() {
        XCTAssertEqual(DockerfileDocs.doc(for: "--mount=type=cache,target=", lineBeforeCursor: "RUN ")?.highlighted, "--mount=type=cache,target=<path>")
        XCTAssertEqual(DockerfileDocs.doc(for: "--from=builder", lineBeforeCursor: "COPY ")?.highlighted, "--from=<stage|image>")
        XCTAssertEqual(DockerfileDocs.doc(for: "--interval=30s", lineBeforeCursor: "HEALTHCHECK ")?.highlighted, "--interval=<duration>")
    }

    func testValuesHighlightOnlyWhenTheyMatch() {
        XCTAssertEqual(DockerfileDocs.doc(for: "SIGQUIT", lineBeforeCursor: "STOPSIGNAL ")?.highlighted, "SIGQUIT")
        XCTAssertEqual(DockerfileDocs.doc(for: "TARGETARCH", lineBeforeCursor: "ARG ")?.highlighted, "TARGETPLATFORM, TARGETOS, TARGETARCH")
        // An image after FROM shows FROM's page without a wrong highlight.
        let from = DockerfileDocs.doc(for: "nginx:1.27-alpine", lineBeforeCursor: "FROM ")
        XCTAssertEqual(from?.instruction, "FROM")
        XCTAssertNil(from?.highlighted)
        XCTAssertNil(DockerfileDocs.doc(for: "x", lineBeforeCursor: "echo "))
    }
}

@MainActor
final class InfoTipTests: XCTestCase {
    func testCardHeightGrowsWithText() {
        let short = InfoTipPresenter.height(title: nil, text: "Short.")
        let long = InfoTipPresenter.height(title: "Title", text: String(repeating: "A longer explanation that wraps. ", count: 8))
        XCTAssertGreaterThan(long, short)
        XCTAssertGreaterThan(short, 28)
    }
}
