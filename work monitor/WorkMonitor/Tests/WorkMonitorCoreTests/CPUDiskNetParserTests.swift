import XCTest
import WorkMonitorCore

final class CPUDiskNetParserTests: XCTestCase {

    // MARK: - CPU

    func testParseCPUStandardMacOSHeader() {
        let sample = """
        Processes: 521 total, 2 running, 519 sleeping, 2812 threads
        2026/04/18 12:34:56
        Load Avg: 2.01, 2.45, 2.30
        CPU usage: 12.34% user, 5.66% sys, 82.00% idle
        """
        let cpu = TopCPUOutputParser.parseCPU(sample)
        XCTAssertEqual(cpu.userPercent, 12.34, accuracy: 0.01)
        XCTAssertEqual(cpu.systemPercent, 5.66, accuracy: 0.01)
        XCTAssertEqual(cpu.idlePercent, 82.00, accuracy: 0.01)
        XCTAssertEqual(cpu.percent, 18.00, accuracy: 0.01)
    }

    func testParseCPUFallsBackToZeroOnMissingLine() {
        let cpu = TopCPUOutputParser.parseCPU("unrelated output\nno cpu line here")
        XCTAssertEqual(cpu.percent, 0)
        XCTAssertEqual(cpu.idlePercent, 100)
    }

    // MARK: - Disk

    func testParseDfRoot() {
        // Format: Filesystem  1K-blocks  Used        Available   Capacity  iused  ifree  %iused  Mounted on
        let sample = """
        Filesystem    1024-blocks       Used Available Capacity iused     ifree %iused  Mounted on
        /dev/disk3s1s1 971350180  12000000 500000000      3%  500000 5000000000   0%   /
        """
        let disk = DfOutputParser.parseRoot(sample)
        // 971_350_180 KB ≈ 926.34 GiB
        XCTAssertEqual(disk.totalGB, 971_350_180.0 / (1024 * 1024), accuracy: 0.01)
        XCTAssertEqual(disk.freeGB,  500_000_000.0 / (1024 * 1024), accuracy: 0.01)
        XCTAssertTrue(disk.usedGB > 0)
        XCTAssertTrue(disk.usagePercent > 0 && disk.usagePercent < 100)
    }

    func testParseDfEmptyReturnsZero() {
        let disk = DfOutputParser.parseRoot("")
        XCTAssertEqual(disk, .zero)
    }

    // MARK: - Network

    func testParseNetstatAggregatesAcrossInterfaces() {
        // Real-ish macOS `netstat -ibn` header + rows. First row per iface has aggregate totals.
        // Columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        let sample = """
        Name  Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0   16384 <Link#1>                         100       0      10000    100       0      10000     0
        lo0   16384 127           localhost          50        0       5000     50       0       5000     0
        en0   1500  <Link#4>      a4:83:e7:00:00:00  1000      0    5000000    500       0    2000000     0
        en0   1500  192.168.1     192.168.1.42       900       0    4000000    450       0    1500000     0
        en1   1500  <Link#5>      a4:83:e7:00:00:01   100      0     200000     50       0      50000     0
        """
        let totals = NetstatOutputParser.parseTotals(sample)
        XCTAssertEqual(totals.inBytes, 5_000_000 + 200_000)   // first-row-per-iface, lo* excluded
        XCTAssertEqual(totals.outBytes, 2_000_000 + 50_000)
    }

    func testParseNetstatSkipsLoopback() {
        let sample = """
        Name  Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
        lo0   16384 <Link#1>                         100       0      10000    100       0      10000     0
        """
        let totals = NetstatOutputParser.parseTotals(sample)
        XCTAssertEqual(totals.inBytes, 0)
        XCTAssertEqual(totals.outBytes, 0)
    }
}
