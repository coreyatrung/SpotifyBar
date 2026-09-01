#!/bin/bash
# Runs the unit tests over the pure logic. No Xcode, no SwiftPM — same spirit as build.sh.
set -e
cd "$(dirname "$0")"

BIN="$(mktemp -d)/spotifybar-tests"

echo "→ Compiling tests"
swiftc -swift-version 5 \
  Sources/SpotifyController.swift \
  Sources/TrackChangeDetector.swift \
  Sources/Formatting.swift \
  Tests/main.swift \
  -o "$BIN"

echo "→ Running"
"$BIN"
