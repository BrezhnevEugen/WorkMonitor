import AppKit
import SwiftUI
import WorkMonitorCore

/// Floating panel that shows top memory-consuming processes.
/// Appears to the right of the main popover.
@MainActor
final class ProcessesPanel {
    static let shared = ProcessesPanel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let panelWidth: CGFloat = 372
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
        let root = AnyView(
            ProcessesDetailView(viewModel: viewModel)
                .environmentObject(LocalizationManager.shared)
        )
        let hosting = NSHostingView(rootView: root)
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
        hostingView?.rootView = AnyView(
            ProcessesDetailView(viewModel: viewModel)
                .environmentObject(LocalizationManager.shared)
        )
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
    @EnvironmentObject private var loc: LocalizationManager
    @State private var systemExpanded: Bool = false
    @State private var userExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "memorychip")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(loc.tr("procs_title"))
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { viewModel.onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Sortable column headers (widths match ProcessRow)
            HStack(spacing: 0) {
                Text("#")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)

                SortableHeader(title: loc.tr("procs_col_process"), field: .name, current: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort(.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)

                SortableHeader(title: loc.tr("procs_col_memory"), field: .memory, current: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort(.memory)
                }
                .frame(width: 68, alignment: .trailing)

                SortableHeader(title: loc.tr("procs_col_percent"), field: .percent, current: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort(.percent)
                }
                .frame(width: 38, alignment: .trailing)

                Spacer().frame(width: 28)
            }
            .font(.caption2)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            // Process list with collapsible sections
            ScrollView {
                LazyVStack(spacing: 0) {
                    // System section - collapsed by default
                    if !viewModel.systemProcesses.isEmpty {
                        ProcessSectionHeader(
                            title: loc.tr("procs_section_system"),
                            icon: "gearshape.fill",
                            totalMB: viewModel.systemProcesses.reduce(0) { $0 + $1.memoryMB },
                            count: viewModel.systemProcesses.count,
                            isExpanded: $systemExpanded
                        )

                        if systemExpanded {
                            ForEach(Array(viewModel.systemProcesses.enumerated()), id: \.element.id) { index, proc in
                                ProcessRow(index: index + 1, process: proc, onKill: nil)

                                if index < viewModel.systemProcesses.count - 1 {
                                    Divider().opacity(0.3).padding(.horizontal, 14)
                                }
                            }
                        }
                    }

                    // User section - expanded by default
                    if !viewModel.userProcesses.isEmpty {
                        ProcessSectionHeader(
                            title: loc.tr("procs_section_user"),
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
                                    Divider().opacity(0.3).padding(.horizontal, 14)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer with memory breakdown
            VStack(alignment: .leading, spacing: 5) {
                let trackedGB = viewModel.processes.reduce(0.0) { $0 + $1.memoryMB } / 1024

                HStack {
                    Text(loc.tr("procs_listed_in_table"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(loc.formatGigabytesOneDecimal(trackedGB))
                        .font(.caption2.monospaced())
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                HStack {
                    Text(loc.tr("procs_wired_kernel"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(loc.formatGigabytesOneDecimal(viewModel.wiredGB))
                        .font(.caption2.monospaced())
                        .foregroundColor(.primary)
                }

                HStack {
                    Text(loc.tr("procs_compressed"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(loc.formatGigabytesOneDecimal(viewModel.compressedGB))
                        .font(.caption2.monospaced())
                        .foregroundColor(.primary)
                }

                Divider().opacity(0.25)

                HStack {
                    Text(loc.tr("procs_total_used"))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(loc.formatRamUsedTotalLine(used: viewModel.usedGB, total: viewModel.totalGB))
                        .font(.caption2.monospaced())
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                let gap = viewModel.usedGB - trackedGB - viewModel.wiredGB
                if gap > 0.5 {
                    Text(String(format: loc.tr("procs_footer_gap_format"), gap))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 372, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
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
                        .font(.caption2.weight(.bold))
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
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text(verbatim: "(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
                Text(loc.formatMegabytesOrGigabytes(totalMB))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.06))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let index: Int
    let process: ProcessMemoryInfo
    var onKill: (() -> Void)?
    @EnvironmentObject private var loc: LocalizationManager
    @State private var isHovered = false

    private let miniBarHeight: CGFloat = 4

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(verbatim: String(format: "%2d", index))
                .font(.caption2.monospaced())
                .foregroundColor(.secondary.opacity(0.65))
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(process.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(process.name)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: miniBarHeight)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor.opacity(0.9))
                            .frame(width: max(0, geo.size.width * min(process.memoryPercent / 100, 1.0)), height: miniBarHeight)
                    }
                }
                .frame(height: miniBarHeight)
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(loc.formatMegabytesOrGigabytes(process.memoryMB))
                .font(.caption2.monospaced())
                .foregroundColor(.primary)
                .frame(width: 68, alignment: .trailing)

            Text(String(format: "%.1f", process.memoryPercent))
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)

            // Kill button - only for user processes (onKill != nil)
            if let killAction = onKill {
                Button(action: { killAction() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var barColor: Color {
        if process.memoryMB >= 2048 { return .red }
        if process.memoryMB >= 512 { return .orange }
        return .blue
    }
}
