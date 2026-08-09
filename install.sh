#!/bin/zsh
# curl -fsSL https://raw.githubusercontent.com/RaazKetan/claude-session-manager/main/install.sh | zsh
set -e

REPO="https://github.com/RaazKetan/claude-session-manager.git"
WORK="${TMPDIR:-/tmp}/claude-session-manager-install"

command -v swift >/dev/null || {
  echo "Needs the Xcode Command Line Tools. Run: xcode-select --install"
  exit 1
}

echo "Building Claude Sessions…"
rm -rf "$WORK"
git clone -q --depth 1 "$REPO" "$WORK"
cd "$WORK"
./build.sh >/dev/null

pkill -f "ClaudeSessions.app/Contents/MacOS" 2>/dev/null || true
rm -rf /Applications/ClaudeSessions.app
cp -R ClaudeSessions.app /Applications/
cd - >/dev/null && rm -rf "$WORK"

open /Applications/ClaudeSessions.app
echo "Installed. Look for the >_ icon in your menu bar."
