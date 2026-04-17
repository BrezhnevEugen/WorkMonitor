import XCTest
import WorkMonitorCore

final class LsofParserTests: XCTestCase {
    func testParsesIPv4ListenWithListenSuffix() {
        let output = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node    12345 user   21u  IPv4 0x1234567890      0t0  TCP 127.0.0.1:3000 (LISTEN)
        """
        let ports = LsofListenOutputParser.parseListenOutput(output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[0].pid, 12345)
        XCTAssertEqual(ports[0].processName, "node")
        XCTAssertEqual(ports[0].address, "127.0.0.1")
        XCTAssertEqual(ports[0].proto, "tcp4")
    }

    func testParsesIPv6BracketAddress() {
        let output = """
        COMMAND PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        nginx 999 user   6u  IPv6 0xabc  0t0  TCP [::1]:8080 (LISTEN)
        """
        let ports = LsofListenOutputParser.parseListenOutput(output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 8080)
        XCTAssertEqual(ports[0].address, "[::1]")
        XCTAssertEqual(ports[0].proto, "tcp6")
    }

    func testDeduplicatesSamePortAndPid() {
        let output = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        app 1 u 1u IPv4 0 0t0 TCP *:4000 (LISTEN)
        app 1 u 2u IPv4 0 0t0 TCP *:4000 (LISTEN)
        """
        let ports = LsofListenOutputParser.parseListenOutput(output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].port, 4000)
    }

    func testSortsByPort() {
        let output = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        b 1 u 1u IPv4 0 0t0 TCP 127.0.0.1:9000 (LISTEN)
        a 1 u 1u IPv4 0 0t0 TCP 127.0.0.1:80 (LISTEN)
        """
        let ports = LsofListenOutputParser.parseListenOutput(output)
        XCTAssertEqual(ports.map(\.port), [80, 9000])
    }
}
