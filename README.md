# Claude Sessions

A macOS menu bar widget listing every Claude Code session on your machine. Click one to resume it in your terminal.

![menu bar](https://img.shields.io/badge/macOS-13%2B-black)

- Reads `~/.claude/projects/*/*.jsonl` — the session log Claude Code already writes. Nothing is sent anywhere.
- Each row shows the first prompt, the project path, and the date it was created. Sorted by most recent.
- Clicking runs `claude --resume <id>` in that directory, in your default terminal.

## Install

```sh
git clone https://github.com/<you>/claude-sessions.git
cd claude-sessions
./build.sh
open ClaudeSessions.app
```

Move `ClaudeSessions.app` to `/Applications` and add it to **System Settings → General → Login Items** to have it always there.

## How resume works

The app writes a small `.command` script to a temp dir and `open`s it. macOS hands `.command` files to whatever terminal you've set as the default — Terminal, iTerm, Ghostty, WezTerm — so there's no per-terminal integration to configure.

## Check the parser

```sh
swift run ClaudeSessions --list
```

Prints every session it found as text.

## License

MIT
