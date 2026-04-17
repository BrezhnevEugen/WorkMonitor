import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var monitor: SystemMonitor!
    private var refreshTimer: Timer?
    private var clickOutsideMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — tray-only app
        NSApp.setActivationPolicy(.accessory)

        monitor = SystemMonitor()

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 480, height: 560)
        popover.behavior = .applicationDefined  // We manage closing ourselves
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(monitor: monitor)
        )

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gearshape.2.fill", accessibilityDescription: "Work Monitor")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closeAll()
        } else {
            openPopover(relativeTo: button)
        }
    }

    private func openPopover(relativeTo button: NSStatusBarButton) {
        monitor.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Start auto-refresh every 5 seconds
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.monitor.refresh()
                if ProcessesPanel.shared.isVisible {
                    ProcessesPanel.shared.update(
                        processes: self.monitor.topProcesses,
                        memory: self.monitor.memory
                    )
                }
            }
        }

        // Monitor clicks outside our windows to close everything
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let mouseLocation = NSEvent.mouseLocation
                let clickedPopover = self.popover.isShown && NSApp.windows.contains { window in
                    window.isVisible && window.frame.contains(mouseLocation)
                }
                let clickedPanel = ProcessesPanel.shared.isVisible && ProcessesPanel.shared.containsPoint(mouseLocation)

                if !clickedPopover && !clickedPanel {
                    self.closeAll()
                }
            }
        }
    }

    private func closeAll() {
        popover.performClose(nil)
        ProcessesPanel.shared.close()
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        ProcessesPanel.shared.close()
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
