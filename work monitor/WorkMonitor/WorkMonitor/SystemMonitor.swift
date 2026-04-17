import Combine
import Foundation
import WorkMonitorCore

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
        let output = await shell("/bin/sh", args: ["-c", "lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null"])
        return LsofListenOutputParser.parseListenOutput(output)
    }

    // MARK: - Docker

    private static func fetchDockerContainers() async -> (containers: [DockerContainer], available: Bool) {
        let dockerPath = await findDocker()
        guard let path = dockerPath else {
            return ([], false)
        }

        let output = await shell(path, args: [
            "ps", "-a",
            "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}|{{.Ports}}"
        ])

        return DockerPsOutputParser.parseCommandOutput(output)
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
        let which = await shell("/usr/bin/which", args: ["docker"])
        let trimmed = which.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    // MARK: - Memory via vm_stat + sysctl

    private static func fetchMemory() async -> MemoryInfo {
        let vmOutput = await shell("/bin/sh", args: ["-c", "vm_stat 2>/dev/null"])
        let sysctlOutput = await shell("/bin/sh", args: ["-c", "sysctl -n hw.memsize 2>/dev/null"])
        let swapOutput = await shell("/bin/sh", args: ["-c", "sysctl vm.swapusage 2>/dev/null"])
        let pressureOutput = await shell("/bin/sh", args: ["-c", "memory_pressure 2>/dev/null || echo NOMINAL"])
        return MemoryOutputParser.buildMemoryInfo(
            vmOutput: vmOutput,
            sysctlHwMemsize: sysctlOutput,
            swapOutput: swapOutput,
            pressureOutput: pressureOutput
        )
    }

    // MARK: - Top processes by memory

    private static func fetchTopProcesses() async -> [ProcessMemoryInfo] {
        let memStr = await shell("/bin/sh", args: ["-c", "sysctl -n hw.memsize 2>/dev/null"])
        let totalBytes = Double(memStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let output = await shell("/bin/sh", args: ["-c", "ps -Axo user=,pid=,rss=,comm= 2>/dev/null | sort -k3 -nr | head -50"])
        return ProcessPsOutputParser.parseTopProcesses(output: output, hwMemsizeBytes: totalBytes)
    }

    // MARK: - Web UI probe

    private static func probeWebUIs(ports: [PortInfo]) async -> [PortInfo] {
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

            let statusCode = httpResponse.statusCode
            guard (100...599).contains(statusCode) else { return (false, nil) }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            var title: String? = nil

            if contentType.contains("text/html") || contentType.contains("application/xhtml") {
                let html = String(data: data.prefix(4096), encoding: .utf8) ?? ""
                title = HTMLTitleParser.extractTitle(fromHTML: html)
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
