import Foundation

// MARK: - Port Info

public struct PortInfo: Identifiable, Hashable {
    public let id = UUID()
    public let port: Int
    public let pid: Int
    public let processName: String
    public let address: String
    public let proto: String
    public var hasWebUI: Bool = false
    public var webTitle: String? = nil

    public init(port: Int, pid: Int, processName: String, address: String, proto: String, hasWebUI: Bool = false, webTitle: String? = nil) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.address = address
        self.proto = proto
        self.hasWebUI = hasWebUI
        self.webTitle = webTitle
    }

    public var webURL: URL? {
        guard hasWebUI else { return nil }
        return URL(string: "http://localhost:\(port)")
    }
}

// MARK: - Docker Container

public struct DockerContainer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let image: String
    public let status: String
    public let state: ContainerState
    public let ports: String

    public init(id: String, name: String, image: String, status: String, state: ContainerState, ports: String) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.state = state
        self.ports = ports
    }

    public enum ContainerState: String, Hashable {
        case running
        case exited
        case paused
        case restarting
        case other

        public var color: String {
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

public struct ProcessMemoryInfo: Identifiable, Hashable {
    public let id = UUID()
    public let pid: Int
    public let name: String
    public let memoryMB: Double
    public let memoryPercent: Double
    public let isSystem: Bool

    public init(pid: Int, name: String, memoryMB: Double, memoryPercent: Double, isSystem: Bool) {
        self.pid = pid
        self.name = name
        self.memoryMB = memoryMB
        self.memoryPercent = memoryPercent
        self.isSystem = isSystem
    }
}

// MARK: - Memory Info

public struct MemoryInfo: Equatable {
    public let totalGB: Double
    public let usedGB: Double
    public let freeGB: Double
    public let swapUsedGB: Double
    public let swapTotalGB: Double
    public let pressure: MemoryPressure
    public let appMemoryGB: Double
    public let wiredGB: Double
    public let compressedGB: Double

    public init(
        totalGB: Double,
        usedGB: Double,
        freeGB: Double,
        swapUsedGB: Double,
        swapTotalGB: Double,
        pressure: MemoryPressure,
        appMemoryGB: Double,
        wiredGB: Double,
        compressedGB: Double
    ) {
        self.totalGB = totalGB
        self.usedGB = usedGB
        self.freeGB = freeGB
        self.swapUsedGB = swapUsedGB
        self.swapTotalGB = swapTotalGB
        self.pressure = pressure
        self.appMemoryGB = appMemoryGB
        self.wiredGB = wiredGB
        self.compressedGB = compressedGB
    }

    public var usagePercent: Double {
        guard totalGB > 0 else { return 0 }
        return (usedGB / totalGB) * 100
    }

    public var swapPercent: Double {
        guard swapTotalGB > 0 else { return 0 }
        return (swapUsedGB / swapTotalGB) * 100
    }

    public enum MemoryPressure: String, Equatable {
        case nominal = "Normal"
        case warn = "Warning"
        case critical = "Critical"

        public var color: String {
            switch self {
            case .nominal: return "green"
            case .warn: return "yellow"
            case .critical: return "red"
            }
        }
    }
}

// MARK: - CPU Info

public struct CPUInfo: Equatable {
    /// 0...100, aggregate across all cores (user + system).
    public let percent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double

    public init(percent: Double, userPercent: Double, systemPercent: Double, idlePercent: Double) {
        self.percent = percent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
    }

    public static let zero = CPUInfo(percent: 0, userPercent: 0, systemPercent: 0, idlePercent: 100)
}

// MARK: - Disk Info

public struct DiskInfo: Equatable {
    public let totalGB: Double
    public let freeGB: Double

    public init(totalGB: Double, freeGB: Double) {
        self.totalGB = totalGB
        self.freeGB = freeGB
    }

    public var usedGB: Double { max(0, totalGB - freeGB) }
    public var usagePercent: Double {
        guard totalGB > 0 else { return 0 }
        return (usedGB / totalGB) * 100
    }

    public static let zero = DiskInfo(totalGB: 0, freeGB: 0)
}

// MARK: - Network Info

public struct NetworkInfo: Equatable {
    /// Bytes per second — downstream (incoming) rate across all interfaces (last sample).
    public let downBytesPerSec: Double
    public let upBytesPerSec: Double
    /// Cumulative bytes since app start — kept so callers can display totals.
    public let totalInBytes: UInt64
    public let totalOutBytes: UInt64

    public init(downBytesPerSec: Double, upBytesPerSec: Double, totalInBytes: UInt64, totalOutBytes: UInt64) {
        self.downBytesPerSec = downBytesPerSec
        self.upBytesPerSec = upBytesPerSec
        self.totalInBytes = totalInBytes
        self.totalOutBytes = totalOutBytes
    }

    public static let zero = NetworkInfo(downBytesPerSec: 0, upBytesPerSec: 0, totalInBytes: 0, totalOutBytes: 0)
}
