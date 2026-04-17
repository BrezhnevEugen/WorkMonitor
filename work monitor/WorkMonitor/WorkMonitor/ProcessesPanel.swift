import AppKit
import SwiftUI

/// Floating panel that shows top memory-consuming processes.
/// Appears to the right of the main popover.
@MainActor
final class ProcessesPanel {
    static let shared = ProcessesPanel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ProcessesDetailView>?
    private let panelWidth: CGFloat = 340
    private let panelHeight: CGFloat = 560

    private init() {}

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func containsPoint(_ point: NSPoint) -> Bool {
        guard let panel = panel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    func toggle(processes: [ProcessMemoryInfo], memory: MemoryInfo) {
        if isVisible {
            close()
        } else {
            show(processes: processes, memory: memory)
        }
    }

    func show(processes: [ProcessMemoryInfo], memory: MemoryInfo) {
        if panel != nil {
            updateContent(processes: processes, memory: memory)
            panel?.orderFront(nil)
            return
        }

        let viewModel = ProcessesViewModel(processes: processes, totalGB: memory.totalGB, wiredGB: memory.wiredGB, compressedGB: memory.compressedGB, appMemoryGB: memory.appMemoryGB, usedGB: memory.usedGB, onClose: { [weak self] in self?.close() })
        let view = ProcessesDetailView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: view)
        hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        // Don't steal focus from popover
        panel.becomesKeyOnlyIfNeeded = true

        positionPanel(panel)
        panel.orderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    func update(processes: [ProcessMemoryInfo], memory: MemoryInfo) {
        guard isVisible else { return }
        updateContent(processes: processes, memory: memory)
    }

    private func updateContent(processes: [ProcessMemoryInfo], memory: MemoryInfo) {
        let viewModel = ProcessesViewModel(processes: processes, totalGB: memory.totalGB, wiredGB: memory.wiredGB, compressedGB: memory.compressedGB, appMemoryGB: memory.appMemoryGB, usedGB: memory.usedGB, onClose: { [weak self] in self?.close() })
        hostingView?.rootView = ProcessesDetailView(viewModel: viewModel)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let popoverWindow = NSApp.windows.first { window in
            window != panel && window.isVisible && window.className.contains("Popover")
        }

        if let popover = popoverWindow {
            let popFrame = popover.frame
            let x = popFrame.maxX + 8
            let y = popFrame.maxY - panelHeight
            panel.setFrameOrigin(NSPoint(x: x, y: max(y, screen.visibleFrame.minY)))
        } else {
            let x = screen.visibleFrame.maxX - panelWidth - 20
            let y = screen.visibleFrame.maxY - panelHeight - 10
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ProcessesViewModel: ObservableObject {
    @Published var processes: [ProcessMemoryInfo]
    @Published var sortBy: SortField = .memory
    @Published var sortAscending: Bool = false
    let totalGB: Double
    let wiredGB: Double
    let compressedGB: Double
    let appMemoryGB: Double
    let usedGB: Double
    var onClose: (() -> Void)?

    enum SortField {
        case name, memory, percent
    }

    var systemProcesses: [ProcessMemoryInfo] {
        applySorting(processes.filter { $0.isSystem })
    }

    var userProcesses: [ProcessMemoryInfo] {
        applySorting(processes.filter { !$0.isSystem })
    }

    private func applySorting(_ list: [ProcessMemoryInfo]) -> [ProcessMemoryInfo] {
        let result: [ProcessMemoryInfo]
        switch sortBy {
        case .name:
            result = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .memory:
            result = list.sorted { $0.memoryMB > $1.memoryMB }
        case .percent:
            result = list.sorted { $0.memoryPercent > $1.memoryPercent }
        }
        return sortAscending ? result.reversed() : result
    }

    init(processes: [ProcessMemoryInfo], totalGB: Double, wiredGB: Double = 0, compressedGB: Double = 0, appMemoryGB: Double = 0, usedGB: Double = 0, onClose: (() -> Void)?) {
        self.processes = processes
        self.totalGB = totalGB
        self.wiredGB = wiredGB
        self.compressedGB = compressedGB
        self.appMemoryGB = appMemoryGB
        self.usedGB = usedGB
        self.onClose = onClose
    }

    func toggleSort(_ field: SortField) {
        if sortBy == field {
            sortAscending.toggle()
        } else {
            sortBy = field
            sortAscending = false
        }
    }

    func killProcess(_ process: ProcessMemoryInfo) {
        let pid = process.pid
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/kill")
            proc.arguments = ["-9", String(pid)]
            try? proc.run()
            proc.waitUntilExit()
        }
        // Remove from list immediately
        processes.removeAll { $0.pid == pid }
    }
}

// MARK: - Detail View

struct ProcessesDetailView: View {
    @ObservedObject var viewModel: ProcessesViewModel
    @State private var systemExpanded: Bool = false
    @State private var userExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "memorychip")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("Top Processes")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { viewModel.onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Sortable column headers
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 22, alignment: .leading)

                SortableHeader(title: "Process", field: .name, current: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort(.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SortableHeader(title: "Memory", field: .memory, current: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort(.memory)
                }
                .frame(width: 65, alignment: .trailing)

                SortableHeader(title: "%", field: .percent, current: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort(.percent)
                }
                .frame(width: 35, alignment: .trailing)

                // Space for kill button
                Spacer().frame(width: 28)
            }
            .font(.caption2)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()

            // Process list with collapsible sections
            ScrollView {
                LazyVStack(spacing: 0) {
                    // System section — collapsed by default
                    if !viewModel.systemProcesses.isEmpty {
                        ProcessSectionHeader(
                            title: "System",
                            icon: "gearshape.fill",
                            totalMB: viewModel.systemProcesses.reduce(0) { $0 + $1.memoryMB },
                            count: viewModel.systemProcesses.count,
                            isExpanded: $systemExpanded
                        )

                        if systemExpanded {
                            ForEach(Array(viewModel.systemProcesses.enumerated()), id: \.element.id) { index, proc in
                                ProcessRow(index: index + 1, process: proc, onKill: nil)

                                if index < viewModel.systemProcesses.count - 1 {
                                    Divider().opacity(0.3).padding(.horizontal, 16)
                                }
                            }
                        }
                    }

                    // User section — expanded by default
                    if !viewModel.userProcesses.isEmpty {
                        ProcessSectionHeader(
                            title: "User",
                            icon: "person.fill",
                            totalMB: viewModel.userProcesses.reduce(0) { $0 + $1.memoryMB },
                            count: viewModel.userProcesses.count,
                            isExpanded: $userExpanded
                        )

                        if userExpanded {
                            ForEach(Array(viewModel.userProcesses.enumerated()), id: \.element.id) { index, proc in
                                ProcessRow(index: index + 1, process: proc, onKill: {
                                    viewModel.killProcess(proc)
                                })

                                if index < viewModel.userProcesses.count - 1 {
                                    Divider().opacity(0.3).padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer with memory breakdown
            VStack(spacing: 6) {
                let trackedGB = viewModel.processes.reduce(0.0) { $0 + $1.memoryMB } / 1024

                HStack {
                    Text("Отслеживается:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f GB", trackedGB))
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Wired (ядро):")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f GB", viewModel.wiredGB))
                        .font(.system(.caption2, design: .monospaced))
                }

                HStack {
                    Text("Compressed:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f GB", viewModel.compressedGB))
                        .font(.system(.caption2, design: .monospaced))
                }

                Divider().opacity(0.3)

                HStack {
                    Text("Всего используется:")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f / %.0f GB", viewModel.usedGB, viewModel.totalGB))
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.medium)
                }

                let gap = viewModel.usedGB - trackedGB - viewModel.wiredGB
                if gap > 0.5 {
                    Text("Δ \(String(format: "%.1f", gap)) GB — кэши, буферы, GPU, мелкие процессы")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Sortable Header

struct SortableHeader: View {
    let title: String
    let field: ProcessesViewModel.SortField
    let current: ProcessesViewModel.SortField
    let ascending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                    .fontWeight(field == current ? .bold : .semibold)
                    .foregroundColor(field == current ? .accentColor : .secondary)
                if field == current {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

// MARK: - Section Header

struct ProcessSectionHeader: View {
    let title: String
    let icon: String
    let totalMB: Double
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text(verbatim: "(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
                Text(formatMemory(totalMB))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let index: Int
    let process: ProcessMemoryInfo
    var onKill: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "\(index)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor)
                            .frame(width: max(0, geo.size.width * min(process.memoryPercent / 100, 1.0)), height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatMemory(process.memoryMB))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 65, alignment: .trailing)

            Text(String(format: "%.1f", process.memoryPercent))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)

            // Kill button — only for user processes (onKill != nil)
            if let killAction = onKill {
                Button(action: { killAction() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isHovered ? .red : .clear)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(width: 28)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            } else {
                Spacer().frame(width: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(isHovered ? Color.gray.opacity(0.08) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var barColor: Color {
        if process.memoryMB >= 2048 { return .red }
        if process.memoryMB >= 512 { return .orange }
        return .blue
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}
