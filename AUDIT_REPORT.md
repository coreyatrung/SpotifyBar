# SpotifyBar — Codebase Audit

**Date:** 18 August 2026
**Scope:** all 603 lines of Swift in `Sources/`, plus `build.sh`, `release.sh`, `Info.plist`, `SpotifyBar.entitlements`, `README.md`
**Build state at audit:** compiles clean for `arm64-apple-macos13.0`, zero warnings
**Status:** all 21 findings fixed, plus one more found during verification (P1 below). Version bumped to 1.1 (build 2).
**Head:** `6631968` — Add right-click menu with Quit (and Open Spotify)

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 4 |
| Medium | 9 |
| Low | 8 |
| **Total** | **21** |

All 21 are fixed. A 22nd issue — the one that actually mattered most — was found while
measuring the fixes and is written up as **P1** at the end of this report.

---

## P1 — The app burned ~50% of a CPU core, permanently

**Found during verification, not during the audit. This is the miss.**

The audit rated the performance findings Medium and moved on. Measuring the app rather than
reading it would have caught this on day one: with Spotify **paused and nothing happening**,
SpotifyBar used roughly half a CPU core, forever, for as long as it was in the menu bar.
The README claims it "sips resources".

### Measured, before and after

Sampled as CPU-seconds consumed over 10 seconds of wall clock, on an M-series Mac with a
120Hz display. The original was rebuilt from `6631968` and measured the same way.

| Scenario | Before | After |
|---|---|---|
| Spotify paused / idle | 5.02s per 10s (~50%) | 0.02s per 10s (~0.2%) |
| Spotify playing | 4.90s per 10s (~49%) | 2.91s per 10s (~29%) |
| Playing, animation disabled (floor) | — | 0.25s per 10s (~2.5%) |

### What was wrong

Two independent causes, both in `MarqueeText`:

1. **The ticker animated forever.** `TimelineView(.animation)` has no `paused:` argument and
   no rate limit, so on a ProMotion display it re-evaluated and redrew the status item 120
   times a second — while paused, while stopped, all night. The equalizer next to it was
   correctly paused when playback stopped; the ticker beside it was not.
2. **It re-measured its own text on every one of those frames.** The `GeometryReader` that
   measured the text width sat *inside* the animation timeline, so every frame re-laid-out
   the string and pushed a SwiftUI preference back up the view tree.

### What was done

- The ticker now stops when playback stops, so the app costs essentially nothing at rest.
- Text measurement moved out of the render loop entirely. `AppDelegate` already measures this
  exact string with this exact font to size the status item, so it passes the widths in. The
  `GeometryReader` and its `PreferenceKey` are gone.
- The equalizer and the ticker share one timeline instead of running two.
- That timeline is capped at 12fps.

### What is still true, and is a decision for you

29% while playing is better than 49%, but it is not good. The remaining cost is not something
a smarter implementation removes cheaply — it is what macOS charges to redraw a menu bar
status item:

| Approach, 20fps | CPU |
|---|---|
| SwiftUI hosted in the status item | ~21ms per redraw |
| Raw Core Graphics into `button.image` | ~8ms per redraw |

Both were measured directly, the second with a standalone probe. The frame rate *is* the CPU
budget, and the only two levers are how often it redraws and how it draws.

Three options, in order of how much work they are:

1. **Leave it.** 12fps, ~29% while playing, ~0.2% at rest. Costs nothing to do.
2. **Drop to 5-6fps.** Measured at ~18% while playing. The ticker becomes visibly steppy —
   at 30pt/second it moves 5-6pt per frame.
3. **Rewrite the menu bar label in Core Graphics** — draw the equalizer, ticker and time into
   an `NSImage` and set it as `statusItem.button.image`, dropping the hosted SwiftUI view.
   Roughly 2.5x cheaper per redraw, so ~12% at 12fps. It is a real rewrite of the app's
   signature UI, and it can't be checked visually on a machine with the menu bar auto-hidden.

The honest fourth option is that a continuously scrolling menu bar ticker is expensive on
macOS no matter how it's built, and the cheapest version of this app truncates the title
instead of scrolling it. That's a product call, not an engineering one.

The frame rate lives in one named constant, `MenuBarLayout.animationInterval`, with the
measurements recorded next to it.

---

## Executive summary

The code is clean for its size: no force-unwrap crash paths, no retain cycles, `[weak self]` used correctly on the only timer, sensible separation between the AppleScript controller, the observable state, and the views. Nothing here loses data or leaks secrets, so there are no Critical findings.

What's actually wrong is concentrated in one place: every interaction with Spotify is a synchronous, blocking AppleScript call on the main thread, and the read script is all-or-nothing — one missing property and the app tells the user Spotify isn't open. Alongside that, the README makes a privacy claim the code does not honour.

The most urgent item is the README, because it's a public statement about user data that is currently untrue.

---

## High

### H1 — Blocking AppleScript on the main thread, once a second, forever
`Sources/SpotifyController.swift:53`, `Sources/AppDelegate.swift:42-45`

`NSAppleScript.executeAndReturnError` runs synchronously on the calling thread. The poll timer calls it on the main thread every second, and the code comment ("the scripts are tiny and return in a few ms") is an assumption, not a guarantee.

Two consequences:

1. **If Spotify hangs or beachballs, SpotifyBar hangs with it.** The Apple event blocks until Spotify replies or the event times out. The menu bar item freezes, the popover stops responding, and nothing recovers until Spotify does.
2. **First launch blocks inside `applicationDidFinishLaunching`.** Line 42 calls `refresh()` before the run loop starts. That first Apple event is what triggers the macOS Automation consent dialog, and it blocks the main thread until the user clicks a button. The status item may not finish drawing until they do.

**Fix:** move `currentSnapshot()` onto a background queue and hop back to `@MainActor` to apply the result. Keep the first call off the launch path — kick it off the timer instead.

### H2 — One missing property kills the whole snapshot, and the UI blames it on Spotify being closed
`Sources/SpotifyController.swift:27-62`

The read script fetches seven properties in one shot and concatenates them. If any single one fails, `executeAndReturnError` returns an error and the code falls through to `return PlayerSnapshot()` — an all-defaults struct with `isRunning = false`. `NowPlayingView.displayTitle` then renders **"Spotify not open"** while Spotify is very much open and playing.

Only error `-1743` (permission denied) is special-cased. Everything else — `-1700` (can't coerce `missing value` to text), `-1728` (no such object), `-600` (app not found) — collapses into the same misleading state.

Spotify's own scripting definition types `artwork url` as `text` backed by the `coverURL` key. When that key is nil the property comes back as `missing value`, and the `&` concatenation on line 41 fails outright. Tracks most likely to hit this: free-tier ads, local files, and some podcast episodes.

*Confidence: the code path is certain from reading it. That Spotify returns `missing value` for these specific track types is highly likely but I did not reproduce it live — doing so needs a local file playing and an Automation grant for the test process.*

**Fix:** wrap each property in a `try`/`on error` that substitutes an empty string, and distinguish "script failed" from "Spotify not running" in `PlayerSnapshot` so the UI can say something truthful.

### H3 — The README's privacy claim is false
`README.md` (Privacy section, and "How it works"), contradicted by `Sources/NowPlayingView.swift:41` and `:180`

The README says:

> SpotifyBar makes no network requests of its own.

and

> That's the whole thing — no network calls, no Spotify Web API, no credentials.

The app makes network requests. `AsyncImage(url:)` is used twice — once for the album art at line 41, once again for the blurred background at line 180 — and both fetch the artwork over HTTPS from Spotify's image CDN every time the track changes. The "no Spotify Web API, no credentials" half is true. The "no network requests" half is not.

This is the finding worth fixing first. It's a public claim about user data on a distributed app, and it's wrong.

**Fix:** rewrite the Privacy section to say what actually happens — the only outbound request is fetching album artwork from Spotify's CDN, no account, no credentials, no telemetry. Optionally add a toggle to skip artwork entirely for anyone who wants the claim to be literally true.

### H4 — Polling stops while menus and drags are open
`Sources/AppDelegate.swift:43`

`Timer.scheduledTimer(withTimeInterval:repeats:block:)` schedules on the current run loop in `.default` mode only. Menu tracking and mouse-drag tracking push the run loop into `.eventTracking`, where that timer does not fire.

So: open the right-click menu and the ticker's elapsed time freezes for as long as the menu is up. Drag the volume slider or the scrubber and the same thing happens. The equalizer keeps animating because `TimelineView` is driven separately, which makes the frozen clock next to it more obvious, not less.

**Fix:** create the timer and add it explicitly with `RunLoop.main.add(timer, forMode: .common)`.

---

## Medium

### M1 — The volume slider snaps back
`Sources/NowPlayingView.swift:160-172`

Scrubbing has a guard: after a seek, `isScrubbing` stays true for 0.5s so the next poll doesn't yank the bar backwards (line 109). Volume has no equivalent. `setVolume` fires on release, `isVolEditing` goes false immediately, and if the poll lands before Spotify has applied the change, `onChange(of: state.volume)` snaps the slider back to the old value — then forward again a second later. Visible bounce.

**Fix:** mirror the scrub guard, or better, replace both with a single "ignore polled values for N ms after sending a command" rule in one place.

### M2 — Every poll invalidates every view, whether anything changed or not
`Sources/PlayerState.swift:22-33`

`apply()` assigns all nine `@Published` properties unconditionally. Each assignment fires `objectWillChange`, so a paused track with nothing happening still triggers roughly nine SwiftUI invalidations per second across both the popover and the menu bar label.

Line 29 guards `artworkURL` with an equality check, which says the author already hit this and fixed the one case with a visible symptom.

**Fix:** make `PlayerSnapshot` `Equatable` and bail out of `apply()` early when the new snapshot equals the last one, or guard each assignment the way line 29 does.

### M3 — A track title containing the delimiter silently corrupts every field after it
`Sources/SpotifyController.swift:24`, `:76-90`

Fields are joined with `|~|` and split back apart with no escaping. The `parts.count >= 9` guard passes when there are *more* than nine parts, so a title containing `|~|` shifts everything down.

Reproduced with the real parse logic on a title of `Track |~| Name`:

```
title = "Track "      artist = " Name"     album = "Artist"
artwork = "Album"     position = 0         duration = 10      volume = 200
```

Every field is wrong, artwork breaks, and `volume = 200` then feeds a `Slider(in: 0...100)`.

Unlikely input, total failure. Cheap to make impossible.

**Fix:** return a record from AppleScript instead of a delimited string, or guard `parts.count == 9` exactly and reject anything else.

### M4 — The artwork is fetched and decoded twice, then blurred at full size
`Sources/NowPlayingView.swift:41`, `:180-187`

Two separate `AsyncImage` instances point at the same URL — one for the 220×220 cover, one for the background, which then gets `.blur(radius: 40)` applied to a full-resolution image behind a fixed 280×460 popover. `URLCache` probably spares the second network round-trip, but not the second decode, and a 40pt blur on a large image is real GPU work for something the user sees at 70% opacity under a material layer.

**Fix:** load once into shared state and feed both views. Downsample hard before blurring — a 40pt blur of a 40px thumbnail looks the same at that opacity.

### M5 — Command failures vanish
`Sources/SpotifyController.swift:71-74`

`runCommand` takes an `NSDictionary?` error and drops it on the floor. Play, pause, next, previous, seek, volume, and activate all fail silently. `permissionDenied` is only ever set from the read path, so if Automation access is revoked while the app is running, the buttons simply stop working with no explanation.

**Fix:** return the error, and set `permissionDenied` on `-1743` from the command path too.

### M6 — Fixed 1Hz polling with no backoff
`Sources/AppDelegate.swift:43`

The same one-second Apple event fires whether Spotify is playing, paused, stopped, closed, or the popover has never been opened. The README claims the app "sips resources".

**Fix:** back off when there's nothing to watch — 5s when Spotify isn't running, 2-3s when paused, 1s only while playing or while the popover is visible.

### M7 — No tests at all
No test target exists.

`MenuBarLabel.fmt`, `SpotifyController.parse`, `NowPlayingView.frac`, and the width arithmetic in `layoutMenuBar` are pure functions with obvious edge cases (negative, NaN, over an hour, short/long/empty strings, malformed AppleScript output). M3 above is exactly the kind of bug a five-line parse test catches.

**Fix:** a small SwiftPM test target over the pure functions. No Spotify or UI needed.

### M8 — The right-click menu relies on modal tracking as flow control
`Sources/AppDelegate.swift:106-112`

```swift
statusItem.menu = menu
statusItem.button?.performClick(nil)
statusItem.menu = nil
```

Line 111 only runs after the menu closes, because menu tracking is modal and `performClick` blocks. That's true today and the comment shows it's deliberate, but the correctness of the whole approach rests on an unstated AppKit behaviour. If it ever returns early, `statusItem.menu` stays attached and left-click stops opening the popover permanently.

**Fix:** `NSMenu.popUp(positioning:at:in:)` relative to the status button, and never attach the menu to the status item.

### M9 — The permission screen sits in a mostly empty 460pt popover
`Sources/AppDelegate.swift:39`, `Sources/NowPlayingView.swift:209-230`

`contentSize` is pinned to 280×460 and `sizingOptions = []` stops it adapting. The permission prompt needs roughly 200pt, so it floats in a large empty panel — and this is the first thing every new user sees, before they've granted access.

**Fix:** set `popover.contentSize` from the current state, or let the permission branch size itself.

---

## Low

1. **Scrub gesture isn't disabled when Spotify is closed** — `NowPlayingView.swift:99-111`. The transport controls get `.disabled(!state.isRunning)` at line 152; the seek bar doesn't, so you can drag it and fire seeks into nothing.
2. **Command scripts are recompiled on every press** — `SpotifyController.swift:71-74`. The read script is cached in `compiledRead`; the six commands each build a fresh `NSAppleScript`.
3. **`build.sh` and `release.sh` have diverged** — `build.sh:15-30` omits `--entitlements` (so a local build has no apple-events entitlement) and omits `-target` (so it ignores the 13.0 floor in `Info.plist` and builds against whatever SDK is current). It also uses `codesign --deep`, which Apple deprecated.
4. **Misleading comment on ad-hoc signing** — `build.sh:29` says signing is "so macOS remembers the Automation permission". Ad-hoc signatures produce a new identity on each rebuild, so TCC frequently forgets and re-prompts anyway.
5. **`duration / 1000` contradicts Spotify's own sdef** — `SpotifyController.swift:39`. Spotify's scripting definition describes `duration` as "The length of the track in seconds"; the code divides by 1000, i.e. treats it as milliseconds. The code is right in practice (the sdef description is a long-standing Spotify error), but nothing records that, so it reads like a bug and invites a "fix" that breaks it. Worth a one-line comment.
6. **No validation on values interpolated into command scripts** — `SpotifyController.swift:67`. `setVolume` clamps; `seek(to:)` doesn't. A NaN duration would emit `set player position to nan`, which AppleScript rejects as an undefined variable (error -2753, confirmed) and the seek silently no-ops. Not reachable from real Spotify output today. (Scientific notation is *not* a problem here — I checked, AppleScript parses `1e-05` correctly.)
7. **Magic numbers** — `AppDelegate.swift:52` (`maxTicker = 150`), `:71` (the `6 + 18 + 6 + … + 6` padding chain), `:39` (280×460), `MenuBarLabel.swift:38-39` (equalizer speeds and phases). Fine individually; the padding chain on line 71 is the one that will silently drift out of sync with the `HStack(spacing: 6)` in `MenuBarLabel`.
8. **Version never bumped** — `Info.plist:17-20` is still `1.0` / `1` with a DMG already distributed. No mechanism to tell builds apart in the wild.

---

## What's solid

Worth stating, since it's most of the code:

- **Memory management is clean.** The single timer uses `[weak self]`, there are no retain cycles, no uncancelled subscriptions, and no listener lifecycle to leak.
- **No crash paths.** `parse` guards its array bounds, the equalizer indexes fixed 4-element arrays with a fixed 4-iteration loop, and the only implicitly-unwrapped optional (`statusItem`) is assigned before any use.
- **`fmt` handles NaN and negatives** (`MenuBarLabel.swift:29`, `NowPlayingView.swift:202`).
- **The marquee width logic is correct**, including the hysteresis between the static and scrolling branches — the separator width only enters the measurement once scrolling has started, so it can't oscillate.
- **The monospaced-digit width trick** (`AppDelegate.swift:51`) is a genuinely nice detail: measuring with the same monospaced font that's displayed is what stops the menu bar item wobbling every second.
- **No secrets anywhere.** No API keys, no tokens, no credentials, no telemetry, no analytics. The entitlements file requests exactly one thing and needs it.
- **`release.sh` is thorough** — universal binary, hardened runtime, optional Developer ID and notarization, and it correctly rebuilds the DMG after stapling the app.

---

## What changed

All 21 findings plus P1. Version bumped to 1.1 (build 2).

| # | Fix | Where |
|---|---|---|
| H1 | AppleScript moved to a private serial queue; a `with timeout of 5 seconds` wrapper; an in-flight guard so slow ticks can't stack; the launch-path read no longer blocks `applicationDidFinishLaunching` | `SpotifyController.swift`, `AppDelegate.swift` |
| H2 | Every property read inside its own `try`; new `SpotifyStatus` enum separates `notRunning` / `permissionDenied` / `unreadable`; the panel now says "Can't read Spotify" instead of lying about Spotify being closed | `SpotifyController.swift`, `NowPlayingView.swift` |
| H3 | Privacy section rewritten to state the one outbound request (album art from Spotify's CDN) | `README.md` |
| H4 | Timer moved to `RunLoop.main` in `.common` mode, so it keeps firing during menu tracking and drags | `AppDelegate.swift` |
| M1 | One `commandHold` rule covers both the scrubber and the volume slider, at 1.5s — longer than a poll interval, which the old 0.5s scrub guard wasn't | `PlayerState.swift` |
| M2 | `PlayerSnapshot` is `Equatable`; `apply` bails on an unchanged snapshot and otherwise assigns only changed fields | `PlayerState.swift` |
| M3 | Delimiter is now U+0001; field count checked exactly rather than `>=`; volume clamped to 0...100 | `SpotifyController.swift` |
| M4 | New `ArtworkLoader` fetches once per track and pre-blurs a 64px thumbnail with CoreImage, replacing two `AsyncImage` views and a per-frame 40pt GPU blur | `ArtworkLoader.swift`, `NowPlayingView.swift` |
| M5 | Command errors are no longer discarded; `-1743` from a command surfaces the permission prompt | `SpotifyController.swift`, `AppDelegate.swift` |
| M6 | Poll backs off: 1s playing, 3s paused or unreadable, 5s closed or no permission | `AppDelegate.swift` |
| M7 | 55 tests over the parser, error mapping and the pure maths, run by `./test.sh`. No Xcode, no SwiftPM | `Tests/main.swift`, `test.sh` |
| M8 | `NSMenu.popUp(positioning:at:in:)` replaces attach / fake-click / detach | `AppDelegate.swift` |
| M9 | Popover height follows the state — 250pt for the permission prompt, 460pt for the player | `AppDelegate.swift`, `Layout.swift` |
| L1 | Scrubber disabled when Spotify isn't running or the duration is unknown | `NowPlayingView.swift` |
| L2 | Static commands compiled once and cached | `SpotifyController.swift` |
| L3 | `build.sh` pins `-target $(uname -m)-apple-macos13.0`, passes `--options runtime --entitlements`, drops deprecated `--deep` | `build.sh` |
| L4 | Ad-hoc signing comment corrected — it explains the re-prompt rather than claiming to prevent it | `build.sh`, `README.md` |
| L5 | The milliseconds-vs-seconds trap documented at the division, with the sdef contradiction spelled out | `SpotifyController.swift` |
| L6 | `seek` rejects non-finite values and caps the upper bound | `SpotifyController.swift` |
| L7 | Magic numbers collected into `MenuBarLayout` / `PanelLayout`; the padding chain is now one `totalWidth` function shared by the view and the sizing code | `Layout.swift` |
| L8 | Version bumped to 1.1 (build 2); `release.sh` prints version and build; README documents bumping before a release | `Info.plist`, `release.sh`, `README.md` |
| P1 | Ticker stops when playback stops; text measurement lifted out of the render loop; one shared timeline capped at 12fps | `MenuBarLabel.swift`, `Layout.swift`, `AppDelegate.swift` |

Two findings also produced fixes beyond what was written up:

- Times now cross the AppleScript boundary as whole milliseconds. AppleScript coerces numbers
  to strings using the system decimal separator, so `1.5` arrives as `"1,5"` on a European
  Mac and `Double("1,5")` is nil — position and duration would have silently read as zero.
  Integers have no separator. (Found while rewriting for H2.)
- `clampedFraction` replaces an inline `min(max(...))` in the scrubber. Swift's `min`/`max`
  propagate NaN rather than clamping it, so a NaN duration could reach a SwiftUI
  `frame(width:)`, which is a hard error rather than a cosmetic one.

One thing worth knowing for next time: the variable name `st` cannot be used inside a
`tell application "Spotify"` block — it collides with Spotify's scripting terminology and
fails to compile with a misleading "Expected expression" error.

## Verification

- `./build.sh` — clean, zero warnings
- `./release.sh` — universal binary (`x86_64 arm64`), DMG built, v1.1 build 2
- `./test.sh` — 55/55 passing
- Read path exercised against live Spotify and parsed end-to-end: title, artist, album,
  artwork URL, `22127ms -> 0:22`, `154444ms -> 2:34`, volume 100. The 2:34 confirms the
  duration really is milliseconds, so the `/1000` is correct and must stay.
- CPU measured before and after against a rebuild of the original — see P1.

Not verified: the menu bar item was never seen rendered — the screenshots taken during
verification caught a fullscreen video covering the menu bar. (The menu bar is not
auto-hidden; an earlier draft of this report said it was, which was wrong.) Layout changes
(ticker widths, popover heights, the marquee rework) are verified by build, tests and
measurement, not by eye. Worth a look before you ship the DMG.
