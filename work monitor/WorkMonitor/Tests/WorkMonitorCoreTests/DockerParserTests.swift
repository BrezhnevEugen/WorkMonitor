import XCTest
import WorkMonitorCore

final class DockerParserTests: XCTestCase {
    func testParsesDockerPsFormatLine() {
        let line = "ab12cd|web|nginx:latest|Up 2 hours|running|0.0.0.0:80->80/tcp"
        let result = DockerPsOutputParser.parseCommandOutput(line)
        XCTAssertTrue(result.available)
        XCTAssertEqual(result.containers.count, 1)
        let c = result.containers[0]
        XCTAssertEqual(c.id, "ab12cd")
        XCTAssertEqual(c.name, "web")
        XCTAssertEqual(c.image, "nginx:latest")
        XCTAssertEqual(c.state, .running)
        XCTAssertEqual(c.ports, "0.0.0.0:80->80/tcp")
    }

    func testCannotConnectMarksUnavailable() {
        let out = "Cannot connect to the Docker daemon at unix:///var/run/docker.sock"
        let result = DockerPsOutputParser.parseCommandOutput(out)
        XCTAssertTrue(result.containers.isEmpty)
        XCTAssertFalse(result.available)
    }

    func testExitedState() {
        let line = "x1|c|img:1|Exited (1) 1h ago|exited|"
        let result = DockerPsOutputParser.parseCommandOutput(line)
        XCTAssertEqual(result.containers.first?.state, .exited)
    }
}
