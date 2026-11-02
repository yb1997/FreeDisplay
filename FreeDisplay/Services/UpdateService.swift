import Foundation
import AppKit

/// Checks for new releases on GitHub and surfaces the latest version info.
@MainActor
final class UpdateService: ObservableObject, @unchecked Sendable {
    static let shared = UpdateService()

    // Set these when the repo is published. Placeholder values disable the update check.
    private let repoOwner = "yb1997"
    private let repoName  = "FreeDisplay"

    // Current app bundle version (CFBundleShortVersionString)
    let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    @Published var latestVersion: String? = nil
    @Published var releaseURL: URL? = nil
    /// The release's FreeDisplay.dmg download, used by UpdateInstaller. nil when the release
    /// has no DMG attached (then only the release page can be offered).
    @Published var updateDMGURL: URL? = nil
    @Published var isChecking: Bool = false
    @Published var hasUpdate: Bool = false
    @Published var lastCheckDate: Date? = nil
    /// True when the last check couldn't reach GitHub or got an unusable reply.
    @Published var lastCheckFailed: Bool = false

    private init() {}

    // MARK: - Check for Updates

    /// Checks GitHub for the latest release. The automatic launch check runs at most once
    /// an hour; `force` (the Check for Updates button) always checks.
    func checkForUpdates(force: Bool = false) async {
        guard !repoOwner.isEmpty, repoOwner != "OWNER", !repoName.isEmpty else {
            // Repo not yet configured — silently skip update check
            return
        }
        if !force, let last = lastCheckDate, Date().timeIntervalSince(last) < 3600 { return }
        guard !isChecking else { return }
        isChecking = true
        lastCheckFailed = false
        defer { isChecking = false }

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // Repo may not exist yet, or rate-limited
                lastCheckFailed = true
                lastCheckDate = Date()
                return
            }
            let json: [String: Any]?
            do {
                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            } catch {
                #if DEBUG
                print("[UpdateService] JSON parse error: \(error)")
                #endif
                lastCheckFailed = true
                lastCheckDate = Date()
                return
            }
            if let tag = json?["tag_name"] as? String {
                let clean = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                latestVersion = clean
                releaseURL = (json?["html_url"] as? String).flatMap { URL(string: $0) }
                let assets = json?["assets"] as? [[String: Any]] ?? []
                updateDMGURL = assets
                    .first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
                    .flatMap { $0["browser_download_url"] as? String }
                    .flatMap { URL(string: $0) }
                hasUpdate = Self.isNewerVersion(clean, than: currentVersion)
            } else {
                lastCheckFailed = true
            }
            lastCheckDate = Date()
        } catch {
            // Network unavailable — the launch check stays quiet; the button shows it
            lastCheckFailed = true
            lastCheckDate = Date()
        }
    }

    // MARK: - Version Comparison

    nonisolated static func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents  = local.split(separator: ".").compactMap { Int($0) }
        let length = max(remoteComponents.count, localComponents.count)
        for i in 0..<length {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let l = i < localComponents.count  ? localComponents[i]  : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    // MARK: - Open Release Page

    func openReleasePage() {
        guard let url = releaseURL else { return }
        NSWorkspace.shared.open(url)
    }
}
