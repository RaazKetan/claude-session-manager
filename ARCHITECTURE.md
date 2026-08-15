# How it works

Three Swift files, 418 lines. No libraries, no database, no internet.

## The big picture

Claude Code and Codex both write a log of every conversation. This app reads those logs and
gives you a way back into them.

```mermaid
flowchart LR
    CC["Claude Code"] -->|writes logs| L[("~/.claude/projects")]
    CX["Codex"] -->|writes logs| L2[("~/.codex/sessions")]
    L -->|reads| APP["Claude Sessions<br/>menu bar app"]
    L2 -->|reads| APP
    APP -->|"opens a terminal<br/>or jumps to one"| T["Your terminal"]
    T --> CC
    T --> CX
```

The app only ever **reads**. It never edits or deletes your session logs.

## Where everything lives

```mermaid
flowchart TD
    subgraph yours["Files Claude Code owns"]
        A["~/.claude/projects/&lt;project&gt;/&lt;session&gt;.jsonl<br/>one file per conversation"]
        B["~/.claude/settings.json<br/>your statusline setting"]
    end
    subgraph ours["Files this app owns"]
        C["names.json<br/>your custom session names"]
        D["statusline-installed<br/>marker, so setup runs once"]
        E["dev.local.claudesessions.plist<br/>starts the app at login"]
    end
```

Everything in "Files this app owns" sits in `~/Library`. Deleting them resets the app.

## Turning a log file into a row

```mermaid
flowchart TD
    A["Open a .jsonl file"] --> B["Read the first 64KB only"]
    B --> C["Find the first line you typed"]
    C --> D["Take the project folder<br/>and the date from it"]
    D --> E{"Is the text usable<br/>as a title?"}
    E -->|"no — an image,<br/>a slash command,<br/>a huge paste"| F["Try the next thing you typed"]
    F --> E
    E -->|yes| G["Use it as the label"]
    G --> H{"Did you rename<br/>this session?"}
    H -->|yes| I["Use your name instead"]
    H -->|no| J["Keep the label"]
```

Only the first 64KB is read because the opening of a conversation is always near the top, and
reading whole files would mean chewing through megabytes to show one line.

## What happens when you click a session

```mermaid
flowchart TD
    A["You click a row"] --> B{"Is this session<br/>already running?"}
    B -->|yes| C["Find which terminal tab<br/>it is running in"]
    C --> D["Bring that window to the front"]
    B -->|no| E["Write a tiny script<br/>that runs claude --resume"]
    E --> F["Hand it to your default terminal"]
    F --> G["The conversation opens<br/>where you left off"]
```

**How it knows a session is already running:** when the app starts a session it passes the
session id on the command line, so it can spot that id in the running process later.

**When it can't tell:** if you started Claude Code yourself, the id isn't there. The app then
only matches by folder, and only if that folder has a single session — otherwise it opens a new
window rather than risk showing you the wrong conversation.

Jumping to an existing window works in Terminal and iTerm2. Other terminals get a new window.

**Skipping permission prompts:** there is a checkbox under the list. Tick it and the resume
command gains `--dangerously-skip-permissions`, so the session runs tools without asking. It is
off until you turn it on, because it is a change to how much the agent can do unattended and
that should be your decision rather than something an install picks for you.

## Starting at login

```mermaid
flowchart LR
    A["App launches"] --> B["Work out its own<br/>permanent location"]
    B --> C["Write a small login file<br/>pointing at it"]
    C --> D["macOS opens it<br/>next time you log in"]
```

The "permanent location" step matters. Homebrew installs each version into its own folder and
deletes the old one when you upgrade. Pointing at that folder would break the app on every
upgrade, so it points at Homebrew's fixed shortcut instead.

## Shipping a new version

```mermaid
flowchart LR
    A["git tag v1.6.0"] --> B["GitHub builds the app"]
    B --> C["Attaches a download<br/>to the release"]
    C --> D["The tap updates itself"]
    D --> E["brew install<br/>gets the new version"]
```

Pushing a tag is the whole release process. The build works on both Intel and Apple Silicon
Macs, and the build fails on purpose if the Intel half is missing.

## Two ways to install, and why

```mermaid
flowchart TD
    A{"Do you have<br/>Xcode tools?"} -->|yes| B["Formula<br/>builds on your Mac"]
    A -->|no| C["Cask<br/>downloads a ready-made app"]
    B --> D["No security warning,<br/>because nothing was downloaded"]
    C --> E["macOS flags downloads,<br/>so the install clears the flag"]
```

## Update check

One request to GitHub's releases API on launch, cached for the session. It compares tags
numerically, so 1.10.0 correctly beats 1.9.0. Nothing is downloaded or installed — the app
shows the `brew upgrade` command and Homebrew stays in charge of the actual update.

## What it can't do yet

| | |
|---|---|
| A session with a very long opening | won't appear in the list |
| Jumping to an open window | Terminal and iTerm2 only |
| A session you started by hand, in a folder with several | opens a new window instead |
| Apple security check | not signed up as a paid developer, so macOS doesn't verify it |

## Checking it works

```sh
swift run ClaudeSessions --list
```

Prints every session it can read, with no window. A `!` at the start of a line means that
project folder is gone.
