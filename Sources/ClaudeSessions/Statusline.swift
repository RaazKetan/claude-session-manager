import Foundation

/// Installs the Spotify statusline plugin and points Claude Code at it, once, on first launch.
// ponytail: shells out to `claude plugin install` instead of reimplementing the plugin system.
//           A marker file — written even on failure — means this never runs twice.
enum Statusline {
    static let marketplace = "RaazKetan/claude-code-spotify"
    static let plugin = "spotify-statusline@raazketan"

    static let supportDir = Names.url.deletingLastPathComponent()
    static let marker = supportDir.appendingPathComponent("statusline-installed")
    static let settings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    static func installIfNeeded() {
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        DispatchQueue.global(qos: .utility).async {
            defer {
                try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
                try? Data().write(to: marker)
            }
            // No Claude Code on this machine — nothing to configure.
            guard let claude = sh("command -v claude"), !claude.isEmpty else { return }
            _ = sh("claude plugin marketplace add \(marketplace)")
            _ = sh("claude plugin install \(plugin)")
            if let script = installedScript() { pointSettings(at: script) }
        }
    }

    /// Newest installed copy of the plugin's statusline.py, whatever version resolved.
    private static func installedScript() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/cache/raazketan/spotify-statusline")
        let versions = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return versions
            .map { $0.appendingPathComponent("statusline.py") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path.compare($1.path, options: .numeric) == .orderedAscending }
            .last
    }

    private static func pointSettings(at script: URL) {
        let command = "python3 \"\(script.path)\""
        var json = (try? Data(contentsOf: settings))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        // Already pointing at this script — don't rewrite the file for nothing.
        if let existing = json["statusLine"] as? [String: Any], existing["command"] as? String == command { return }

        // Never clobber an existing statusline without leaving a way back.
        if json["statusLine"] != nil, let current = try? Data(contentsOf: settings) {
            try? current.write(to: settings.appendingPathExtension("claude-sessions-backup"))
        }

        json["statusLine"] = ["type": "command", "command": command, "refreshInterval": 1]
        guard let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? out.write(to: settings, options: .atomic)
    }

    @discardableResult
    private static func sh(_ command: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]          // login shell, so PATH matches the user's terminal
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
