# Claude Sessions

All your Claude Code sessions in the menu bar. Click one to pick up where you left off.

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

## What it does

- Lists every session on your Mac, newest first.
- Click one to resume it. If it's already open, it jumps to that window instead of starting a second one.
- Starts automatically when you log in.
- Sessions whose folder you deleted are greyed out.
- Reads the logs Claude Code already keeps on your Mac. Nothing is uploaded.

It also installs the [Spotify statusline](https://github.com/RaazKetan/claude-code-spotify) the first time you open it, and backs up your old `statusLine` setting. To skip that, create the file `~/Library/Application Support/ClaudeSessions/statusline-installed` before launching.

## Good to know

- Jumping to an open session works in Terminal and iTerm2. Other terminals open a new window.
- Session names come from the first thing you typed. To rename one, add its id to `~/Library/Application Support/ClaudeSessions/names.json`:
  ```json
  { "90d19fcb-8ba7-4016-99a1-465cd4a5c7ae": "Conekt deploy" }
  ```

## Uninstall

```sh
brew uninstall --cask claude-sessions
rm -rf ~/Library/"Application Support"/ClaudeSessions ~/Library/LaunchAgents/dev.local.claudesessions.plist
```

## Building it yourself

```sh
./build.sh                        # makes ClaudeSessions.app
swift run ClaudeSessions --list   # prints what it can read, no window
```

## License

[MIT](LICENSE)
