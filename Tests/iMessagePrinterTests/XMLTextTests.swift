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

    func testSegmentsTurnNewlinesAndTabsIntoRunMarkers() {
        XCTAssertEqual(
            XMLText.segments("line 1\nline 2\tend"),
            [.text("line 1"), .lineBreak, .text("line 2"), .tab, .text("end")]
        )
    }

    func testSegmentsPreserveEmojiAndAmpersands() {
        XCTAssertEqual(XMLText.segments("❤️ & more"), [.text("❤️ &amp; more")])
    }

    func testSegmentsHandleCarriageReturnNewline() {
        XCTAssertEqual(XMLText.segments("a\r\nb"), [.text("a"), .lineBreak, .text("b")])
    }
}
