import SwiftUI
import AppKit

@main
struct WorkMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window - tray-only app
        Settings { EmptyView() }
    }
}
