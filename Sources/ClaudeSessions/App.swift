import SwiftUI

// MARK: - Model

struct Session: Identifiable {
    let id: String
    let cwd: String
    let title: String
    let created: Date
    let modified: Date

    var project: String { (cwd as NSString).lastPathComponent }
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

            for line in text.split(separator: "\n") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      obj["type"] as? String == "user",
                      let cwd = obj["cwd"] as? String,
                      let sid = obj["sessionId"] as? String else { continue }

                let msg = obj["message"] as? [String: Any]
                var title = ""
                if let s = msg?["content"] as? String {
                    title = s
                } else if let blocks = msg?["content"] as? [[String: Any]] {
                    title = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
                }
                title = title.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""

                let created = (obj["timestamp"] as? String).flatMap(iso.date(from:)) ?? .distantPast
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? created

                out.append(Session(id: sid, cwd: cwd, title: title.isEmpty ? "(no prompt)" : title,
                                   created: created, modified: modified))
                break // first user message is enough
            }
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
                                Text(s.cwd).lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(s.created.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4).padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Resume in terminal")
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
            s.forEach { print("\($0.created.formatted())  \($0.cwd)  \($0.id)  \($0.title.prefix(50))") }
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
