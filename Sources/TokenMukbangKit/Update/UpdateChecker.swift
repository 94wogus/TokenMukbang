import Foundation

/// Compares the running version against the latest GitHub release (I1).
/// The actual signed/notarized DMG + Homebrew cask delivery is ADR-0010; this is
/// just the version-comparison logic (pure → testable).
public enum UpdateChecker {
    /// GitHub `/releases/latest` API URL for the repo.
    public static func latestReleaseURL(owner: String, repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    /// Parse the version from a `/releases/latest` JSON payload (`"tag_name": "v1.2.3"`).
    public static func latestVersion(fromReleaseJSON json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String
        else { return nil }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Whether `latest` is a newer semver than `current` (numeric components).
    public static func isNewer(latest: String, current: String) -> Bool {
        let l = components(latest), c = components(current)
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
