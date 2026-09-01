# SpotifyBar

<img src="docs/icon.png" alt="SpotifyBar icon" width="120" align="right">

A tiny Spotify controller that lives in your Mac menu bar. See what's playing at a glance, and control it without ever opening the full app.

## What it does

- **Live ticker** — the current song and artist scroll past in the menu bar, with an animated equalizer and the elapsed time.
- **Now-playing panel** — click the menu bar item for album art, a draggable scrubber, play/pause/skip, and a volume slider.
- **Track-change toast** — when the song changes, a small card drops out from under the menu bar icon with the album art, title and artist, then fades. Hover to keep it up, click to jump to Spotify, and turn it off from the right-click menu.
- **Stays out of the way** — no Dock icon, launches into the menu bar, and stays quiet: it won't interrupt you when the panel is already open, when Spotify itself is in front, or when you're in a fullscreen app, and it never steals keyboard focus.

It talks to the Spotify desktop app directly on your Mac (over AppleScript), so there's **no login and no account linking.**

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
./test.sh             # runs the unit tests
open SpotifyBar.app
```

Rebuilding changes the ad-hoc signature, so macOS will usually ask for Automation access again. That's expected.

To produce a universal (Intel + Apple Silicon) DMG for distribution:

```bash
./release.sh          # builds a universal SpotifyBar.app + SpotifyBar.dmg
```

Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist` before cutting a release — `release.sh` prints both so you can tell builds apart once they're out in the world.

## How it works

A small AppKit menu bar app hosting SwiftUI views. A timer polls Spotify via AppleScript (`NSAppleScript`) for the track, artwork URL, position, and volume, and the same channel sends play/pause/skip/seek/volume commands back. Polling runs on a background queue so a busy Spotify can't freeze the menu bar, and it backs off when there's nothing to watch — once a second while music is playing, every three seconds when it's paused, every five when Spotify is closed.

The one thing that isn't local is the album art: the AppleScript gives us a URL, and the app downloads that image from Spotify's CDN. No Spotify Web API, no credentials, no account.

## Privacy

Everything SpotifyBar knows about your listening comes from the Spotify app already running on your Mac, and none of it is sent anywhere. There's no account, no login, no analytics, and no telemetry.

SpotifyBar makes exactly one kind of network request: it downloads the current album cover from Spotify's image CDN, using the URL Spotify itself hands over. That's an anonymous image fetch, once per track. Nothing else leaves your machine.

## License

[MIT](LICENSE) © Corey Hearne

---

*Not affiliated with or endorsed by Spotify AB. "Spotify" is a trademark of Spotify AB.*
