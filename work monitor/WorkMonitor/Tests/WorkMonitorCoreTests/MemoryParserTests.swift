import XCTest
import WorkMonitorCore

final class MemoryParserTests: XCTestCase {
    func testParsePressure() {
        XCTAssertEqual(MemoryOutputParser.parsePressureOutput("system WARN level"), .warn)
        XCTAssertEqual(MemoryOutputParser.parsePressureOutput("CRITICAL"), .critical)
        XCTAssertEqual(MemoryOutputParser.parsePressureOutput("NOMINAL"), .nominal)
    }

    func testParseSwapUsage() {
        let swapText = "vm.swapusage: total = 4096.00M  used = 512.00M  free = 3584.00M  (encrypted)"
        let s = MemoryOutputParser.parseSwapUsage(swapText)
        XCTAssertEqual(s.totalGB, 4.0, accuracy: 0.001)
        XCTAssertEqual(s.usedGB, 0.5, accuracy: 0.001)
    }

    func testBuildMemoryInfoMinimal() {
        let vm = """
        Mach Virtual Memory Statistics: (page size of 4096 bytes)
        Pages free:                        1000.
        Pages active:                      2000.
        Pages inactive:                    500.
        Pages speculative:                  0.
        Pages wired down:                  300.
        Pages purgeable:                    0.
        Pages occupied by compressor:     100.
        """
        let hw = String(4 * 1_073_741_824) // 4 GiB in bytes
        let swap = "vm.swapusage: total = 0.00M  used = 0.00M  free = 0.00M"
        let mem = MemoryOutputParser.buildMemoryInfo(
            vmOutput: vm,
            sysctlHwMemsize: hw,
            swapOutput: swap,
            pressureOutput: "NOMINAL"
        )
        XCTAssertEqual(mem.totalGB, 4.0, accuracy: 0.02)
        XCTAssertEqual(mem.pressure, .nominal)
        XCTAssertGreaterThan(mem.usedGB, 0)
        XCTAssertGreaterThan(mem.wiredGB, 0)
        XCTAssertGreaterThan(mem.compressedGB, 0)
    }

    func testUsagePercent() {
        let m = MemoryInfo(
            totalGB: 100,
            usedGB: 25,
            freeGB: 75,
            swapUsedGB: 0,
            swapTotalGB: 0,
            pressure: .nominal,
            appMemoryGB: 10,
            wiredGB: 5,
            compressedGB: 2
        )
        XCTAssertEqual(m.usagePercent, 25.0, accuracy: 0.001)
    }
}
