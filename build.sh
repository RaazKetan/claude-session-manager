#!/bin/zsh
# Builds ClaudeSessions.app (menu bar app + desktop widget).
set -e
command -v xcodegen >/dev/null && xcodegen generate   # regenerate from project.yml when available
xcodebuild -project ClaudeSessions.xcodeproj -scheme ClaudeSessions \
  -configuration Release -derivedDataPath .dd build | tail -1
rm -rf ClaudeSessions.app
cp -R .dd/Build/Products/Release/ClaudeSessions.app .
echo "Built ClaudeSessions.app — move it to /Applications so macOS registers the widget."
