import Foundation

// MARK: - Model

/// The coding agent a session belongs to. Each stores its transcripts differently and has
/// its own resume command, but a row is a row.
enum Agent: String, CaseIterable {
    case claude, codex

    var label: String { self == .claude ? "Claude" : "Codex" }
    var binary: String { rawValue }
    var installURL: String {
        self == .claude ? "https://claude.com/claude-code" : "https://developers.openai.com/codex/cli"
    }

    /// Resume command, minus the working directory.
    func resumeCommand(_ id: String, skipPermissions: Bool) -> String {
        switch self {
        case .claude: return "claude --resume \(id)" + (skipPermissions ? " --dangerously-skip-permissions" : "")
        case .codex:  return "codex resume \(id)"   // codex has its own approval flags; don't assume them
        }
    }
}

struct Session: Identifiable {
    /// The log file's path. Unique per row — the same session id can legitimately exist
    /// under two project folders, and SwiftUI needs the rows to be distinguishable.
    let id: String
    /// What the resume command takes. Shared between copies of the same conversation.
    let sessionID: String
    let agent: Agent
    let cwd: String
    let title: String      // auto-derived from the first usable prompt
    let name: String?      // user-chosen label, wins over title
    let created: Date
    let modified: Date
    let exists: Bool
    /// True when this is the only session in its folder, so a folder match identifies it.
    var aloneInFolder = false
    /// A `claude` is running right now with this session id on its command line.
    var isRunning = false

    /// Path with the home directory collapsed, the way a shell prompt shows it.
    var shortPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd == home ? "~" : cwd.replacingOccurrences(of: home + "/", with: "~/")
    }

    /// "3m ago" for today, "Yesterday", "Aug 9" beyond that.
    var when: String {
        let days = Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0
        if days == 0 {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: created, relativeTo: Date())
        }
        if days == 1 { return "Yesterday" }
        return created.formatted(.dateTime.day().month(.abbreviated))
    }

    var label: String { name ?? title }
    var project: String { (cwd as NSString).lastPathComponent }
}

/// Runs a command in a login shell so PATH matches the user's terminal.
@discardableResult
func sh(_ command: String) -> String? { run("/bin/zsh", ["-lc", command]) }

func osascript(_ source: String) -> String? { run("/usr/bin/osascript", ["-e", source]) }

private func run(_ tool: String, _ arguments: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Turns a project folder name back into a path, using the filesystem to settle ambiguity.
///
/// Claude Code encodes the directory by replacing `/` with `-`, which is lossy: for
/// `-Users-me-CODE-hr-match` you cannot tell which dashes were slashes. So walk the tokens and
/// keep extending the current component until the result is a directory that exists.
/// Returns nil when nothing matches — the project was moved or deleted.
func decodeProjectFolder(_ encoded: String) -> String? {
    let tokens = encoded.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
    guard !tokens.isEmpty else { return nil }

    var path = ""
    var pending = ""
    for token in tokens {
        pending = pending.isEmpty ? token : pending + "-" + token
        var isDir: ObjCBool = false
        let candidate = path + "/" + pending
        if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
            path = candidate
            pending = ""
        }
    }
    return pending.isEmpty ? path : nil
}

/// Moves a session's transcript to the Trash, along with any subagent logs it spawned.
///
// ponytail: trashItem, never unlink. These files are unrecoverable conversations, some of them
//           hundreds of megabytes, and the Trash is the difference between a mistake and a loss.
func trashSession(_ s: Session) -> Bool {
    let fm = FileManager.default
    let transcript = URL(fileURLWithPath: s.id)

    // Claude Code keeps subagent transcripts in a folder named after the session, next to it.
    var targets = [transcript]
    let subagents = transcript.deletingLastPathComponent().appendingPathComponent(s.sessionID)
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: subagents.path, isDirectory: &isDir), isDir.boolValue {
        targets.append(subagents)
    }

    for target in targets {
        guard (try? fm.trashItem(at: target, resultingItemURL: nil)) != nil else { return false }
    }
    Names.set("", for: s.sessionID)   // forget any custom name we were keeping for it
    return true
}

/// Session ids whose transcript contains `text`, anywhere in the conversation.
///
// ponytail: grep over the logs rather than an index. 364MB scans in well under a second, and an
//           index would need invalidating every time Claude Code writes a line.
func sessionsContaining(_ text: String) -> Set<String> {
    let quoted = "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let home = FileManager.default.homeDirectoryForCurrentUser
    let roots = [".claude/projects", ".codex/sessions"]
        .map { "'" + home.appendingPathComponent($0).path + "'" }
        .joined(separator: " ")
    // ripgrep is ~1000x faster here: 0.0s against grep's 7s over 364MB, because it searches in
    // parallel. grep is the fallback so the feature still works without it, just slower.
    let command = """
        if command -v rg >/dev/null 2>&1; then
          rg -l -i -F --glob '*.jsonl' -- \(quoted) \(roots) 2>/dev/null
        else
          grep -rlF -i --include='*.jsonl' -- \(quoted) \(roots) 2>/dev/null
        fi
        """
    guard let out = sh(command), !out.isEmpty else { return [] }

    // A hit is either <folder>/<session-id>.jsonl or, for a subagent transcript,
    // <folder>/<session-id>/subagents/agent-*.jsonl. The first UUID in the path is the
    // session either way, so a subagent match credits the conversation that spawned it.
    let uuid = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
    var ids = Set<String>()
    for line in out.split(separator: "\n") {
        let s = String(line)
        let range = NSRange(s.startIndex..., in: s)
        if let m = uuid?.firstMatch(in: s, range: range), let r = Range(m.range, in: s) {
            ids.insert(String(s[r]))
        }
    }
    return ids
}

/// Session ids that a running agent has on its command line. One shell call, not one per row.
func runningSessionIDs() -> Set<String> {
    let pids = Agent.allCases.map { "pgrep -x \($0.binary)" }.joined(separator: "; ")
    guard let out = sh("for pid in $(\(pids)); do ps -o command= -p $pid; done") else { return [] }
    // claude: --resume <id>   codex: resume <id>
    let uuid = try? NSRegularExpression(pattern: "resume\\s+([0-9a-fA-F-]{36})")
    let range = NSRange(out.startIndex..., in: out)
    var ids = Set<String>()
    uuid?.enumerateMatches(in: out, range: range) { match, _, _ in
        if let m = match, let r = Range(m.range(at: 1), in: out) { ids.insert(String(out[r])) }
    }
    return ids
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
func loadClaudeSessions() -> [Session] {
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

            var recordedCwd: String?, sid: String?, created = Date.distantPast, title: String?
            for line in text.split(separator: "\n") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      obj["type"] as? String == "user",
                      let c = obj["cwd"] as? String,
                      let s = obj["sessionId"] as? String else { continue }

                if recordedCwd == nil {  // identity + creation time come from the first message, whatever it says
                    (recordedCwd, sid) = (c, s)
                    created = (obj["timestamp"] as? String).flatMap(iso.date(from:)) ?? .distantPast
                }
                title = usableTitle(obj)
                if title != nil { break }
            }
            guard let recordedCwd, let sid else { continue }

            // The folder a session lives in beats the cwd written inside it. Copy a session
            // into another project and the file still names the directory it was born in.
            let folder = decodeProjectFolder(dir.lastPathComponent)
            let cwd = folder ?? recordedCwd

            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created
            out.append(Session(id: file.path, sessionID: sid, agent: .claude, cwd: cwd,
                               title: title ?? "(no prompt)", name: names[sid],
                               created: created, modified: modified,
                               exists: fm.fileExists(atPath: cwd)))
        }
    }
    // The same conversation can legitimately live under two project folders — copy one into
    // another project to carry on there. Both rows are kept; they differ by folder.
    var perFolder: [String: Int] = [:]
    for s in out { perFolder[s.cwd, default: 0] += 1 }
    let running = runningSessionIDs()
    for i in out.indices {
        out[i].aloneInFolder = perFolder[out[i].cwd] == 1
        out[i].isRunning = running.contains(out[i].sessionID)
    }

    return out.sorted { $0.modified > $1.modified }
}

/// Scans ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl.
///
/// Easier than Claude Code's layout: line one is a `session_meta` record carrying the id and
/// the working directory, and ~/.codex/session_index.jsonl already holds a human thread name.
func loadCodexSessions() -> [Session] {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let root = home.appendingPathComponent(".codex/sessions")
    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return [] }

    // id -> thread name, e.g. "Explore project folder"
    var threadNames: [String: String] = [:]
    if let index = try? String(contentsOf: home.appendingPathComponent(".codex/session_index.jsonl"), encoding: .utf8) {
        for line in index.split(separator: "\n") {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let id = obj["id"] as? String, let name = obj["thread_name"] as? String {
                threadNames[id] = name
            }
        }
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let names = Names.load()

    var out: [Session] = []
    for case let file as URL in walker where file.lastPathComponent.hasPrefix("rollout-")
                                          && file.pathExtension == "jsonl" {
        guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 64 * 1024),
              let text = String(data: chunk, encoding: .utf8),
              let first = text.split(separator: "\n").first,
              let obj = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String
        else { continue }

        let created = (payload["timestamp"] as? String).flatMap(iso.date(from:)) ?? .distantPast
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created

        out.append(Session(id: file.path, sessionID: id, agent: .codex, cwd: cwd,
                           title: threadNames[id] ?? "(untitled)", name: names[id],
                           created: created, modified: modified,
                           exists: fm.fileExists(atPath: cwd)))
    }
    return out
}

/// Every session from every agent, newest first.
func loadSessions() -> [Session] {
    (loadClaudeSessions() + loadCodexSessions()).sorted { $0.modified > $1.modified }
}
