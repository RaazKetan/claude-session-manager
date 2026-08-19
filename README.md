# Claude Sessions

All your Claude Code and Codex sessions in the menu bar. Click one to pick up where you left off.

```sh
brew install --cask RaazKetan/tap/claude-sessions && open /Applications/ClaudeSessions.app
```

Works on Intel and Apple Silicon. Needs macOS 13 or newer.

<details>
<summary>Other ways to install</summary>

Build from source instead of downloading (needs `xcode-select --install`):

```sh
brew install RaazKetan/tap/claude-session-manager
open "$(brew --prefix)/opt/claude-session-manager/ClaudeSessions.app"
```

No Homebrew:

```sh
curl -fsSL https://raw.githubusercontent.com/RaazKetan/claude-session-manager/main/install.sh | zsh
```

</details>

## Updating

Whichever way you installed it:

```sh
brew upgrade --cask claude-sessions                      # the cask, above
brew upgrade RaazKetan/tap/claude-session-manager        # built from source
curl -fsSL https://raw.githubusercontent.com/RaazKetan/claude-session-manager/main/install.sh | zsh   # no Homebrew
```

Versions before 1.9.2 offered the cask command to everybody, so if you built from source it answered
`Error: Cask 'claude-sessions' is not installed`. Use the second line once, and the app gets it right
from then on. A plain `brew upgrade` also picks it up.

## What it does

- Lists every Claude Code and Codex session on your Mac, newest first. Filter by agent, or search inside the conversations themselves.
- Click one to resume it. If it's already open, it jumps to that window instead of starting a second one.
- Marks the sessions running right now.
- Starts automatically when you log in.
- Tells you when an update is out — in the menu bar panel, as a notification, and as a line new terminals print — and copies the right upgrade command for how you installed it.
- Optional checkbox to resume Claude sessions with `--dangerously-skip-permissions`, so they never stop to ask before running a tool. Off unless you turn it on.
- Sessions whose folder you deleted are greyed out.
- Right-click a session to move it to the Trash, or reveal the log file in Finder.
- Reads the logs these tools already keep on your Mac. Nothing about you is sent anywhere. The only network call is one request to GitHub on launch, to see whether a newer version exists.

It also installs the [Spotify statusline](https://github.com/RaazKetan/claude-code-spotify) the first time you open it, and backs up your old `statusLine` setting. To skip that, create the file `~/Library/Application Support/ClaudeSessions/statusline-installed` before launching.

## Good to know

- Jumping to an open session works in Terminal and iTerm2. Other terminals open a new window.
- Searching inside conversations runs one `grep` per transcript across your cores, and shows the passage it found. About a second over a gigabyte of logs; no ripgrep needed.
- Session names come from the first thing you typed. To rename one, add its id to `~/Library/Application Support/ClaudeSessions/names.json`:
  ```json
  { "90d19fcb-8ba7-4016-99a1-465cd4a5c7ae": "Conekt deploy" }
  ```

## Uninstall

```sh
brew uninstall --cask claude-sessions   # or: brew uninstall claude-session-manager
rm -rf ~/Library/"Application Support"/ClaudeSessions ~/Library/LaunchAgents/dev.local.claudesessions.plist
```

## How it works

[ARCHITECTURE.md](ARCHITECTURE.md) covers how sessions are found, how resuming and window-switching work, and where the limits are.

## Building it yourself

```sh
./build.sh                                  # makes ClaudeSessions.app
swift run ClaudeSessions --list              # prints what it can read, no window
swift run ClaudeSessions --search "some text"   # what searching inside conversations finds
swift run ClaudeSessions --update               # version check and the upgrade command for this copy
```

## License

[MIT](LICENSE)
