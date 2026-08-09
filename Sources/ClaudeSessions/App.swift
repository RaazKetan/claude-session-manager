import SwiftUI
import ServiceManagement

/// Brings an already-running session forward, or starts it in the default terminal.
func resume(_ s: Session) {
    if focusRunningSession(s) { return }

    let quoted = "'" + s.cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
    // Explain the two ways this can fail, instead of leaving a bare "command not found".
    let script = """
        #!/bin/zsh
        cd \(quoted) 2>/dev/null || {
          echo "That folder is gone: \(s.cwd)"
          read "?Press return to close… "
          exit 1
        }
        if ! command -v claude >/dev/null 2>&1; then
          echo "Claude Code isn't installed, or 'claude' isn't on your PATH."
          echo "Install it from https://claude.com/claude-code, then try again."
          echo
          read "?Press return to close… "
          exit 1
        fi
        claude --resume \(s.id)

        """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(s.id).command")
    try? script.write(to: url, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    NSWorkspace.shared.open(url)
}

/// tty of the running `claude` for this session, or nil if it isn't running — or if we
/// can't tell which of several sessions in the folder is the one on screen.
func runningSessionTTY(_ s: Session) -> String? {
    // Exact: our own resume passes `--resume <id>`, so the id is in the process arguments.
    if let tty = claudeTTY(matching: "ps -o command= -p $pid | grep -q -- \(s.id)") { return tty }

    // A folder match only identifies the session when the folder holds exactly one.
    // Guessing between siblings would surface the wrong window.
    guard s.aloneInFolder else { return nil }
    let quoted = "'" + s.cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return claudeTTY(matching: "[ \"$(lsof -a -p $pid -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')\" = \(quoted) ]")
}

private func claudeTTY(matching test: String) -> String? {
    let tty = sh("""
        for pid in $(pgrep -x claude); do
          if \(test); then ps -o tty= -p $pid | tr -d ' '; break; fi
        done
        """)
    guard let tty, !tty.isEmpty, tty != "??" else { return nil }
    return "/dev/" + tty
}

/// Bundle path with any Homebrew version baked out of it:
/// …/Cellar/claude-session-manager/1.3.1/X.app → …/opt/claude-session-manager/X.app
func stableBundlePath() -> String {
    let path = Bundle.main.bundleURL.path
    guard let range = path.range(of: "/Cellar/[^/]+/[^/]+/", options: .regularExpression) else { return path }
    let formula = path[range].split(separator: "/")[1]
    return path.replacingCharacters(in: range, with: "/opt/\(formula)/")
}

/// Starts the app at login.
// ponytail: SMAppService records the bundle's literal path, which under a Homebrew formula
//           is a versioned Cellar directory that `brew upgrade` deletes — leaving a login
//           item pointing at nothing. Our own agent can name the stable symlink instead.
func enableLaunchAtLogin() {
    try? SMAppService.mainApp.unregister()   // drop the Cellar-pinned entry older builds made

    let agents = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    let plist: [String: Any] = [
        "Label": "dev.local.claudesessions",
        "ProgramArguments": ["\(stableBundlePath())/Contents/MacOS/ClaudeSessions"],
        "RunAtLoad": true,
    ]
    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    else { return }
    try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    try? data.write(to: agents.appendingPathComponent("dev.local.claudesessions.plist"), options: .atomic)
}

/// Focuses the window already running this session.
// ponytail: only Terminal and iTerm2 expose tty per tab. Any other terminal falls through to a new window.
func focusRunningSession(_ s: Session) -> Bool {
    guard let tty = runningSessionTTY(s) else { return false }
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

    if running.contains("com.apple.Terminal"), osascript("""
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected of t to true
                set index of w to 1
                activate
                return "ok"
              end if
            end repeat
          end repeat
        end tell
        return "no"
        """) == "ok" { return true }

    if running.contains("com.googlecode.iterm2"), osascript("""
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with ss in sessions of t
                if tty of ss is "\(tty)" then
                  select ss
                  select t
                  select w
                  activate
                  return "ok"
                end if
              end repeat
            end repeat
          end repeat
        end tell
        return "no"
        """) == "ok" { return true }

    return false
}

// MARK: - UI

/// Menu bar mark: a session window with a prompt inside it.
// ponytail: drawn in code, no asset catalog. Monoline at a single stroke weight so it
//           sits with the system icons; template image, so macOS tints it per theme.
let statusIcon: NSImage = {
    let stroke: CGFloat = 1.5

    let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.setStroke()

        let window = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.6, width: 15, height: 12.8),
                                  xRadius: 2.8, yRadius: 2.8)
        window.lineWidth = stroke
        window.stroke()

        let titleBar = NSBezierPath()
        titleBar.move(to: NSPoint(x: 1.5, y: 12.0))
        titleBar.line(to: NSPoint(x: 16.5, y: 12.0))
        titleBar.lineWidth = stroke
        titleBar.stroke()

        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: 4.8, y: 9.4))
        chevron.line(to: NSPoint(x: 7.4, y: 7.4))
        chevron.line(to: NSPoint(x: 4.8, y: 5.4))
        chevron.lineWidth = stroke
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()

        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 9.0, y: 5.4))
        cursor.line(to: NSPoint(x: 12.6, y: 5.4))
        cursor.lineWidth = stroke
        cursor.lineCapStyle = .round
        cursor.stroke()

        return true
    }
    icon.isTemplate = true
    return icon
}()

struct SessionList: View {
    @State private var sessions: [Session] = []
    @State private var query = ""

    var filtered: [Session] {
        query.isEmpty ? sessions : sessions.filter {
            ($0.cwd + " " + $0.label).localizedCaseInsensitiveContains(query)
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
                                Text(s.label).lineLimit(1).font(.system(size: 12, weight: .medium))
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
                        .help(s.exists ? "Resume — switches to its window if it is already open"
                                       : "That directory no longer exists")
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
        Statusline.installIfNeeded()
        enableLaunchAtLogin()
    }

    var body: some Scene {
        MenuBarExtra { SessionList() } label: { Image(nsImage: statusIcon) }
            .menuBarExtraStyle(.window)
    }
}
