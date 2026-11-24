import XCTest
@testable import iMessagePrinter

final class XMLTextTests: XCTestCase {
    func testEscapesMarkupCharacters() {
        XCTAssertEqual(
            XMLText.escape("a & b < c > d \"e\" 'f'"),
            "a &amp; b &lt; c &gt; d &quot;e&quot; 'f'"
        )
    }

    func testStripsInvalidControlCharacters() {
        let input = "a\u{0000}b\u{0008}c\u{000B}d\u{001F}e"
        XCTAssertEqual(XMLText.escape(input), "abcde")
    }

    func testRunsTurnNewlinesAndTabsIntoWordMarkup() {
        XCTAssertEqual(
            XMLText.runs("line 1\nline 2\tend"),
            "line 1<w:br/>line 2<w:tab/>end"
        )
    }

    func testRunsPreserveEmojiAndAmpersands() {
        XCTAssertEqual(XMLText.runs("❤️ & more"), "❤️ &amp; more")
    }

    func testRunsHandleCarriageReturnNewline() {
        XCTAssertEqual(XMLText.runs("a\r\nb"), "a<w:br/>b")
    }
}
