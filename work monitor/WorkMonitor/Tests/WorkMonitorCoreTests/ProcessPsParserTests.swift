import XCTest
import WorkMonitorCore

final class ProcessPsParserTests: XCTestCase {
    func testParsesUserProcess() {
        let output = "eugen  1000  204800  /Applications/Foo.app/Contents/MacOS/Foo"
        let totalBytes = 16.0 * 1_073_741_824
        let list = ProcessPsOutputParser.parseTopProcesses(output: output, hwMemsizeBytes: totalBytes)
        XCTAssertFalse(list.isEmpty)
        let p = list.first { $0.pid == 1000 }
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.name, "Foo")
        XCTAssertFalse(p?.isSystem ?? true)
        if let mem = p?.memoryMB {
            XCTAssertEqual(mem, 200, accuracy: 0.01)
        } else {
            XCTFail("expected memoryMB")
        }
    }

    func testRootMarkedSystem() {
        let output = "root  1  10240  /sbin/launchd"
        let totalBytes = 8.0 * 1_073_741_824
        let list = ProcessPsOutputParser.parseTopProcesses(output: output, hwMemsizeBytes: totalBytes)
        let p = list.first { $0.pid == 1 }
        XCTAssertNotNil(p)
        XCTAssertTrue(p?.isSystem ?? false)
    }

    func testSkipsSmallRss() {
        let output = "eugen 2 8192 /usr/bin/small"
        let list = ProcessPsOutputParser.parseTopProcesses(output: output, hwMemsizeBytes: 8 * 1_073_741_824)
        XCTAssertTrue(list.isEmpty)
    }
}
