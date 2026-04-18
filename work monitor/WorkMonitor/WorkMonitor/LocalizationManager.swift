import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Keys into Localizable.strings for the picker row label (localized per current UI language).
    var pickerTitleKey: String {
        switch self {
        case .system: return "language_system"
        case .english: return "language_english"
        case .russian: return "language_russian"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let defaultsKey = "WorkMonitor.appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// Localizations ship inside the app bundle at `Contents/Resources/*.lproj` (see `build.sh`).
    func bundleForStrings() -> Bundle {
        let root = Bundle.main
        guard root.path(forResource: "en", ofType: "lproj") != nil else {
            return root
        }
        switch language {
        case .system:
            return root
        case .english:
            return Self.lprojBundle("en", in: root) ?? root
        case .russian:
            return Self.lprojBundle("ru", in: root) ?? root
        }
    }

    func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundleForStrings(), value: key, comment: "")
    }

    private static func lprojBundle(_ code: String, in root: Bundle) -> Bundle? {
        guard let path = root.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Storage units (aligned with Russian macOS / Activity Monitor: ГБ, МБ)

    private var useRussianStyleUnits: Bool {
        switch language {
        case .russian: return true
        case .english: return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("ru") == true
        }
    }

    private var unitGB: String { useRussianStyleUnits ? "ГБ" : "GB" }
    private var unitMB: String { useRussianStyleUnits ? "МБ" : "MB" }

    func formatGigabytesOneDecimal(_ gigabytes: Double) -> String {
        String(format: "%.1f %@", gigabytes, unitGB)
    }

    func formatRamUsedTotalLine(used: Double, total: Double) -> String {
        String(format: "%.1f / %.0f %@", used, total, unitGB)
    }

    func formatSwapUsedTotalLine(used: Double, total: Double) -> String {
        String(format: "%.1f / %.1f %@", used, total, unitGB)
    }

    func formatMegabytesOrGigabytes(_ megabytes: Double) -> String {
        if megabytes >= 1024 {
            return String(format: "%.1f %@", megabytes / 1024, unitGB)
        }
        return String(format: "%.0f %@", megabytes, unitMB)
    }

    // MARK: - v2 formatters

    /// Formats a bytes-per-second rate into a compact string: `1.2 MB/s` / `842 KB/s` / `0 B/s`.
    func formatNetworkRate(_ bytesPerSec: Double) -> String {
        let bps = max(0, bytesPerSec)
        if bps >= 1_048_576 {
            return String(format: "%.1f MB/s", bps / 1_048_576)
        } else if bps >= 1_024 {
            return String(format: "%.0f KB/s", bps / 1_024)
        }
        return String(format: "%.0f B/s", bps)
    }

    /// Relative "updated Xs ago" indicator for the header.
    func formatRelativeUpdated(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 2 { return tr("updated_now") }
        if secs < 60 { return String(format: tr("updated_secs_ago_format"), secs) }
        let mins = secs / 60
        return String(format: tr("updated_mins_ago_format"), mins)
    }
}
