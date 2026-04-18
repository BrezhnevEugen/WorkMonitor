import Combine
import Foundation

/// Lightweight version-check via GitHub Releases API.
///
/// Uses only stdlib/Foundation — no third-party code. Fires a single HTTPS GET
/// to `/releases/latest`, parses `tag_name`, compares with the bundle version.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case available(latest: String, releaseURL: URL, current: String)
        case failed(message: String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheckedAt: Date?

    private let releasesAPI = URL(string: "https://api.github.com/repos/BrezhnevEugen/WorkMonitor/releases/latest")!
    private let keyLastCheck = "WorkMonitor.lastUpdateCheckAt"
    /// Autocheck waits this long between attempts.
    private let autocheckCooldown: TimeInterval = 24 * 3600

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    private init() {
        if let ts = UserDefaults.standard.object(forKey: keyLastCheck) as? TimeInterval {
            lastCheckedAt = Date(timeIntervalSince1970: ts)
        }
    }

    /// User-triggered immediate check. Flips status.checking → upToDate/available/failed.
    func checkNow() {
        status = .checking
        Task { await runCheck() }
    }

    /// Autocheck: fires only if the user enabled it AND cooldown has elapsed.
    func checkIfDue() {
        guard AppSettings.shared.autoCheckUpdates else { return }
        let stale = lastCheckedAt.map { Date().timeIntervalSince($0) >= autocheckCooldown } ?? true
        guard stale else { return }
        Task { await runCheck(silent: true) }
    }

    // MARK: - Network

    private func runCheck(silent: Bool = false) async {
        do {
            var req = URLRequest(url: releasesAPI)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("WorkMonitor/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "UpdateChecker", code: -1, userInfo: [NSLocalizedDescriptionKey: "no http response"])
            }
            guard http.statusCode == 200 else {
                throw NSError(domain: "UpdateChecker", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }

            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard
                let tag = obj["tag_name"] as? String,
                let urlStr = obj["html_url"] as? String,
                let url = URL(string: urlStr)
            else {
                throw NSError(domain: "UpdateChecker", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "malformed response"])
            }

            let latest = Self.normalize(tag)
            let current = currentVersion
            let now = Date()

            self.lastCheckedAt = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: keyLastCheck)

            if Self.isNewer(latest, than: current) {
                self.status = .available(latest: latest, releaseURL: url, current: current)
            } else {
                self.status = .upToDate(current: current)
            }
        } catch {
            // Silent runs (autocheck) shouldn't surface an error UI — just leave status as-is.
            if !silent {
                self.status = .failed(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Version helpers

    /// Strips a leading `v`/`V` from a release tag ("v2.0.0" → "2.0.0").
    static func normalize(_ tag: String) -> String {
        var s = tag
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Purely numeric semver compare: ignores pre-release tags. Returns true if a > b.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let aParts = numericParts(a)
        let bParts = numericParts(b)
        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }

    private static func numericParts(_ v: String) -> [Int] {
        // drops anything after "-" or "+" (e.g. "2.0.0-beta.1" → "2.0.0")
        let core = v.split(whereSeparator: { "-+".contains($0) }).first.map(String.init) ?? v
        return core.split(separator: ".").compactMap { Int($0) }
    }
}
