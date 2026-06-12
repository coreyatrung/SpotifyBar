# SpotifyBar

<img src="docs/icon.png" alt="SpotifyBar icon" width="120" align="right">

A tiny Spotify controller that lives in your Mac menu bar. See what's playing at a glance, and control it without ever opening the full app.

## What it does

- **Live ticker** — the current song and artist scroll past in the menu bar, with an animated equalizer and the elapsed time.
- **Now-playing panel** — click the menu bar item for album art, a draggable scrubber, play/pause/skip, and a volume slider.
- **Stays out of the way** — no Dock icon, launches into the menu bar, sips resources.

It talks to the Spotify desktop app directly on your Mac (over AppleScript), so there's **no login, no account linking, and no data leaves your machine.**

## Install

1. Download the latest **`SpotifyBar.dmg`** from the [Releases](../../releases) page.
2. Open the DMG and drag **SpotifyBar** into your **Applications** folder.
3. Launch it. The first time, macOS will ask to let SpotifyBar control Spotify — click **OK**. (That's what lets it read what's playing and control playback.)

> **First launch (un-notarized builds only):** if macOS says it "cannot verify the developer," right-click the app and choose **Open**, then **Open** again. You only need to do this once.

Requires macOS 13 (Ventura) or later, and the Spotify desktop app.

## Build from source

You don't need Xcode's interface — just the command-line tools.

```bash
git clone https://github.com/coreyatrung/SpotifyBar.git
cd SpotifyBar
./build.sh            # builds SpotifyBar.app for your Mac
open SpotifyBar.app
```

To produce a universal (Intel + Apple Silicon) DMG for distribution:

```bash
./release.sh          # builds a universal SpotifyBar.app + SpotifyBar.dmg
```

## How it works

A small AppKit menu bar app hosting SwiftUI views. A timer polls Spotify once a second via AppleScript (`NSAppleScript`) for the track, artwork URL, position, and volume, and the same channel sends play/pause/skip/seek/volume commands back. That's the whole thing — no network calls, no Spotify Web API, no credentials.

## Privacy

SpotifyBar makes no network requests of its own. The only data it touches is what the Spotify app already exposes locally, and it stays on your Mac.

## License

[MIT](LICENSE) © Corey Hearne

---

*Not affiliated with or endorsed by Spotify AB. "Spotify" is a trademark of Spotify AB.*
