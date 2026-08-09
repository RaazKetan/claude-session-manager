import SwiftUI

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
    @State private var editing: String?     // session id being renamed
    @State private var draft = ""
    @FocusState private var nameFieldFocused: Bool

    var filtered: [Session] {
        query.isEmpty ? sessions : sessions.filter {
            ($0.cwd + " " + $0.label).localizedCaseInsensitiveContains(query)
        }
    }

    func commit(_ s: Session) {
        Names.set(draft, for: s.id)
        editing = nil
        sessions = loadSessions()
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { s in
                        HStack(spacing: 4) {
                            Button { resume(s) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if editing == s.id {
                                        TextField("Name this session", text: $draft)
                                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                                            .focused($nameFieldFocused)
                                            .onSubmit { commit(s) }
                                            .onExitCommand { editing = nil }
                                    } else {
                                        Text(s.label).lineLimit(1).font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(s.exists ? .primary : .tertiary)
                                    }
                                    Text(s.exists ? s.cwd : "\(s.cwd) — folder is gone")
                                        .lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(s.created.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).padding(.leading, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!s.exists || editing == s.id)
                            .help(s.exists ? "Resume in terminal" : "That directory no longer exists")

                            Button {
                                if editing == s.id { commit(s) } else {
                                    draft = s.name ?? ""
                                    editing = s.id
                                    nameFieldFocused = true
                                }
                            } label: {
                                Image(systemName: editing == s.id ? "checkmark" : "pencil")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain).padding(.trailing, 6)
                            .help(s.name == nil ? "Name this session" : "Rename (clear the field to restore the prompt)")
                        }
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
            s.forEach { print("\($0.exists ? " " : "!")\($0.created.formatted())  \($0.cwd)  \($0.id)  \($0.name == nil ? "" : "[named] ")\($0.label.prefix(50))") }
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
