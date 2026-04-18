import AppKit
import Combine
import SwiftUI

// MARK: - Theme palette

/// All colour tokens used by the UI. Swapping the current palette re-themes the whole app.
struct ThemePalette: Equatable {
    let bgPopover: Color
    let bgPopoverElev: Color
    let bgRowHover: Color
    let border: Color
    let borderStrong: Color

    let text: Color
    let textDim: Color
    let textMute: Color

    let accent: Color
    let accentDim: Color
    let amber: Color
    let red: Color
    let blue: Color
    let purple: Color

    let miniBarTrack: Color
    let sectionCountBg: Color

    /// Drives `.preferredColorScheme(...)` on the popover root.
    let colorScheme: ColorScheme
}

// MARK: - Available themes

enum ThemeKind: String, CaseIterable, Identifiable {
    /// Follows macOS system appearance — dark terminal when system is dark,
    /// light minimal when system is light. Updates live.
    case auto
    case darkTerminal
    case lightMinimal
    case midnightBlue

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .auto:          return "theme_auto"
        case .darkTerminal:  return "theme_dark_terminal"
        case .lightMinimal:  return "theme_light_minimal"
        case .midnightBlue:  return "theme_midnight_blue"
        }
    }

    /// Three swatches shown next to the name in the theme picker.
    /// For `.auto` — shows the currently resolved palette (live updates).
    var previewColors: [Color] {
        let p = resolvedPalette()
        return [p.bgPopover, p.accent, p.text]
    }

    /// Palette to use right now: for explicit kinds it's fixed, for `.auto`
    /// it reflects the current system appearance.
    func resolvedPalette() -> ThemePalette {
        switch self {
        case .auto:
            return ThemeKind.systemIsDark()
                ? ThemeKind.darkTerminal.explicitPalette
                : ThemeKind.lightMinimal.explicitPalette
        case .darkTerminal, .lightMinimal, .midnightBlue:
            return explicitPalette
        }
    }

    /// True when the system is in Dark Mode (or effective appearance best-matches darkAqua).
    static func systemIsDark() -> Bool {
        guard let app = NSApplication.shared.windows.first?.effectiveAppearance ?? NSApp?.effectiveAppearance else {
            // Fallback: query via global API before any window exists.
            let name = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return name == "Dark"
        }
        let match = app.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua
    }

    private var explicitPalette: ThemePalette {
        switch self {
        case .auto:
            // Never reached in practice — `.auto` goes through `resolvedPalette()`.
            return ThemeKind.darkTerminal.explicitPalette
        case .darkTerminal:
            return ThemePalette(
                bgPopover:      Color(hex: 0x0D0F11),
                bgPopoverElev:  Color(hex: 0x14171A),
                bgRowHover:     Color(hex: 0x1A1E22),
                border:         Color(hex: 0x23272C),
                borderStrong:   Color(hex: 0x2D333A),
                text:           Color(hex: 0xE6E6E6),
                textDim:        Color(hex: 0x8A8F98),
                textMute:       Color(hex: 0x5A6069),
                accent:         Color(hex: 0x4ADE80),
                accentDim:      Color(hex: 0x2F8A50),
                amber:          Color(hex: 0xFBBF24),
                red:            Color(hex: 0xEF4444),
                blue:           Color(hex: 0x60A5FA),
                purple:         Color(hex: 0xA78BFA),
                miniBarTrack:   Color(hex: 0x1C2024),
                sectionCountBg: Color(hex: 0x1C2024),
                colorScheme:    .dark
            )

        case .lightMinimal:
            return ThemePalette(
                bgPopover:      Color(hex: 0xFAFAF9),
                bgPopoverElev:  Color(hex: 0xF3F3F1),
                bgRowHover:     Color(hex: 0xECECE9),
                border:         Color(hex: 0xE2E2DF),
                borderStrong:   Color(hex: 0xCFCFCB),
                text:           Color(hex: 0x1C1F22),
                textDim:        Color(hex: 0x5F6368),
                textMute:       Color(hex: 0x9A9EA3),
                accent:         Color(hex: 0x10B981),
                accentDim:      Color(hex: 0x047857),
                amber:          Color(hex: 0xB45309),
                red:            Color(hex: 0xDC2626),
                blue:           Color(hex: 0x2563EB),
                purple:         Color(hex: 0x7C3AED),
                miniBarTrack:   Color(hex: 0xE2E2DF),
                sectionCountBg: Color(hex: 0xE2E2DF),
                colorScheme:    .light
            )

        case .midnightBlue:
            return ThemePalette(
                bgPopover:      Color(hex: 0x0A1120),
                bgPopoverElev:  Color(hex: 0x121A2C),
                bgRowHover:     Color(hex: 0x182238),
                border:         Color(hex: 0x1E2A42),
                borderStrong:   Color(hex: 0x2A3A58),
                text:           Color(hex: 0xE5EAF3),
                textDim:        Color(hex: 0x8490AA),
                textMute:       Color(hex: 0x566078),
                accent:         Color(hex: 0x60A5FA),
                accentDim:      Color(hex: 0x3B82F6),
                amber:          Color(hex: 0xF59E0B),
                red:            Color(hex: 0xF87171),
                blue:           Color(hex: 0x93C5FD),
                purple:         Color(hex: 0xC4B5FD),
                miniBarTrack:   Color(hex: 0x1A243C),
                sectionCountBg: Color(hex: 0x1A243C),
                colorScheme:    .dark
            )
        }
    }
}

// MARK: - Theme manager

/// Holds the active `ThemeKind`, persists it, and publishes changes so the SwiftUI tree
/// can re-read `Theme.*` static accessors.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let defaultsKey = "WorkMonitor.themeKind"

    @Published var kind: ThemeKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: defaultsKey) }
    }

    /// Currently active palette. For `.auto` this reflects the live macOS appearance.
    var palette: ThemePalette { kind.resolvedPalette() }

    private var systemAppearanceObserver: NSObjectProtocol?

    private init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ThemeKind.auto.rawValue
        kind = ThemeKind(rawValue: raw) ?? .auto

        // Re-publish when the user flips macOS dark/light (only relevant while in .auto).
        systemAppearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.kind == .auto {
                // Kick SwiftUI to redraw by touching the @Published property.
                self.objectWillChange.send()
            }
        }
    }

    deinit {
        if let obs = systemAppearanceObserver {
            DistributedNotificationCenter.default.removeObserver(obs)
        }
    }
}

// MARK: - Theme facade

/// Static-access facade. Reads colours from `ThemeManager.shared.palette` so every
/// view stays code-stable while the user swaps themes at runtime. Fonts are theme-
/// independent and kept as constants.
enum Theme {
    // Colours (dynamic)
    static var bgPopover: Color      { ThemeManager.shared.palette.bgPopover }
    static var bgPopoverElev: Color  { ThemeManager.shared.palette.bgPopoverElev }
    static var bgRowHover: Color     { ThemeManager.shared.palette.bgRowHover }
    static var border: Color         { ThemeManager.shared.palette.border }
    static var borderStrong: Color   { ThemeManager.shared.palette.borderStrong }

    static var text: Color           { ThemeManager.shared.palette.text }
    static var textDim: Color        { ThemeManager.shared.palette.textDim }
    static var textMute: Color       { ThemeManager.shared.palette.textMute }

    static var accent: Color         { ThemeManager.shared.palette.accent }
    static var accentDim: Color      { ThemeManager.shared.palette.accentDim }
    static var amber: Color          { ThemeManager.shared.palette.amber }
    static var red: Color            { ThemeManager.shared.palette.red }
    static var blue: Color           { ThemeManager.shared.palette.blue }
    static var purple: Color         { ThemeManager.shared.palette.purple }

    static var miniBarTrack: Color   { ThemeManager.shared.palette.miniBarTrack }
    static var sectionCountBg: Color { ThemeManager.shared.palette.sectionCountBg }

    // Fonts (static)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let body      = mono(12)
    static let bodyBold  = mono(12, weight: .semibold)
    static let small     = mono(11)
    static let tiny      = mono(10)
    static let title     = mono(13, weight: .semibold)
    static let metric    = mono(14, weight: .medium)
    static let sectionCaption = mono(11, weight: .medium)
}

// MARK: - Helpers

extension Color {
    /// Compact init from hex literal (e.g. `0x4ADE80`).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - View modifiers

struct HoverBackground: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Theme.bgRowHover : Color.clear)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverBackground() -> some View { modifier(HoverBackground()) }
}

struct RevealOnRowHover<Child: View>: View {
    let hovering: Bool
    @ViewBuilder let child: () -> Child
    var body: some View {
        child()
            .opacity(hovering ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}
