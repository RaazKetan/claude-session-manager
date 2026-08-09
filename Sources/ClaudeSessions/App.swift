import SwiftUI

// MARK: - Model

struct Session: Identifiable {
    let id: String
    let cwd: String
    let title: String
    let created: Date
    let modified: Date
    let exists: Bool

    var project: String { (cwd as NSString).lastPathComponent }
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
            out.append(Session(id: sid, cwd: cwd, title: title ?? "(no prompt)",
                               created: created, modified: modified,
                               exists: fm.fileExists(atPath: cwd)))
        }
    }
    return out.sorted { $0.modified > $1.modified }
}

/// Opens the session in whatever app handles .command files — i.e. the user's default terminal.
func resume(_ s: Session) {
    let quoted = "'" + s.cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let script = "#!/bin/zsh\ncd \(quoted) && claude --resume \(s.id)\n"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(s.id).command")
    try? script.write(to: url, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    NSWorkspace.shared.open(url)
}

// MARK: - UI

struct SessionList: View {
    @State private var sessions: [Session] = []
    @State private var query = ""

    var filtered: [Session] {
        query.isEmpty ? sessions : sessions.filter {
            ($0.cwd + " " + $0.title).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { s in
                        Button { resume(s) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).lineLimit(1).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(s.exists ? .primary : .tertiary)
                                Text(s.exists ? s.cwd : "\(s.cwd) — folder is gone")
                                    .lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(s.created.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4).padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!s.exists)
                        .help(s.exists ? "Resume in terminal" : "That directory no longer exists")
                    }
                }
            }
            .frame(height: 360)

            HStack {
                Text("\(filtered.count) sessions").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption)
            }
        }
        .padding(10)
        .frame(width: 340)
        .onAppear { sessions = loadSessions() }
    }
}

@main
struct ClaudeSessionsApp: App {
    init() {
        // runnable check: `swift run ClaudeSessions --list`
        if CommandLine.arguments.contains("--list") {
            let s = loadSessions()
            s.forEach { print("\($0.exists ? " " : "!")\($0.created.formatted())  \($0.cwd)  \($0.id)  \($0.title.prefix(50))") }
            assert(s.allSatisfy { !$0.cwd.isEmpty && !$0.id.isEmpty }, "parsed session missing cwd/id")
            print("\(s.count) sessions")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("Claude Sessions", systemImage: "terminal") { SessionList() }
            .menuBarExtraStyle(.window)
    }
}
