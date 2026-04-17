import XCTest
import WorkMonitorCore

final class HTMLTitleParserTests: XCTestCase {
    func testExtractsTitleCaseInsensitive() {
        let html = "<HTML><HEAD><TITLE>My App</TITLE></HEAD><body></body>"
        XCTAssertEqual(HTMLTitleParser.extractTitle(fromHTML: html), "My App")
    }

    func testReturnsNilWhenMissing() {
        XCTAssertNil(HTMLTitleParser.extractTitle(fromHTML: "<html></html>"))
    }

    func testTrimsWhitespace() {
        let html = "<title>  spaced  </title>"
        XCTAssertEqual(HTMLTitleParser.extractTitle(fromHTML: html), "spaced")
    }
}
