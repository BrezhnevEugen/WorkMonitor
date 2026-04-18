import Combine
import Foundation

/// User-tweakable app preferences persisted in `UserDefaults`.
/// Injected into SwiftUI via `.environmentObject(AppSettings.shared)` so any view
/// (e.g. DashboardView body / SettingsView toggles) re-renders on change.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Refresh interval presets

    /// Allowed values for the in-popover refresh cadence. Kept small so UI can render as chips.
    static let popoverRefreshPresets: [Double]    = [1, 2, 5, 10]
    /// Allowed values for the always-on background cadence (tray label freshness).
    static let backgroundRefreshPresets: [Double] = [15, 30, 60, 120]

    private let keyShowPorts         = "WorkMonitor.showPorts"
    private let keyShowDocker        = "WorkMonitor.showDocker"
    private let keyShowProcesses     = "WorkMonitor.showProcesses"
    private let keyGroupPortsByApp   = "WorkMonitor.groupPortsByApp"
    private let keyPopoverRefreshSec = "WorkMonitor.popoverRefreshSec"
    private let keyBgRefreshSec      = "WorkMonitor.backgroundRefreshSec"
    private let keyAutoCheckUpdates  = "WorkMonitor.autoCheckUpdates"

    @Published var showPorts: Bool {
        didSet { UserDefaults.standard.set(showPorts, forKey: keyShowPorts) }
    }
    @Published var showDocker: Bool {
        didSet { UserDefaults.standard.set(showDocker, forKey: keyShowDocker) }
    }
    @Published var showProcesses: Bool {
        didSet { UserDefaults.standard.set(showProcesses, forKey: keyShowProcesses) }
    }
    @Published var groupPortsByApp: Bool {
        didSet { UserDefaults.standard.set(groupPortsByApp, forKey: keyGroupPortsByApp) }
    }
    /// Refresh cadence while the popover is open (seconds).
    @Published var popoverRefreshSec: Double {
        didSet { UserDefaults.standard.set(popoverRefreshSec, forKey: keyPopoverRefreshSec) }
    }
    /// Always-on refresh cadence (seconds) — keeps tray label/count fresh.
    @Published var backgroundRefreshSec: Double {
        didSet { UserDefaults.standard.set(backgroundRefreshSec, forKey: keyBgRefreshSec) }
    }
    /// Automatic daily update check via GitHub Releases.
    @Published var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: keyAutoCheckUpdates) }
    }

    private init() {
        let d = UserDefaults.standard
        showPorts            = (d.object(forKey: keyShowPorts)         as? Bool)   ?? true
        showDocker           = (d.object(forKey: keyShowDocker)        as? Bool)   ?? true
        showProcesses        = (d.object(forKey: keyShowProcesses)     as? Bool)   ?? true
        groupPortsByApp      = (d.object(forKey: keyGroupPortsByApp)   as? Bool)   ?? true
        popoverRefreshSec    = (d.object(forKey: keyPopoverRefreshSec) as? Double) ?? 2
        backgroundRefreshSec = (d.object(forKey: keyBgRefreshSec)      as? Double) ?? 15
        autoCheckUpdates     = (d.object(forKey: keyAutoCheckUpdates)  as? Bool)   ?? true
    }
}
