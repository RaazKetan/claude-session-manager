# Claude Sessions

A macOS menu bar app listing every Claude Code session on your machine. Click one to resume it.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![MIT](https://img.shields.io/badge/license-MIT-blue)

## Install

```sh
brew install RaazKetan/tap/claude-session-manager
open "$(brew --prefix)/opt/claude-session-manager/ClaudeSessions.app"
```

macOS 13+. Builds on your machine, so there is no Gatekeeper warning — needs the Command Line Tools (`xcode-select --install`). Want a prebuilt download instead?

```sh
brew install --cask RaazKetan/tap/claude-sessions && open /Applications/ClaudeSessions.app
```

No Homebrew? `curl -fsSL https://raw.githubusercontent.com/RaazKetan/claude-session-manager/main/install.sh | zsh`

## What it does

- Lists every session from `~/.claude/projects/*/*.jsonl`, newest first. Nothing leaves your machine.
- Clicking **switches to the session's window** if it's already running, otherwise resumes it in your default terminal. Window switching needs Terminal or iTerm2; other terminals get a new window.
- Greys out sessions whose folder was deleted.
- Starts at login.
- Installs the [Spotify statusline](https://github.com/RaazKetan/claude-code-spotify) on first launch, backing up any `statusLine` you already have. To skip it, `touch ~/Library/Application\ Support/ClaudeSessions/statusline-installed` first.

Rename a session by adding its id to `~/Library/Application Support/ClaudeSessions/names.json`:

```json
{ "90d19fcb-8ba7-4016-99a1-465cd4a5c7ae": "Conekt deploy" }
```

## Uninstall

```sh
brew uninstall claude-session-manager   # or: brew uninstall --cask claude-sessions
rm -rf ~/Library/"Application Support"/ClaudeSessions
```

Then remove it from **System Settings → General → Login Items**.

## Development

```sh
swift run ClaudeSessions --list   # print parsed sessions, no UI ('!' = folder gone)
./build.sh                        # assemble ClaudeSessions.app
```

If macOS calls a downloaded build damaged, it's the missing notarization: `xattr -dr com.apple.quarantine /Applications/ClaudeSessions.app`.

## License

MIT — an unofficial third-party tool, not affiliated with or endorsed by Anthropic.
