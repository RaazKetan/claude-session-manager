import SwiftUI
import ServiceManagement

/// Brings an already-running session forward, or starts it in the default terminal.
// ponytail: skipPermissions is opt-in and off by default. It hands the session blanket
//           tool approval, which is the user's call to make, not an install-time default.
func resume(_ s: Session, skipPermissions: Bool = false) {
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
        if ! command -v \(s.agent.binary) >/dev/null 2>&1; then
          echo "'\(s.agent.binary)' isn't installed, or isn't on your PATH."
          echo "Install it from \(s.agent.installURL), then try again."
          echo
          read "?Press return to close… "
          exit 1
        fi
        \(s.agent.resumeCommand(s.sessionID, skipPermissions: skipPermissions))

        """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(s.sessionID).command")
    try? script.write(to: url, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    NSWorkspace.shared.open(url)
}

/// tty of the running `claude` for this session, or nil if it isn't running — or if we
/// can't tell which of several sessions in the folder is the one on screen.
func runningSessionTTY(_ s: Session) -> String? {
    // Exact: our own resume passes the id, so it is in the process arguments.
    if let tty = agentTTY(s.agent, matching: "ps -o command= -p $pid | grep -q -- \(s.sessionID)") { return tty }

    // A folder match only identifies the session when the folder holds exactly one.
    // Guessing between siblings would surface the wrong window.
    guard s.aloneInFolder else { return nil }
    let quoted = "'" + s.cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return agentTTY(s.agent, matching: "[ \"$(lsof -a -p $pid -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')\" = \(quoted) ]")
}

private func agentTTY(_ agent: Agent, matching test: String) -> String? {
    let tty = sh("""
        for pid in $(pgrep -x \(agent.binary)); do
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

/// Menu bar mark, as a pixel grid — one row per line, `1` is a filled cell.
private let iconPixels = [
    "0011111111111100",
    "0011111111111100",
    "0011011111101100",
    "0011011111101100",
    "1111111111111111",
    "1111111111111111",
    "0011111111111100",
    "0011111111111100",
    "0001010000101000",
    "0001010000101000",
]

// ponytail: 1.5pt cells land on whole device pixels at 2x, so the sprite stays crisp
//           instead of smearing the way a scaled bitmap would.
let statusIcon: NSImage = {
    let cell: CGFloat = 1.25
    let cols = CGFloat(iconPixels[0].count), rows = CGFloat(iconPixels.count)

    let icon = NSImage(size: NSSize(width: cols * cell, height: rows * cell), flipped: false) { _ in
        NSColor.black.setFill()   // template images are an alpha mask; macOS supplies the colour
        for (r, row) in iconPixels.enumerated() {
            for (c, pixel) in row.enumerated() where pixel == "1" {
                // Grid runs top-down; the drawing origin is bottom-left.
                NSRect(x: CGFloat(c) * cell,
                       y: (rows - 1 - CGFloat(r)) * cell,
                       width: cell, height: cell).fill()
            }
        }
        return true
    }
    icon.isTemplate = true   // white on a dark menu bar, black on a light one
    return icon
}()

struct SessionList: View {
    @State private var sessions: [Session] = []
    @State private var query = ""
    @AppStorage("skipPermissions") private var skipPermissions = false
    @State private var hovered: String?
    @State private var insideMatches: Set<String> = []
    @State private var searchingInside = false
    @State private var updateAvailable: String?
    @State private var copiedUpgrade = false
    @AppStorage("agentFilterRaw") private var agentFilterRaw = ""
    private var agentFilter: Agent? {
        get { Agent(rawValue: agentFilterRaw) }
        nonmutating set { agentFilterRaw = newValue?.rawValue ?? "" }
    }

    /// Matches on the visible label and path, plus anything found inside the transcripts.
    var filtered: [Session] {
        sessions.filter { s in
            guard agentFilter == nil || s.agent == agentFilter else { return false }
            guard !query.isEmpty else { return true }
            return (s.cwd + " " + s.label).localizedCaseInsensitiveContains(query)
                || insideMatches.contains(s.sessionID)
        }
    }

    func count(_ agent: Agent?) -> Int {
        agent == nil ? sessions.count : sessions.filter { $0.agent == agent }.count
    }

    /// True when the row only turned up because of what's inside the conversation.
    func matchedInside(_ s: Session) -> Bool {
        insideMatches.contains(s.sessionID)
            && !(s.cwd + " " + s.label).localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search sessions and conversations", text: $query)
                .textFieldStyle(.roundedBorder)
                // Debounced, and .task(id:) cancels the previous scan when the query changes.
                .task(id: query) {
                    guard query.count >= 2 else { insideMatches = []; return }
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    searchingInside = true
                    let text = query
                    let hits = await Task.detached(priority: .userInitiated) {
                        sessionsContaining(text)
                    }.value
                    guard !Task.isCancelled else { return }
                    insideMatches = hits
                    searchingInside = false
                }

            HStack(spacing: 6) {
                ForEach([nil] + Agent.allCases.map { Optional($0) }, id: \.self) { agent in
                    let selected = agentFilter == agent
                    Button {
                        agentFilter = agent
                    } label: {
                        HStack(spacing: 4) {
                            Text(agent?.label ?? "All")
                            Text("\(count(agent))")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(selected ? AnyShapeStyle(.selection) : AnyShapeStyle(.quaternary),
                                    in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(count(agent) == 0 && agent != nil)
                    .opacity(count(agent) == 0 && agent != nil ? 0.4 : 1)
                }
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { s in
                        Button { resume(s, skipPermissions: skipPermissions) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    if s.isRunning {
                                        Circle().fill(.green).frame(width: 6, height: 6)
                                            .help("Running now")
                                    }
                                    Text(s.label)
                                        .lineLimit(1)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(s.exists ? .primary : .secondary)
                                }

                                HStack(spacing: 6) {
                                    if agentFilter == nil {
                                        Text(s.agent.label)
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(s.shortPath)
                                        .lineLimit(1).truncationMode(.head)
                                    Text("·")
                                    Text(s.when)
                                    if !s.exists {
                                        Text("folder missing")
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                    if matchedInside(s) {
                                        Label("in conversation", systemImage: "text.magnifyingglass")
                                            .labelStyle(.titleAndIcon)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(hovered == s.id ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!s.exists)
                        .onHover { hovered = $0 ? s.id : (hovered == s.id ? nil : hovered) }
                        .help(s.exists ? "Resume — switches to its window if it is already open"
                                       : "That folder no longer exists")
                    }
                }
            }
            .frame(height: 360)

            Toggle("Skip permission prompts", isOn: $skipPermissions)
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(skipPermissions ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Resume with --dangerously-skip-permissions, so the session never asks before running a tool")

            if let newer = updateAvailable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Update.upgradeCommand, forType: .string)
                    copiedUpgrade = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle")
                        Text(copiedUpgrade ? "Copied — paste it in a terminal"
                                           : "Version \(newer) is out. Click to copy the upgrade command.")
                        Spacer()
                    }
                    .font(.caption)
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Update.upgradeCommand)
            }

            HStack {
                Text(searchingInside ? "searching…" : "\(filtered.count) sessions")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption)
            }
        }
        .padding(10)
        .frame(width: 340)
        .onAppear { sessions = loadSessions() }
        .task { updateAvailable = await Update.newerVersion() }
    }
}

@main
struct ClaudeSessionsApp: App {
    init() {
        // runnable check: `swift run ClaudeSessions --list`
        if CommandLine.arguments.contains("--list") {
            let s = loadSessions()
            s.forEach { print("\($0.exists ? " " : "!")\($0.created.formatted())  \($0.cwd)  \($0.agent.label)  \($0.sessionID)  \($0.isRunning ? "[running] " : "")\($0.name == nil ? "" : "[named] ")\($0.label.prefix(50))") }
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
