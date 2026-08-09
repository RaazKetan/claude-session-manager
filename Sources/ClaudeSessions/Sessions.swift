import Foundation

// MARK: - Model

struct Session: Identifiable {
    let id: String
    let cwd: String
    let title: String      // auto-derived from the first usable prompt
    let name: String?      // user-chosen label, wins over title
    let created: Date
    let modified: Date
    let exists: Bool

    var label: String { name ?? title }
    var project: String { (cwd as NSString).lastPathComponent }
}

/// User-chosen labels, keyed by session id.
// ponytail: one JSON file in Application Support — the widget reads the same path, so no App Group entitlement is needed.
enum Names {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeSessions/names.json")

    static func load() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }

    static func set(_ name: String, for id: String) {
        var all = load()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        all[id] = trimmed.isEmpty ? nil : trimmed   // clearing the field restores the auto summary
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: url)
    }
}

/// First line of a user message, or nil if it's not worth showing as a title.
// ponytail: opening prompts are often junk — image-only, a slash command, a giant paste. Caller falls through to the next one.
func usableTitle(_ obj: [String: Any]) -> String? {
    let content = (obj["message"] as? [String: Any])?["content"]
    var text = ""
    if let s = content as? String {
        text = s
    } else if let blocks = content as? [[String: Any]] {
        text = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
    }
    let junk = CharacterSet(charactersIn: "─━—-=_* ").union(.whitespacesAndNewlines)
    guard let line = text.split(separator: "\n").first?.trimmingCharacters(in: junk), line.count >= 3 else { return nil }
    guard !"<[/".contains(line.first!), !line.hasPrefix("Caveat:") else { return nil }
    guard line.count < 2000 else { return nil }  // a dumped file or stack trace, not a prompt
    return line.count > 160 ? line.prefix(160) + "…" : line
}

/// Scans ~/.claude/projects/*/*.jsonl.
// ponytail: reads only the first 64KB of each file — cwd and the first user prompt are always near the top.
func loadSessions() -> [Session] {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let names = Names.load()

    var out: [Session] = []
    for dir in dirs {
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "jsonl" {
            guard let head = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? head.close() }
            guard let chunk = try? head.read(upToCount: 64 * 1024), let text = String(data: chunk, encoding: .utf8) else { continue }

            var cwd: String?, sid: String?, created = Date.distantPast, title: String?
            for line in text.split(separator: "\n") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      obj["type"] as? String == "user",
                      let c = obj["cwd"] as? String,
                      let s = obj["sessionId"] as? String else { continue }

                if cwd == nil {  // identity + creation time come from the first message, whatever it says
                    (cwd, sid) = (c, s)
                    created = (obj["timestamp"] as? String).flatMap(iso.date(from:)) ?? .distantPast
                }
                title = usableTitle(obj)
                if title != nil { break }
            }
            guard let cwd, let sid else { continue }

            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created
            out.append(Session(id: sid, cwd: cwd, title: title ?? "(no prompt)", name: names[sid],
                               created: created, modified: modified,
                               exists: fm.fileExists(atPath: cwd)))
        }
    }
    return out.sorted { $0.modified > $1.modified }
}
