import Foundation

// MARK: - lsof LISTEN

public enum LsofListenOutputParser {
    /// Parses `lsof -iTCP -sTCP:LISTEN -nP` stdout (including header line).
    public static func parseListenOutput(_ output: String) -> [PortInfo] {
        var results: [PortInfo] = []
        var seen = Set<String>()
        let lines = output.split(separator: "\n")
        for line in lines.dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }

            let processName = String(cols[0])
            let pid = Int(String(cols[1])) ?? 0

            let typeField = String(cols[4])
            let proto = typeField == "IPv6" ? "tcp6" : "tcp4"

            let lastCol = String(cols[cols.count - 1])
            let nameField: String
            if lastCol.hasPrefix("(") {
                guard cols.count >= 10 else { continue }
                nameField = String(cols[cols.count - 2])
            } else {
                nameField = lastCol
            }

            guard let lastColon = nameField.lastIndex(of: ":") else { continue }
            let address = String(nameField[nameField.startIndex..<lastColon])
            let portStr = String(nameField[nameField.index(after: lastColon)...])
            guard let port = Int(portStr) else { continue }

            let key = "\(port)-\(pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            results.append(PortInfo(
                port: port,
                pid: pid,
                processName: processName,
                address: address,
                proto: proto
            ))
        }
        return results.sorted { $0.port < $1.port }
    }
}

// MARK: - Docker `ps` format

public enum DockerPsOutputParser {
    /// Same heuristics as `SystemMonitor.fetchDockerContainers` for raw CLI output.
    public static func parseCommandOutput(_ output: String) -> (containers: [DockerContainer], available: Bool) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || output.contains("Cannot connect") || output.contains("error") {
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
}

// MARK: - Memory (vm_stat + sysctl + swap + pressure)

public enum MemoryOutputParser {
    public static func parsePressureOutput(_ output: String) -> MemoryInfo.MemoryPressure {
        if output.contains("CRITICAL") { return .critical }
        if output.contains("WARN") { return .warn }
        return .nominal
    }

    public static func parseSwapUsage(_ swapOutput: String) -> (usedGB: Double, totalGB: Double) {
        var swapTotal: Double = 0
        var swapUsed: Double = 0
        let swapParts = swapOutput.components(separatedBy: "=")
        for (i, part) in swapParts.enumerated() {
            guard i > 0 else { continue }
            let cleaned = part.trimmingCharacters(in: .whitespaces)
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
        return (swapUsed, swapTotal)
    }

    public static func buildMemoryInfo(
        vmOutput: String,
        sysctlHwMemsize: String,
        swapOutput: String,
        pressureOutput: String
    ) -> MemoryInfo {
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
        for line in vmOutput.split(separator: "\n").dropFirst() {
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

        let totalBytes = Double(sysctlHwMemsize.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
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

        let swap = parseSwapUsage(swapOutput)
        let pressure = parsePressureOutput(pressureOutput)

        return MemoryInfo(
            totalGB: totalGB,
            usedGB: usedGB,
            freeGB: freeGB,
            swapUsedGB: swap.usedGB,
            swapTotalGB: swap.totalGB,
            pressure: pressure,
            appMemoryGB: appGB,
            wiredGB: wiredGB,
            compressedGB: compressedGB
        )
    }
}

// MARK: - ps RSS lines

public enum ProcessPsOutputParser {
    public static let systemUsers: Set<String> = [
        "root", "_windowserver", "_coreaudiod", "_locationd",
        "_displaypolicyd", "_distnoted", "_nsurlsessiond",
        "_mdnsresponder", "_timed", "_networkd", "_appleevents",
        "_cmiodalassistants", "_spotlight", "nobody", "_securityagent",
        "_coreml", "_trustd", "_analyticsd", "_fpsd"
    ]

    public static let systemProcessPrefixes: [String] = [
        "com.apple.", "kernel_task", "launchd", "WindowServer",
        "mds", "logd", "watchdog", "corespeech", "airportd",
        "bluetoothd", "UserEventAgent", "syslogd", "configd",
        "coreauthd", "opendirectoryd", "securityd"
    ]

    public static func parseTopProcesses(output: String, hwMemsizeBytes: Double) -> [ProcessMemoryInfo] {
        let totalMB = hwMemsizeBytes / 1_048_576
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

        let sorted = results.sorted { $0.memoryMB > $1.memoryMB }
        let topSystem = Array(sorted.filter { $0.isSystem }.prefix(10))
        let topUser = Array(sorted.filter { !$0.isSystem }.prefix(15))
        return (topSystem + topUser).sorted { $0.memoryMB > $1.memoryMB }
    }
}

// MARK: - HTML title (for web probe)

public enum HTMLTitleParser {
    public static func extractTitle(fromHTML html: String) -> String? {
        guard let titleStart = html.range(of: "<title>", options: .caseInsensitive),
              let titleEnd = html.range(of: "</title>", options: .caseInsensitive),
              titleStart.upperBound < titleEnd.lowerBound else { return nil }
        let title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
