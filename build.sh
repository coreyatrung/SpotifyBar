#!/bin/bash
# Builds SpotifyBar.app from the Swift sources. No Xcode GUI needed.
set -e
cd "$(dirname "$0")"

APP="SpotifyBar.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/SpotifyBar"

echo "→ Cleaning"
rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources"

echo "→ Compiling"
swiftc -swift-version 5 -O \
  Sources/SpotifyController.swift \
  Sources/PlayerState.swift \
  Sources/MenuBarLabel.swift \
  Sources/NowPlayingView.swift \
  Sources/AppDelegate.swift \
  Sources/main.swift \
  -framework AppKit -framework SwiftUI -framework Foundation \
  -o "$BIN"

echo "→ Bundling"
cp Info.plist "$APP/Contents/Info.plist"

echo "→ Ad-hoc signing (so macOS remembers the Automation permission)"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
