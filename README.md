# Claude Sessions

A macOS menu bar widget listing every Claude Code session on your machine. Click one to resume it in your terminal.

![menu bar](https://img.shields.io/badge/macOS-13%2B-black)

- Reads `~/.claude/projects/*/*.jsonl` — the session log Claude Code already writes. Nothing is sent anywhere.
- Each row shows the first prompt, the project path, and the date it was created. Sorted by most recent.
- Clicking runs `claude --resume <id>` in that directory, in your default terminal.
- Sessions whose folder has since been deleted are greyed out and not clickable.

## Naming sessions

The label is the first usable prompt of the conversation, which is often not what you'd call it. Click the pencil on any row and type your own name. Clear the field to go back to the auto label.

Names live in `~/Library/Application Support/ClaudeSessions/names.json`, keyed by session id — delete that file to reset everything.

## Install

```sh
git clone https://github.com/<you>/claude-sessions.git
cd claude-sessions
./build.sh
open ClaudeSessions.app
```

Move `ClaudeSessions.app` to `/Applications` and add it to **System Settings → General → Login Items** to have it always there.

### "ClaudeSessions is damaged and can't be opened"

The app is ad-hoc signed, not notarized, so macOS quarantines it. Strip the flag:

```sh
xattr -dr com.apple.quarantine ClaudeSessions.app
```

You only need this if you downloaded a release zip — a local `./build.sh` isn't quarantined.

## How resume works

The app writes a small `.command` script to a temp dir and `open`s it. macOS hands `.command` files to whatever terminal you've set as the default — Terminal, iTerm, Ghostty, WezTerm — so there's no per-terminal integration to configure.

## Spotify statusline

On first launch this installs [claude-code-spotify](https://github.com/RaazKetan/claude-code-spotify) and sets it as your Claude Code statusline — session, model, branch, context, cost, and the live synced lyric.

It runs once. If you already have a `statusLine` configured, the old `~/.claude/settings.json` is copied to `settings.json.claude-sessions-backup` first. To opt out, create the marker before you launch the app:

```sh
mkdir -p ~/Library/Application\ Support/ClaudeSessions
touch ~/Library/Application\ Support/ClaudeSessions/statusline-installed
```

## Check the parser

```sh
swift run ClaudeSessions --list
```

Prints every session it found as text.

## License

MIT
