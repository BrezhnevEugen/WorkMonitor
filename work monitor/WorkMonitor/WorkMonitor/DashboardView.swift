import AppKit
import SwiftUI
import WorkMonitorCore

// MARK: - Links

private enum SupportLinks {
    static let boostyDonate = URL(string: "https://boosty.to/genius_me/donate")!
}

// MARK: - Root

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var settings: AppSettings
    @State private var route: Route = .main

    enum Route { case main, about, settings }

    var body: some View {
        ZStack {
            Theme.bgPopover.ignoresSafeArea()
            switch route {
            case .main:
                mainView.transition(.opacity)
            case .about:
                AboutView(onBack: { go(.main) })
                    .transition(.opacity)
            case .settings:
                SettingsView(onBack: { go(.main) })
                    .transition(.opacity)
            }
        }
        .frame(width: 420, height: 600)
        .preferredColorScheme(themeManager.palette.colorScheme)
    }

    private func go(_ r: Route) {
        withAnimation(.easeInOut(duration: 0.15)) { route = r }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            HeaderView(monitor: monitor, onOpenSettings: { go(.settings) })
            SummaryBar(
                cpu: monitor.cpu,
                memory: monitor.memory,
                disk: monitor.disk,
                network: monitor.network
            )
            .background(Theme.bgPopoverElev)
            Divider().overlay(Theme.border)

            ScrollView {
                VStack(spacing: 0) {
                    if settings.showPorts {
                        PortsSection(ports: monitor.ports)
                    }
                    if settings.showDocker {
                        DockerSection(containers: monitor.containers, dockerAvailable: monitor.dockerAvailable)
                    }
                    if settings.showProcesses {
                        ProcessesSection(processes: monitor.topProcesses)
                    }
                    if !settings.showPorts && !settings.showDocker && !settings.showProcesses {
                        EmptyRow(text: loc.tr("sections_all_hidden"))
                            .padding(.vertical, 20)
                    }
                }
            }
            .background(Theme.bgPopover)

            FooterView(
                lastUpdated: monitor.lastUpdated,
                isLoading: monitor.isLoading,
                onAbout: { go(.about) }
            )
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    @ObservedObject var monitor: SystemMonitor
    let onOpenSettings: () -> Void
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("▣")
                    .font(Theme.title)
                    .foregroundColor(Theme.accent)
                Text("work-monitor")
                    .font(Theme.title)
                    .foregroundColor(Theme.text)
                Spacer()
                IconButton(symbol: "arrow.clockwise", tooltip: loc.tr("refresh")) {
                    monitor.refresh()
                }
                IconButton(symbol: "gearshape", tooltip: loc.tr("settings"), action: onOpenSettings)
            }
            HStack(spacing: 8) {
                Pill(text: "● dev", color: Theme.accent)
                Text(hostDescription)
                    .font(Theme.small)
                    .foregroundColor(Theme.textDim)
                Spacer()
                Text(loc.formatRelativeUpdated(monitor.lastUpdated))
                    .font(Theme.small)
                    .foregroundColor(Theme.textMute)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var hostDescription: String {
        let hostName = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
        let sys = ProcessInfo.processInfo.operatingSystemVersion
        return "\(hostName) · macOS \(sys.majorVersion).\(sys.minorVersion)"
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(Theme.tiny)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct IconButton: View {
    let symbol: String
    let tooltip: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundColor(hovering ? Theme.accent : Theme.textDim)
                .background(hovering ? Theme.accent.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(hovering ? Theme.accentDim : Theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Summary Bar

struct SummaryBar: View {
    let cpu: CPUInfo
    let memory: MemoryInfo
    let disk: DiskInfo
    let network: NetworkInfo
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MetricCell(
                label: loc.tr("metric_cpu"),
                value: String(format: "%.0f", cpu.percent),
                unit: "%",
                fraction: min(1, cpu.percent / 100),
                tone: tone(for: cpu.percent, warn: 70, crit: 90)
            )
            MetricCell(
                label: loc.tr("metric_ram"),
                value: String(format: "%.1f", memory.usedGB),
                unit: "/\(Int(memory.totalGB.rounded())) ГБ",
                fraction: min(1, memory.usagePercent / 100),
                tone: tone(for: memory.usagePercent, warn: 75, crit: 90)
            )
            MetricCell(
                label: loc.tr("metric_disk"),
                value: String(format: "%.0f", disk.freeGB),
                unit: "ГБ free",
                fraction: min(1, disk.usagePercent / 100),
                tone: tone(for: disk.usagePercent, warn: 85, crit: 95)
            )
            MetricCell(
                label: loc.tr("metric_net"),
                value: loc.formatNetworkRate(network.downBytesPerSec),
                unit: "↓",
                fraction: min(1, network.downBytesPerSec / (20 * 1024 * 1024)), // scale to 20 MB/s max
                tone: .normal,
                unitFirst: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func tone(for value: Double, warn: Double, crit: Double) -> MetricCell.Tone {
        if value >= crit { return .critical }
        if value >= warn { return .warning }
        return .normal
    }
}

struct MetricCell: View {
    enum Tone { case normal, warning, critical }
    let label: String
    let value: String
    let unit: String
    let fraction: Double
    let tone: Tone
    var unitFirst: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textMute)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if unitFirst {
                    Text(unit).font(Theme.tiny).foregroundColor(Theme.textMute)
                    Text(value).font(Theme.metric).foregroundColor(Theme.text)
                } else {
                    Text(value).font(Theme.metric).foregroundColor(Theme.text)
                    Text(unit).font(Theme.tiny).foregroundColor(Theme.textMute)
                }
            }

            MiniBar(fraction: fraction, color: barColor)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var barColor: Color {
        switch tone {
        case .normal:   return Theme.accent
        case .warning:  return Theme.amber
        case .critical: return Theme.red
        }
    }
}

struct MiniBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.miniBarTrack)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, CGFloat(min(1, max(0, fraction))) * geo.size.width))
            }
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: String?
    @ViewBuilder let content: () -> Content

    @State private var collapsed = false

    init(title: String, count: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeOut(duration: 0.12)) { collapsed.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.textMute)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    Text(title)
                        .font(Theme.sectionCaption)
                        .foregroundColor(Theme.textDim)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    if let count = count {
                        Text(count)
                            .font(Theme.tiny)
                            .foregroundColor(Theme.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.sectionCountBg)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(spacing: 0) { content() }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

// MARK: - Ports section

struct PortsSection: View {
    let ports: [PortInfo]
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var settings: AppSettings

    /// Grouped by process name (stable): first occurrence dictates app order by its lowest port.
    private var groups: [(app: String, ports: [PortInfo])] {
        var bucket: [String: [PortInfo]] = [:]
        var order: [String] = []
        for p in ports {
            if bucket[p.processName] == nil {
                bucket[p.processName] = []
                order.append(p.processName)
            }
            bucket[p.processName]?.append(p)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    var body: some View {
        CollapsibleSection(title: loc.tr("section_ports"), count: "\(ports.count)") {
            if ports.isEmpty {
                EmptyRow(text: loc.tr("no_listening_ports"))
            } else if settings.groupPortsByApp {
                ForEach(groups, id: \.app) { group in
                    PortAppGroupView(appName: group.app, ports: group.ports)
                }
            } else {
                ForEach(ports) { port in
                    PortRow(port: port)
                }
            }
        }
    }
}

/// Collapsible "app" subheader + its ports indented below. Mirrors the grouped
/// layout from v1 but inside the new dark-technical look.
struct PortAppGroupView: View {
    let appName: String
    let ports: [PortInfo]

    @State private var collapsed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeOut(duration: 0.1)) { collapsed.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.textMute)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    Text(appName)
                        .font(Theme.bodyBold)
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text("×\(ports.count)")
                        .font(Theme.tiny)
                        .foregroundColor(Theme.textMute)
                    Spacer()
                    let pids = Set(ports.map { $0.pid })
                    if pids.count == 1, let pid = pids.first {
                        Text("pid \(pid)")
                            .font(Theme.tiny)
                            .foregroundColor(Theme.textMute)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(spacing: 0) {
                    ForEach(ports) { port in
                        PortRow(port: port, compact: true)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }
}

struct PortRow: View {
    let port: PortInfo
    /// When shown inside a grouped app, the process name is already in the app header,
    /// so the row omits it and emphasises the port number + web title/address instead.
    var compact: Bool = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(port.port)")
                .font(Theme.bodyBold)
                .foregroundColor(Theme.accent)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    Text(port.processName)
                        .font(Theme.body)
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                }
                if let title = port.webTitle, !title.isEmpty {
                    Text(title)
                        .font(compact ? Theme.small : Theme.tiny)
                        .foregroundColor(compact ? Theme.textDim : Theme.textMute)
                        .lineLimit(1)
                } else {
                    Text(port.address.isEmpty ? port.proto : "\(port.proto) · \(port.address)")
                        .font(compact ? Theme.small : Theme.tiny)
                        .foregroundColor(compact ? Theme.textDim : Theme.textMute)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !compact {
                Text("pid \(port.pid)")
                    .font(Theme.tiny)
                    .foregroundColor(Theme.textMute)
                    .opacity(hovering ? 0 : 1)
            }

            RevealOnRowHover(hovering: hovering) {
                HStack(spacing: 4) {
                    if port.hasWebUI, let url = port.webURL {
                        HoverAction(title: "open") { NSWorkspace.shared.open(url) }
                    }
                    HoverAction(title: "kill", danger: true) { killPID(port.pid) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.bgRowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func killPID(_ pid: Int) {
        guard pid > 0 else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", "\(pid)"]
        try? process.run()
    }
}

// MARK: - Docker section

struct DockerSection: View {
    let containers: [DockerContainer]
    let dockerAvailable: Bool
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        CollapsibleSection(
            title: loc.tr("section_docker"),
            count: countBadge
        ) {
            if !dockerAvailable {
                EmptyRow(text: loc.tr("docker_not_running"))
            } else if containers.isEmpty {
                EmptyRow(text: loc.tr("no_containers"))
            } else {
                ForEach(containers, id: \.id) { c in
                    DockerRow(container: c)
                }
            }
        }
    }

    private var countBadge: String {
        let running = containers.filter { $0.state == .running }.count
        return running == 0 ? "\(containers.count)" : String(format: loc.tr("docker_badge_running_format"), running)
    }
}

struct DockerRow: View {
    let container: DockerContainer
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.8), radius: container.state == .running ? 3 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(Theme.body)
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(container.image)
                        .font(Theme.tiny)
                        .foregroundColor(Theme.purple)
                        .lineLimit(1)
                    if !container.ports.isEmpty {
                        Text(shortPorts(container.ports))
                            .font(Theme.tiny)
                            .foregroundColor(Theme.textMute)
                            .lineLimit(1)
                    }
                    Text(shortStatus(container.status))
                        .font(Theme.tiny)
                        .foregroundColor(Theme.textMute)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RevealOnRowHover(hovering: hovering) {
                HStack(spacing: 4) {
                    HoverAction(title: container.state == .running ? "stop" : "start") { }
                    HoverAction(title: "logs") { }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.bgRowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var statusColor: Color {
        switch container.state {
        case .running:    return Theme.accent
        case .exited:     return Theme.textMute
        case .restarting: return Theme.amber
        case .paused:     return Theme.amber
        case .other:      return Theme.textMute
        }
    }

    private func shortPorts(_ raw: String) -> String {
        // "0.0.0.0:5432->5432/tcp" → ":5432"
        if let range = raw.range(of: #":\d+"#, options: .regularExpression) {
            return String(raw[range])
        }
        return raw
    }

    private func shortStatus(_ raw: String) -> String {
        // "Up 3 hours" → "up 3h"; fall back to raw.
        raw.lowercased()
            .replacingOccurrences(of: " hours", with: "h")
            .replacingOccurrences(of: " hour", with: "h")
            .replacingOccurrences(of: " minutes", with: "m")
            .replacingOccurrences(of: " minute", with: "m")
            .replacingOccurrences(of: " seconds", with: "s")
            .replacingOccurrences(of: " second", with: "s")
    }
}

// MARK: - Processes section

struct ProcessesSection: View {
    let processes: [ProcessMemoryInfo]
    @EnvironmentObject private var loc: LocalizationManager

    private var top: [ProcessMemoryInfo] {
        Array(processes.prefix(6))
    }

    var body: some View {
        CollapsibleSection(title: loc.tr("section_processes"), count: "by RAM") {
            if top.isEmpty {
                EmptyRow(text: "—")
            } else {
                ForEach(top) { p in TopProcessRow(process: p) }
            }
        }
    }
}

struct TopProcessRow: View {
    let process: ProcessMemoryInfo
    @State private var hovering = false
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        HStack(spacing: 10) {
            Text(process.name)
                .font(Theme.body)
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(loc.formatMegabytesOrGigabytes(process.memoryMB))
                .font(Theme.small)
                .foregroundColor(hotColor)
                .frame(width: 64, alignment: .trailing)

            Text(String(format: "%.0f%%", process.memoryPercent))
                .font(Theme.small)
                .foregroundColor(Theme.textDim)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.bgRowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var hotColor: Color {
        if process.memoryPercent >= 10 { return Theme.amber }
        if process.memoryPercent >= 25 { return Theme.red }
        return Theme.textDim
    }
}

// MARK: - Small building blocks

struct EmptyRow: View {
    let text: String
    var body: some View {
        HStack {
            Text(text)
                .font(Theme.small)
                .foregroundColor(Theme.textMute)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            Spacer()
        }
    }
}

struct HoverAction: View {
    let title: String
    var danger: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.tiny)
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var color: Color {
        if danger { return hovering ? Theme.red : Theme.textDim }
        return hovering ? Theme.accent : Theme.textDim
    }
    private var borderColor: Color {
        if danger { return hovering ? Theme.red : Theme.borderStrong }
        return hovering ? Theme.accentDim : Theme.borderStrong
    }
}

// MARK: - Footer

struct FooterView: View {
    let lastUpdated: Date
    let isLoading: Bool
    let onAbout: () -> Void
    @EnvironmentObject private var loc: LocalizationManager
    @State private var blink = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .opacity(blink ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: blink)
                Text(isLoading ? loc.tr("footer_loading") : loc.tr("footer_live"))
                    .font(Theme.tiny)
                    .foregroundColor(Theme.textMute)
            }
            Spacer()
            HStack(spacing: 10) {
                FooterLink(label: loc.tr("about"), action: onAbout)
                FooterLink(label: "♥ " + loc.tr("boosty"), color: Theme.accent) {
                    NSWorkspace.shared.open(SupportLinks.boostyDonate)
                }
                FooterLink(label: "⌘Q  " + loc.tr("quit")) { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.bgPopoverElev)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .onAppear { blink = true }
    }
}

struct FooterLink: View {
    let label: String
    var color: Color = Theme.textDim
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.tiny)
                .foregroundColor(hovering ? Theme.accent : color)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - About (compact)

struct AboutView: View {
    let onBack: () -> Void
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var themeManager: ThemeManager

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(symbol: "chevron.left", tooltip: loc.tr("about_back"), action: onBack)
                Text("about")
                    .font(Theme.title)
                    .foregroundColor(Theme.text)
                Spacer()
                Text("v\(version)")
                    .font(Theme.small)
                    .foregroundColor(Theme.textMute)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(loc.tr("about_body_1"))
                        .font(Theme.body)
                        .foregroundColor(Theme.textDim)
                    Text(loc.tr("about_body_2"))
                        .font(Theme.body)
                        .foregroundColor(Theme.textDim)
                    Text(loc.tr("about_body_3"))
                        .font(Theme.body)
                        .foregroundColor(Theme.textDim)

                    Divider().overlay(Theme.border)

                    InfoRow(key: loc.tr("about_info_platform"),  value: loc.tr("about_info_platform_value"))
                    InfoRow(key: loc.tr("about_info_framework"), value: loc.tr("about_info_framework_value"))
                    InfoRow(key: loc.tr("about_info_refresh"),   value: loc.tr("about_info_refresh_value"))
                    InfoRow(key: loc.tr("about_info_author"),    value: loc.tr("about_info_author_value"))

                    Divider().overlay(Theme.border)

                    Text(loc.tr("about_support_heading"))
                        .font(Theme.sectionCaption)
                        .foregroundColor(Theme.textDim)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(loc.tr("about_support_body"))
                        .font(Theme.body)
                        .foregroundColor(Theme.textDim)
                    Button(action: { NSWorkspace.shared.open(SupportLinks.boostyDonate) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                            Text(loc.tr("about_boosty_button"))
                        }
                        .font(Theme.body)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.accentDim, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
        .background(Theme.bgPopover)
    }
}

struct InfoRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key)
                .font(Theme.small)
                .foregroundColor(Theme.textMute)
            Spacer()
            Text(value)
                .font(Theme.small)
                .foregroundColor(Theme.text)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let onBack: () -> Void
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var updater: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                IconButton(symbol: "chevron.left", tooltip: loc.tr("about_back"), action: onBack)
                Text("settings")
                    .font(Theme.title)
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // — Theme
                    SettingsGroup(title: loc.tr("settings_theme_section")) {
                        VStack(spacing: 0) {
                            ForEach(ThemeKind.allCases) { kind in
                                ThemeOptionRow(
                                    kind: kind,
                                    selected: themeManager.kind == kind
                                ) { themeManager.kind = kind }
                                if kind != ThemeKind.allCases.last {
                                    Divider().overlay(Theme.border).padding(.leading, 10)
                                }
                            }
                        }
                    }

                    // — Visible sections
                    SettingsGroup(title: loc.tr("settings_sections_section")) {
                        VStack(spacing: 0) {
                            CheckboxRow(
                                label: loc.tr("section_ports"),
                                isOn: Binding(
                                    get: { settings.showPorts },
                                    set: { settings.showPorts = $0 }
                                )
                            )
                            Divider().overlay(Theme.border).padding(.leading, 10)
                            CheckboxRow(
                                label: loc.tr("section_docker"),
                                isOn: Binding(
                                    get: { settings.showDocker },
                                    set: { settings.showDocker = $0 }
                                )
                            )
                            Divider().overlay(Theme.border).padding(.leading, 10)
                            CheckboxRow(
                                label: loc.tr("section_processes"),
                                isOn: Binding(
                                    get: { settings.showProcesses },
                                    set: { settings.showProcesses = $0 }
                                )
                            )
                        }
                    }

                    // — Ports
                    SettingsGroup(title: loc.tr("settings_ports_section")) {
                        CheckboxRow(
                            label: loc.tr("settings_group_ports_by_app"),
                            isOn: Binding(
                                get: { settings.groupPortsByApp },
                                set: { settings.groupPortsByApp = $0 }
                            )
                        )
                    }

                    // — Language
                    SettingsGroup(title: loc.tr("settings_language")) {
                        VStack(spacing: 0) {
                            ForEach(AppLanguage.allCases) { lang in
                                LanguageOptionRow(
                                    language: lang,
                                    selected: loc.language == lang
                                ) { loc.language = lang }
                                if lang != AppLanguage.allCases.last {
                                    Divider().overlay(Theme.border).padding(.leading, 10)
                                }
                            }
                        }
                    }

                    // — Refresh
                    SettingsGroup(title: loc.tr("settings_refresh_section")) {
                        VStack(spacing: 0) {
                            IntervalPickerRow(
                                label: loc.tr("settings_refresh_open"),
                                presets: AppSettings.popoverRefreshPresets,
                                selected: Binding(
                                    get: { settings.popoverRefreshSec },
                                    set: { settings.popoverRefreshSec = $0 }
                                )
                            )
                            Divider().overlay(Theme.border).padding(.leading, 10)
                            IntervalPickerRow(
                                label: loc.tr("settings_refresh_bg"),
                                presets: AppSettings.backgroundRefreshPresets,
                                selected: Binding(
                                    get: { settings.backgroundRefreshSec },
                                    set: { settings.backgroundRefreshSec = $0 }
                                )
                            )
                        }
                    }

                    // — Updates
                    SettingsGroup(title: loc.tr("settings_updates_section")) {
                        VStack(spacing: 0) {
                            UpdateStatusRow()
                            Divider().overlay(Theme.border).padding(.leading, 10)
                            CheckboxRow(
                                label: loc.tr("settings_updates_auto"),
                                isOn: Binding(
                                    get: { settings.autoCheckUpdates },
                                    set: { settings.autoCheckUpdates = $0 }
                                )
                            )
                        }
                    }

                    // — System
                    SettingsGroup(title: loc.tr("settings_system_section")) {
                        VStack(spacing: 0) {
                            Button(action: openLoginItems) {
                                HStack {
                                    Text(loc.tr("settings_open_login_items"))
                                        .font(Theme.small)
                                        .foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textMute)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }
                .padding(14)
            }
        }
        .background(Theme.bgPopover)
    }

    private func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.sectionCaption)
                .foregroundColor(Theme.textDim)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 2)
            content()
                .background(Theme.bgPopoverElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct LanguageOptionRow: View {
    let language: AppLanguage
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(selected ? Theme.accent : Theme.borderStrong, lineWidth: 1)
                        .frame(width: 12, height: 12)
                    if selected {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(loc.tr(language.pickerTitleKey))
                    .font(Theme.small)
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(hovering ? Theme.bgRowHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct InfoRowBoxed: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key)
                .font(Theme.small)
                .foregroundColor(Theme.textMute)
            Spacer()
            Text(value)
                .font(Theme.small)
                .foregroundColor(Theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

struct UpdateStatusRow: View {
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var updater: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            // Top: label + current version + check button
            HStack(spacing: 10) {
                Text(loc.tr("settings_updates_current"))
                    .font(Theme.small)
                    .foregroundColor(Theme.textMute)
                Spacer()
                Text("v\(updater.currentVersion)")
                    .font(Theme.small)
                    .foregroundColor(Theme.text)
                Button(action: { updater.checkNow() }) {
                    HStack(spacing: 4) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(loc.tr("settings_updates_check_now"))
                            .font(Theme.tiny)
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Theme.accentDim, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            // Status line
            statusContent
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
        }
    }

    private var isChecking: Bool {
        if case .checking = updater.status { return true }
        return false
    }

    @ViewBuilder
    private var statusContent: some View {
        switch updater.status {
        case .idle:
            HStack {
                Text(idleLabel)
                    .font(Theme.tiny)
                    .foregroundColor(Theme.textMute)
                Spacer()
            }
        case .checking:
            HStack {
                Text(loc.tr("settings_updates_checking"))
                    .font(Theme.tiny)
                    .foregroundColor(Theme.textDim)
                Spacer()
            }
        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.accent)
                Text(loc.tr("settings_updates_up_to_date"))
                    .font(Theme.tiny)
                    .foregroundColor(Theme.text)
                Spacer()
            }
        case .available(let latest, let url, _):
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.amber)
                Text(String(format: loc.tr("settings_updates_available_format"), latest))
                    .font(Theme.tiny)
                    .foregroundColor(Theme.text)
                Spacer()
                Button(action: { NSWorkspace.shared.open(url) }) {
                    Text(loc.tr("settings_updates_open_release"))
                        .font(Theme.tiny)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Theme.accentDim, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.red)
                Text(message)
                    .font(Theme.tiny)
                    .foregroundColor(Theme.textDim)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    private var idleLabel: String {
        if let d = updater.lastCheckedAt {
            return String(format: loc.tr("settings_updates_last_checked_format"), loc.formatRelativeUpdated(d))
        }
        return loc.tr("settings_updates_never_checked")
    }
}

struct IntervalPickerRow: View {
    let label: String
    let presets: [Double]
    @Binding var selected: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.small)
                .foregroundColor(Theme.textMute)
            Spacer()
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { value in
                    IntervalChip(
                        value: value,
                        isSelected: abs(selected - value) < 0.001
                    ) { selected = value }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

struct IntervalChip: View {
    let value: Double
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            Text(formatted)
                .font(Theme.tiny)
                .foregroundColor(isSelected ? Theme.accent : (hovering ? Theme.text : Theme.textDim))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isSelected ? Theme.accent.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? Theme.accentDim : Theme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var formatted: String {
        value >= 60 ? "\(Int(value / 60))m" : "\(Int(value))s"
    }
}

struct ThemeOptionRow: View {
    let kind: ThemeKind
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(selected ? Theme.accent : Theme.borderStrong, lineWidth: 1)
                        .frame(width: 12, height: 12)
                    if selected {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    }
                }
                // 3-color preview
                HStack(spacing: 3) {
                    ForEach(Array(kind.previewColors.enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(c)
                            .frame(width: 10, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                    }
                }
                Text(loc.tr(kind.titleKey))
                    .font(Theme.small)
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(hovering ? Theme.bgRowHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct CheckboxRow: View {
    let label: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 10) {
                // Terminal-style checkbox: [✓] / [ ]
                Text(isOn ? "[✓]" : "[ ]")
                    .font(Theme.body)
                    .foregroundColor(isOn ? Theme.accent : Theme.textDim)
                Text(label)
                    .font(Theme.small)
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(hovering ? Theme.bgRowHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
