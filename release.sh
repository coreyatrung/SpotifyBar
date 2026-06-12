#!/bin/bash
# Builds a UNIVERSAL SpotifyBar.app (arm64 + x86_64) and packages it into a DMG.
#
# Optional signing / notarization via environment variables:
#   SPOTIFYBAR_SIGN_ID  "Developer ID Application: Your Name (TEAMID)"  -> enables a distributable signature
#   SPOTIFYBAR_NOTARY   name of a notarytool keychain profile           -> notarizes + staples the DMG
#
# With neither set, it ad-hoc signs (works, but downloaders see the Gatekeeper warning).
set -e
cd "$(dirname "$0")"

APP="SpotifyBar.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/SpotifyBar"
DMG="SpotifyBar.dmg"
SOURCES=(
  Sources/SpotifyController.swift
  Sources/PlayerState.swift
  Sources/MenuBarLabel.swift
  Sources/NowPlayingView.swift
  Sources/AppDelegate.swift
  Sources/main.swift
)

echo "→ Cleaning"
rm -rf "$APP" "$DMG" dmg-stage

echo "→ Compiling universal (arm64 + x86_64)"
mkdir -p "$MACOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos13.0  "${SOURCES[@]}" -framework AppKit -framework SwiftUI -o "$BIN-arm64"
swiftc -swift-version 5 -O -target x86_64-apple-macos13.0 "${SOURCES[@]}" -framework AppKit -framework SwiftUI -o "$BIN-x86_64"
lipo -create "$BIN-arm64" "$BIN-x86_64" -output "$BIN"
rm -f "$BIN-arm64" "$BIN-x86_64"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ID="${SPOTIFYBAR_SIGN_ID:-}"
if [ -n "$SIGN_ID" ]; then
  echo "→ Signing with Developer ID: $SIGN_ID"
  codesign --force --options runtime --timestamp --entitlements SpotifyBar.entitlements --sign "$SIGN_ID" "$APP"
else
  echo "→ Ad-hoc signing (set SPOTIFYBAR_SIGN_ID to make a notarizable build)"
  codesign --force --options runtime --entitlements SpotifyBar.entitlements --sign - "$APP"
fi

echo "→ Building DMG"
mkdir -p dmg-stage
cp -R "$APP" dmg-stage/
ln -s /Applications dmg-stage/Applications
hdiutil create -volname "SpotifyBar" -srcfolder dmg-stage -ov -format UDZO "$DMG" >/dev/null
rm -rf dmg-stage

if [ -n "$SIGN_ID" ] && [ -n "${SPOTIFYBAR_NOTARY:-}" ]; then
  echo "→ Notarizing (this can take a minute or two)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$SPOTIFYBAR_NOTARY" --wait
  echo "→ Stapling the notarization ticket"
  xcrun stapler staple "$APP"
  # Rebuild the DMG so the stapled app is the one inside it, then staple the DMG too.
  rm -f "$DMG"; mkdir -p dmg-stage; cp -R "$APP" dmg-stage/; ln -s /Applications dmg-stage/Applications
  hdiutil create -volname "SpotifyBar" -srcfolder dmg-stage -ov -format UDZO "$DMG" >/dev/null
  rm -rf dmg-stage
  xcrun stapler staple "$DMG"
  echo "✓ Notarized + stapled."
fi

echo "✓ Built $DMG  ($(lipo -archs "$BIN"))"
