import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var monitor: SystemMonitor!
    private var popoverTimer: Timer?        // fast poll while popover is open
    private var backgroundTimer: Timer?     // slow poll to keep tray label fresh
    private var clickOutsideMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — tray-only app
        NSApp.setActivationPolicy(.accessory)

        monitor = SystemMonitor()

        // Popover: new 420x600 dark popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 600)
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(monitor: monitor)
                .environmentObject(LocalizationManager.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(ThemeManager.shared)
                .environmentObject(UpdateChecker.shared)
        )

        // Status bar item with monochrome template icon + adaptive count
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imagePosition = .imageLeading
        }
        updateTrayLabel()

        // Keep tray label in sync with monitor state
        monitor.$ports
            .combineLatest(monitor.$memory, monitor.$dockerAvailable, monitor.$containers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in self?.updateTrayLabel() }
            .store(in: &cancellables)

        // Background refresh — runs regardless of popover visibility, cadence from AppSettings.
        restartBackgroundTimer()

        // React to user changing the background cadence in Settings.
        AppSettings.shared.$backgroundRefreshSec
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartBackgroundTimer() }
            .store(in: &cancellables)

        // React to user changing the popover cadence (only effective while popover is open).
        AppSettings.shared.$popoverRefreshSec
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.popover.isShown else { return }
                self.restartPopoverTimer()
            }
            .store(in: &cancellables)

        monitor.refresh()

        // Daily autocheck for app updates (only when user enabled it).
        UpdateChecker.shared.checkIfDue()
    }

    // MARK: - Timer helpers

    private func restartBackgroundTimer() {
        backgroundTimer?.invalidate()
        let interval = max(5, AppSettings.shared.backgroundRefreshSec)
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.monitor.refresh() }
        }
    }

    private func restartPopoverTimer() {
        popoverTimer?.invalidate()
        let interval = max(1, AppSettings.shared.popoverRefreshSec)
        popoverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.monitor.refresh() }
        }
    }

    // MARK: - Tray label

    /// Monochrome tray icon — a template SF Symbol (system paints it for the current
    /// menu bar appearance) plus the port count as adaptive text in `.labelColor`.
    /// State is conveyed by the symbol shape, not colour.
    private func updateTrayLabel() {
        guard let button = statusItem?.button else { return }

        let portCount = monitor.ports.count
        let memPct = monitor.memory.usagePercent
        let dockerDown = !monitor.dockerAvailable
        let unhealthy = hasUnhealthyContainer

        // Semantic shape picked by state. All rendered as template (auto-inverts on light/dark menubar).
        let symbolName: String
        if memPct > 90 || (dockerDown && portCount == 0) {
            symbolName = "exclamationmark.circle.fill"     // critical
        } else if memPct > 75 || unhealthy {
            symbolName = "exclamationmark.triangle.fill"   // warning
        } else if portCount == 0 {
            symbolName = "circle"                          // idle (hollow)
        } else {
            symbolName = "circle.fill"                     // normal (solid)
        }

        let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Work Monitor")?
            .withSymbolConfiguration(cfg)
        image?.isTemplate = true    // ← macOS paints this in white on dark bar, black on light bar
        button.image = image

        // Count only when there's something to count; otherwise the icon alone is enough.
        let titleText = portCount > 0 ? " \(portCount)" : ""
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
        ]
        button.attributedTitle = NSAttributedString(string: titleText, attributes: attrs)
    }

    private var hasUnhealthyContainer: Bool {
        monitor.containers.contains { $0.status.lowercased().contains("unhealthy") }
    }

    // MARK: - Popover show/hide

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

        // Fast refresh while popover is open — cadence from AppSettings
        restartPopoverTimer()

        // Close on outside click
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let mouseLocation = NSEvent.mouseLocation
                let clickedPopover = self.popover.isShown && NSApp.windows.contains { window in
                    window.isVisible && window.frame.contains(mouseLocation)
                }
                if !clickedPopover { self.closeAll() }
            }
        }
    }

    private func closeAll() {
        popover.performClose(nil)
        popoverTimer?.invalidate()
        popoverTimer = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popoverTimer?.invalidate()
        popoverTimer = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
