import Foundation
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var containers: [DockerContainer] = []
    @Published var memory: MemoryInfo = MemoryInfo(
        totalGB: 0, usedGB: 0, freeGB: 0,
        swapUsedGB: 0, swapTotalGB: 0,
        pressure: .nominal,
        appMemoryGB: 0, wiredGB: 0, compressedGB: 0
    )
    @Published var dockerAvailable: Bool = true
    @Published var topProcesses: [ProcessMemoryInfo] = []
    @Published var lastUpdated: Date = Date()
    @Published var isLoading: Bool = false

    func refresh() {
        isLoading = true
        Task {
            async let p = Self.fetchPorts()
            async let d = Self.fetchDockerContainers()
            async let m = Self.fetchMemory()
            async let t = Self.fetchTopProcesses()

            var (newPorts, dockerResult, newMemory, newTop) = await (p, d, m, t)

            // Probe ports for web UIs (quick parallel HTTP checks)
            newPorts = await Self.probeWebUIs(ports: newPorts)

            self.ports = newPorts
            self.containers = dockerResult.containers
            self.dockerAvailable = dockerResult.available
            self.memory = newMemory
            self.topProcesses = newTop
            self.lastUpdated = Date()
            self.isLoading = false
        }
    }

    // MARK: - Ports via lsof

    private static func fetchPorts() async -> [PortInfo] {
        // Use /bin/sh to run lsof — avoids PATH and permission issues in .app bundle
        let output = await shell("/bin/sh", args: ["-c", "lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null"])
        var results: [PortInfo] = []
        var seen = Set<String>()

        let lines = output.split(separator: "\n")
        for line in lines.dropFirst() { // skip header "COMMAND PID USER ..."
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            // lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME (STATE)
            // Minimum 9 cols, but NAME is second-to-last when (LISTEN) is present
            guard cols.count >= 9 else { continue }

            let processName = String(cols[0])
            let pid = Int(String(cols[1])) ?? 0

            // The TYPE column (index 4) tells us IPv4/IPv6
            let typeField = String(cols[4])
            let proto = typeField == "IPv6" ? "tcp6" : "tcp4"

            // NAME is the address:port field.
            // If last col is "(LISTEN)", NAME is second-to-last; otherwise NAME is last.
            let lastCol = String(cols[cols.count - 1])
            let nameField: String
            if lastCol.hasPrefix("(") {
                // e.g. "(LISTEN)" — NAME is one before
                guard cols.count >= 10 else { continue }
                nameField = String(cols[cols.count - 2])
            } else {
                nameField = lastCol
            }

            // Parse address:port — handle IPv6 like [::1]:3000 and IPv4 like 127.0.0.1:3000
            guard let lastColon = nameField.lastIndex(of: ":") else { continue }
            let address = String(nameField[nameField.startIndex..<lastColon])
            let portStr = String(nameField[nameField.index(after: lastColon)...])
            guard let port = Int(portStr) else { continue }

            let key = "\(port)-\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            results.append(PortInfo(
                port: port, pid: pid,
                processName: processName,
                address: address,
                proto: proto
            ))
        }

        return results.sorted { $0.port < $1.port }
    }

    // MARK: - Docker

    private static func fetchDockerContainers() async -> (containers: [DockerContainer], available: Bool) {
        // Try to find docker
        let dockerPath = await findDocker()
        guard let path = dockerPath else {
            return ([], false)
        }

        let output = await shell(path, args: [
            "ps", "-a",
            "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}|{{.Ports}}"
        ])

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           output.contains("Cannot connect") || output.contains("error") {
            return ([], output.contains("Cannot connect") ? false : true)
        }

        var containers: [DockerContainer] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { continue }

            let stateStr = parts[4].lowercased()
            let state: DockerContainer.ContainerState = switch stateStr {
                case "running": .running
                case "exited": .exited
                case "paused": .paused
                case "restarting": .restarting
                default: .other
            }

            containers.append(DockerContainer(
                id: parts[0],
                name: parts[1],
                image: parts[2],
                status: parts[3],
                state: state,
                ports: parts.count > 5 ? parts[5] : ""
            ))
        }

        return (containers, true)
    }

    private static func findDocker() async -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try `which docker`
        let which = await shell("/usr/bin/which", args: ["docker"])
        let trimmed = which.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    // MARK: - Memory via vm_stat + sysctl

    private static func fetchMemory() async -> MemoryInfo {
        // Run all commands through /bin/sh to inherit proper PATH
        let vmOutput = await shell("/bin/sh", args: ["-c", "vm_stat 2>/dev/null"])
        let sysctlOutput = await shell("/bin/sh", args: ["-c", "sysctl -n hw.memsize 2>/dev/null"])

        // Parse page size from vm_stat header: "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
        var pageSize: Double = 16384
        if let firstLine = vmOutput.split(separator: "\n").first {
            let header = String(firstLine)
            if let range = header.range(of: #"page size of (\d+)"#, options: .regularExpression) {
                let match = header[range]
                let digits = match.replacingOccurrences(of: "page size of ", with: "")
                pageSize = Double(digits) ?? 16384
            }
        }

        var pages: [String: Double] = [:]
        for line in vmOutput.split(separator: "\n").dropFirst() { // skip header
            let str = String(line)
            if let colonIdx = str.firstIndex(of: ":") {
                let key = String(str[str.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let valStr = String(str[str.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ".", with: "")
                if let val = Double(valStr) {
                    pages[key] = val
                }
            }
        }

        // Total RAM from sysctl — `sysctl -n` gives just the number
        let totalBytes = Double(sysctlOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let totalGB = totalBytes / 1_073_741_824

        let freePages = pages["Pages free"] ?? 0
        let activePages = pages["Pages active"] ?? 0
        let inactivePages = pages["Pages inactive"] ?? 0
        let wiredPages = pages["Pages wired down"] ?? 0
        let compressedPages = pages["Pages occupied by compressor"] ?? 0
        let speculativePages = pages["Pages speculative"] ?? 0
        let purgablePages = pages["Pages purgeable"] ?? 0

        let wiredGB = (wiredPages * pageSize) / 1_073_741_824
        let compressedGB = (compressedPages * pageSize) / 1_073_741_824
        let appGB = ((activePages + inactivePages) * pageSize) / 1_073_741_824
        let freeGB = ((freePages + speculativePages + purgablePages) * pageSize) / 1_073_741_824
        let usedGB = totalGB - freeGB

        // Swap
        let swapOutput = await shell("/bin/sh", args: ["-c", "sysctl vm.swapusage 2>/dev/null"])
        var swapTotal: Double = 0
        var swapUsed: Double = 0

        // Format: "vm.swapusage: total = 2048.00M  used = 1024.00M  free = 1024.00M  (encrypted)"
        // Parse by splitting on "=" and extracting M-values
        let swapParts = swapOutput.components(separatedBy: "=")
        // swapParts[0] = "vm.swapusage: total ", [1] = " 2048.00M  used ", [2] = " 1024.00M  free ", ...
        for (i, part) in swapParts.enumerated() {
            guard i > 0 else { continue }
            let cleaned = part.trimmingCharacters(in: .whitespaces)
            // Extract the number before "M"
            if let mIdx = cleaned.firstIndex(of: "M") {
                let numStr = String(cleaned[cleaned.startIndex..<mIdx])
                let valueMB = Double(numStr) ?? 0
                let prevPart = swapParts[i - 1].lowercased()
                if prevPart.contains("total") {
                    swapTotal = valueMB / 1024
                } else if prevPart.contains("used") {
                    swapUsed = valueMB / 1024
                }
            }
        }

        // Memory pressure
        let pressureOutput = await shell("/bin/sh", args: ["-c", "memory_pressure 2>/dev/null || echo NOMINAL"])
        let pressure: MemoryInfo.MemoryPressure
        if pressureOutput.contains("CRITICAL") {
            pressure = .critical
        } else if pressureOutput.contains("WARN") {
            pressure = .warn
        } else {
            pressure = .nominal
        }

        return MemoryInfo(
            totalGB: totalGB,
            usedGB: usedGB,
            freeGB: freeGB,
            swapUsedGB: swapUsed,
            swapTotalGB: swapTotal,
            pressure: pressure,
            appMemoryGB: appGB,
            wiredGB: wiredGB,
            compressedGB: compressedGB
        )
    }

    // MARK: - Top processes by memory

    // System users on macOS — processes owned by these cannot be killed
    private static let systemUsers: Set<String> = [
        "root", "_windowserver", "_coreaudiod", "_locationd",
        "_displaypolicyd", "_distnoted", "_nsurlsessiond",
        "_mdnsresponder", "_timed", "_networkd", "_appleevents",
        "_cmiodalassistants", "_spotlight", "nobody", "_securityagent",
        "_coreml", "_trustd", "_analyticsd", "_fpsd"
    ]

    // System process names — matched by prefix
    private static let systemProcessPrefixes: [String] = [
        "com.apple.", "kernel_task", "launchd", "WindowServer",
        "mds", "logd", "watchdog", "corespeech", "airportd",
        "bluetoothd", "UserEventAgent", "syslogd", "configd",
        "coreauthd", "opendirectoryd", "securityd"
    ]

    private static func fetchTopProcesses() async -> [ProcessMemoryInfo] {
        // Get total RAM for percentage calculation
        let memStr = await shell("/bin/sh", args: ["-c", "sysctl -n hw.memsize 2>/dev/null"])
        let totalBytes = Double(memStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let totalMB = totalBytes / 1_048_576

        // Sort by RSS descending in shell, take top 50 — keeps parsing fast
        let output = await shell("/bin/sh", args: ["-c", "ps -Axo user=,pid=,rss=,comm= 2>/dev/null | sort -k3 -nr | head -50"])
        var results: [ProcessMemoryInfo] = []

        for line in output.split(separator: "\n") {
            let cols = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard cols.count >= 4 else { continue }

            let user = String(cols[0])
            guard let pid = Int(String(cols[1])) else { continue }
            guard let rssKB = Double(String(cols[2])) else { continue }
            let memMB = rssKB / 1024

            guard memMB >= 10 else { continue }

            let memPercent = totalMB > 0 ? (memMB / totalMB) * 100 : 0

            let fullPath = String(cols[3])
            let name: String
            if let lastSlash = fullPath.lastIndex(of: "/") {
                name = String(fullPath[fullPath.index(after: lastSlash)...])
            } else {
                name = fullPath
            }

            // Determine if system process
            let isSystem = systemUsers.contains(user)
                || user.hasPrefix("_")
                || systemProcessPrefixes.contains(where: { name.hasPrefix($0) || fullPath.contains("/usr/libexec/") || fullPath.contains("/usr/sbin/") })

            results.append(ProcessMemoryInfo(
                pid: pid,
                name: name,
                memoryMB: memMB,
                memoryPercent: memPercent,
                isSystem: isSystem
            ))
        }

        // Sort by memory descending
        let sorted = results.sorted { $0.memoryMB > $1.memoryMB }

        // Take top system + top user separately to get good coverage
        let topSystem = Array(sorted.filter { $0.isSystem }.prefix(10))
        let topUser = Array(sorted.filter { !$0.isSystem }.prefix(15))

        return (topSystem + topUser).sorted { $0.memoryMB > $1.memoryMB }
    }

    // MARK: - Web UI probe

    private static func probeWebUIs(ports: [PortInfo]) async -> [PortInfo] {
        // Check all ports in parallel with a short timeout
        await withTaskGroup(of: (Int, Bool, String?).self) { group in
            for (index, port) in ports.enumerated() {
                group.addTask {
                    let result = await Self.probePort(port.port)
                    return (index, result.isWeb, result.title)
                }
            }

            var updated = ports
            for await (index, isWeb, title) in group {
                updated[index].hasWebUI = isWeb
                updated[index].webTitle = title
            }
            return updated
        }
    }

    private static func probePort(_ port: Int) async -> (isWeb: Bool, title: String?) {
        guard let url = URL(string: "http://localhost:\(port)") else {
            return (false, nil)
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return (false, nil) }

            // Any HTTP response means it's a web service
            let statusCode = httpResponse.statusCode
            guard (100...599).contains(statusCode) else { return (false, nil) }

            // Try to extract <title> from HTML
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            var title: String? = nil

            if contentType.contains("text/html") || contentType.contains("application/xhtml") {
                let html = String(data: data.prefix(4096), encoding: .utf8) ?? ""
                if let titleStart = html.range(of: "<title>", options: .caseInsensitive),
                   let titleEnd = html.range(of: "</title>", options: .caseInsensitive),
                   titleStart.upperBound < titleEnd.lowerBound {
                    title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if title?.isEmpty == true { title = nil }
                }
            }

            return (true, title)
        } catch {
            return (false, nil)
        }
    }

    // MARK: - Shell helper

    private static func shell(_ command: String, args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
