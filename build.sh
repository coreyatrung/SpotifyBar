#!/bin/bash
# Builds SpotifyBar.app from the Swift sources. No Xcode GUI needed.
# For a distributable universal build, use ./release.sh instead.
set -e
cd "$(dirname "$0")"

APP="SpotifyBar.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/SpotifyBar"
SOURCES=(
  Sources/Layout.swift
  Sources/Formatting.swift
  Sources/SpotifyController.swift
  Sources/TrackChangeDetector.swift
  Sources/PlayerState.swift
  Sources/ArtworkLoader.swift
  Sources/MenuBarLabel.swift
  Sources/NowPlayingView.swift
  Sources/TrackToast.swift
  Sources/AppDelegate.swift
  Sources/main.swift
)

echo "→ Cleaning"
rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources"

# Pin the same deployment target as Info.plist and release.sh. Without -target this
# built against whatever SDK happened to be current and ignored the 13.0 floor.
echo "→ Compiling for $(uname -m)"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" \
  "${SOURCES[@]}" \
  -framework AppKit -framework SwiftUI \
  -o "$BIN"

echo "→ Bundling"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Same hardened runtime and entitlements as release.sh, so a local build behaves the
# same way as a shipped one. Note that an ad-hoc signature is a fresh identity on every
# rebuild, so macOS will usually re-ask for Automation access after you rebuild —
# that's expected, not a bug.
echo "→ Ad-hoc signing"
codesign --force --options runtime --entitlements SpotifyBar.entitlements --sign - "$APP"

echo "✓ Built $APP"
