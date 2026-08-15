import Foundation

/// Tells you when a newer release exists. Nothing is downloaded or installed — Homebrew owns
/// that — and no information about you is sent. It is one unauthenticated GET for a tag name.
// ponytail: checked once per launch and cached. A menu bar app that hits the API every time the
//           panel opens is rude to GitHub and pointless: releases don't appear that often.
enum Update {
    static let repo = "RaazKetan/claude-session-manager"
    static let upgradeCommand = "brew upgrade --cask claude-sessions"

    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static var cached: String??

    /// The newer version's tag, or nil when up to date, offline, or running an unreleased build.
    static func newerVersion() async -> String? {
        if let cached { return cached }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String
        else { return nil }   // don't cache failures; the next launch can retry

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let result = isNewer(latest, than: current) ? latest : nil
        cached = result
        return result
    }

    /// Numeric compare, so 1.10.0 beats 1.9.0 rather than losing a string comparison.
    static func isNewer(_ candidate: String, than existing: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = existing.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
