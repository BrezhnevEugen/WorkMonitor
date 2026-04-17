import Foundation

// MARK: - Port Info

struct PortInfo: Identifiable, Hashable {
    let id = UUID()
    let port: Int
    let pid: Int
    let processName: String
    let address: String  // e.g. "127.0.0.1" or "*"
    let proto: String    // "tcp4", "tcp6"
    var hasWebUI: Bool = false
    var webTitle: String? = nil  // page <title> if detected

    var webURL: URL? {
        guard hasWebUI else { return nil }
        return URL(string: "http://localhost:\(port)")
    }
}

// MARK: - Docker Container

struct DockerContainer: Identifiable, Hashable {
    let id: String       // container ID (short)
    let name: String
    let image: String
    let status: String
    let state: ContainerState
    let ports: String

    enum ContainerState: String {
        case running
        case exited
        case paused
        case restarting
        case other

        var color: String {
            switch self {
            case .running: return "green"
            case .exited: return "red"
            case .paused: return "yellow"
            case .restarting: return "orange"
            case .other: return "gray"
            }
        }
    }
}

// MARK: - Process Memory

struct ProcessMemoryInfo: Identifiable, Hashable {
    let id = UUID()
    let pid: Int
    let name: String
    let memoryMB: Double
    let memoryPercent: Double
    let isSystem: Bool
}

// MARK: - Memory Info

struct MemoryInfo {
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
    let swapUsedGB: Double
    let swapTotalGB: Double
    let pressure: MemoryPressure
    let appMemoryGB: Double      // App memory (used by apps)
    let wiredGB: Double          // Wired memory
    let compressedGB: Double     // Compressed memory

    var usagePercent: Double {
        guard totalGB > 0 else { return 0 }
        return (usedGB / totalGB) * 100
    }

    var swapPercent: Double {
        guard swapTotalGB > 0 else { return 0 }
        return (swapUsedGB / swapTotalGB) * 100
    }

    enum MemoryPressure: String {
        case nominal = "Normal"
        case warn = "Warning"
        case critical = "Critical"

        var color: String {
            switch self {
            case .nominal: return "green"
            case .warn: return "yellow"
            case .critical: return "red"
            }
        }
    }
}
