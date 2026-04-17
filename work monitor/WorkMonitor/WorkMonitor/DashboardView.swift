import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var showAbout: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if showAbout {
                AboutView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { showAbout = false } })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerView
                        MemorySectionView(memory: monitor.memory, topProcesses: monitor.topProcesses)
                        PortsSectionView(ports: monitor.ports)
                        DockerSectionView(
                            containers: monitor.containers,
                            dockerAvailable: monitor.dockerAvailable
                        )
                    }
                    .padding(16)
                }

                Divider()

                HStack {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAbout = true } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                            Text("About")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    Spacer()

                    Button(action: { NSApp.terminate(nil) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 9))
                            Text("Quit")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 480, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Work Monitor")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if monitor.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(monitor.lastUpdated, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Memory Section

struct MemorySectionView: View {
    let memory: MemoryInfo
    let topProcesses: [ProcessMemoryInfo]

    var body: some View {
        SectionContainer(title: "Memory", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 10) {
                // Main bar
                HStack {
                    ProgressBarView(
                        value: memory.usagePercent / 100,
                        color: memoryColor,
                        label: "RAM"
                    )
                    Text(String(format: "%.1f / %.0f GB", memory.usedGB, memory.totalGB))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }

                // Breakdown
                HStack(spacing: 16) {
                    MemoryChip(label: "Apps", value: memory.appMemoryGB, color: .blue)
                    MemoryChip(label: "Wired", value: memory.wiredGB, color: .orange)
                    MemoryChip(label: "Compressed", value: memory.compressedGB, color: .purple)
                }

                // Swap
                HStack {
                    ProgressBarView(
                        value: memory.swapPercent / 100,
                        color: memory.swapUsedGB > 2 ? .red : .yellow,
                        label: "Swap"
                    )
                    Text(String(format: "%.1f / %.1f GB", memory.swapUsedGB, memory.swapTotalGB))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }

                // Pressure + detail button
                HStack(spacing: 6) {
                    Circle()
                        .fill(pressureColor)
                        .frame(width: 8, height: 8)
                    Text("Pressure: \(memory.pressure.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        ProcessesPanel.shared.toggle(processes: topProcesses, memory: memory)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 10))
                            Text("Processes")
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
    }

    private var memoryColor: Color {
        if memory.usagePercent > 90 { return .red }
        if memory.usagePercent > 70 { return .orange }
        return .green
    }

    private var pressureColor: Color {
        switch memory.pressure {
        case .nominal: return .green
        case .warn: return .yellow
        case .critical: return .red
        }
    }
}

struct MemoryChip: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label): \(String(format: "%.1f", value)) GB")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct TopProcessesView: View {
    let processes: [ProcessMemoryInfo]
    let totalGB: Double

    var body: some View {
        VStack(spacing: 0) {
            ForEach(processes) { proc in
                HStack(spacing: 8) {
                    Text(proc.name)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Mini bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(barColor(proc.memoryMB))
                                .frame(width: max(0, geo.size.width * min(proc.memoryPercent / 100, 1.0)), height: 4)
                        }
                    }
                    .frame(width: 60, height: 4)

                    Text(formatMemory(proc.memoryMB))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 65, alignment: .trailing)

                    Text(verbatim: String(proc.pid))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 45, alignment: .trailing)
                }
                .padding(.vertical, 3)

                if proc != processes.last {
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    private func barColor(_ mb: Double) -> Color {
        if mb >= 2048 { return .red }
        if mb >= 512 { return .orange }
        return .blue
    }
}

// MARK: - Ports Section

struct PortsSectionView: View {
    let ports: [PortInfo]
    @State private var isExpanded: Bool = false

    /// Group ports by process name, sorted by lowest port in each group
    private var groupedPorts: [(name: String, ports: [PortInfo])] {
        let dict = Dictionary(grouping: ports) { $0.processName }
        return dict.map { (name: $0.key, ports: $0.value.sorted { $0.port < $1.port }) }
            .sorted { $0.ports.first!.port < $1.ports.first!.port }
    }

    var body: some View {
        SectionContainer(
            title: "Listening Ports",
            icon: "network",
            badge: "\(ports.count)"
        ) {
            if ports.isEmpty {
                Text("No listening ports detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    // Clickable header to expand/collapse
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                        HStack {
                            let webCount = ports.filter { $0.hasWebUI }.count
                            Text("\(ports.count) ports · \(groupedPorts.count) apps" + (webCount > 0 ? " · \(webCount) web" : ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        ForEach(Array(groupedPorts.enumerated()), id: \.offset) { _, group in
                            PortGroupRow(name: group.name, ports: group.ports)
                        }
                    } // end if isExpanded
                }
            }
        }
    }
}

/// A collapsible group of ports belonging to one process
struct PortGroupRow: View {
    let name: String
    let ports: [PortInfo]
    @State private var isGroupExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)

            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isGroupExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isGroupExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)

                    Text(name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    // Show port numbers inline as compact chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(ports) { port in
                                HStack(spacing: 2) {
                                    if port.hasWebUI {
                                        Image(systemName: "globe")
                                            .font(.system(size: 8))
                                    }
                                    Text(verbatim: String(port.port))
                                        .font(.system(.caption2, design: .monospaced))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(port.hasWebUI ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                                .foregroundColor(port.hasWebUI ? .green : .accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }

                    Spacer()

                    Text(verbatim: "\(ports.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isGroupExpanded {
                VStack(spacing: 0) {
                    ForEach(ports) { port in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(verbatim: String(port.port))
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 60, alignment: .leading)
                                Text(port.address)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)

                                if port.hasWebUI {
                                    if let title = port.webTitle {
                                        Text(title)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if port.hasWebUI, let url = port.webURL {
                                    Button(action: { NSWorkspace.shared.open(url) }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 9))
                                            Text("Open")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.green)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                                }

                                Text(verbatim: "PID \(port.pid)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.leading, 18)

                        if port.id != ports.last?.id {
                            Divider().opacity(0.2).padding(.leading, 18)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Docker Section

struct DockerSectionView: View {
    let containers: [DockerContainer]
    let dockerAvailable: Bool
    @State private var isExpanded: Bool = false

    private var runningCount: Int {
        containers.filter { $0.state == .running }.count
    }

    var body: some View {
        SectionContainer(
            title: "Docker",
            icon: "shippingbox",
            badge: dockerAvailable ? "\(runningCount) running" : nil
        ) {
            if !dockerAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Docker is not running or not installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if containers.isEmpty {
                Text("No containers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    // Collapsed summary
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                        HStack {
                            Text("\(runningCount) running · \(containers.count) total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        ForEach(containers) { container in
                            Divider().opacity(0.5)

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(stateColor(container.state))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(container.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(container.image)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(container.status)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if !container.ports.isEmpty {
                                        Text(container.ports)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private func stateColor(_ state: DockerContainer.ContainerState) -> Color {
        switch state {
        case .running: return .green
        case .exited: return .red
        case .paused: return .yellow
        case .restarting: return .orange
        case .other: return .gray
        }
    }
}

// MARK: - Reusable Components

struct SectionContainer<Content: View>: View {
    let title: String
    let icon: String
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                if let badge = badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            content
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - About View

struct AboutView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 20)

                    // App icon
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    // Title & version
                    VStack(spacing: 4) {
                        Text("Work Monitor")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("v1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Description
                    Text("Dev environment dashboard for macOS. Monitors ports, Docker containers, memory usage, and running processes from your menu bar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Divider().padding(.horizontal, 40)

                    // Features
                    VStack(alignment: .leading, spacing: 10) {
                        AboutFeatureRow(icon: "network", color: .blue, title: "Listening Ports", description: "Grouped by app, web panel detection with one-click open")
                        AboutFeatureRow(icon: "shippingbox", color: .orange, title: "Docker Containers", description: "Running status, images, port mappings")
                        AboutFeatureRow(icon: "memorychip", color: .green, title: "Memory Monitor", description: "RAM, Swap, pressure level, Apps/Wired/Compressed breakdown")
                        AboutFeatureRow(icon: "list.bullet.rectangle", color: .purple, title: "Process Manager", description: "Top processes by memory, system vs user, kill user processes")
                    }
                    .padding(.horizontal, 30)

                    Divider().padding(.horizontal, 40)

                    // Tech info
                    VStack(spacing: 6) {
                        AboutInfoRow(label: "Platform", value: "macOS 13+")
                        AboutInfoRow(label: "Framework", value: "Swift + SwiftUI")
                        AboutInfoRow(label: "Refresh", value: "Every 5 seconds")
                        AboutInfoRow(label: "Author", value: "Eugen Brezhnev")
                    }
                    .padding(.horizontal, 30)

                    Spacer().frame(height: 10)
                }
            }

            Divider()

            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Back")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AboutInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct ProgressBarView: View {
    let value: Double  // 0..1
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * min(value, 1.0)), height: 6)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.0f%%", value * 100))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }
}
