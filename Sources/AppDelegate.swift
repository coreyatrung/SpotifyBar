import AppKit
import SwiftUI

/// Hosts the menu bar SwiftUI label but passes clicks through to the status button underneath,
/// so clicking anywhere on the equalizer/ticker still toggles the popover.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let state = PlayerState()
    private let controller = SpotifyController()
    private let artwork = ArtworkLoader()
    private lazy var toast = TrackToastController(artwork: artwork)
    private var timer: Timer?
    private var pollInterval: TimeInterval = 0

    private var trackChanges = TrackChangeDetector()
    private static let notificationsDefaultsKey = "showTrackNotifications"
    private static let spotifyBundleID = "com.spotify.client"

    /// Poll fast only when there's something worth watching. The old fixed 1Hz tick ran
    /// at the same rate with Spotify closed, paused, and the panel shut.
    private enum Poll {
        static let playing: TimeInterval = 1
        static let idle: TimeInterval = 3       // running but paused, or a failed read
        static let dormant: TimeInterval = 5    // Spotify closed, or no permission
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = MenuBarLayout.idleWidth

        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let host = PassthroughHostingView(rootView: MenuBarLabel(state: state))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }

        popover.behavior = .transient
        let content = NSHostingController(
            rootView: NowPlayingView(state: state, artwork: artwork, controller: controller)
        )
        content.sizingOptions = []   // don't let the controller resize the popover to fit
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.playerHeight)
        popover.contentViewController = content

        // A command failing on -1743 means Automation access was pulled mid-session.
        // Re-read so the panel switches to the permission prompt instead of the
        // buttons silently doing nothing.
        controller.onPermissionDenied = { [weak self] in self?.refresh() }
        toast.onTap = { [weak self] in self?.controller.activateSpotify() }

        // This kicks off the first AppleScript call, which is what triggers the macOS
        // Automation consent dialog. It now runs on a background queue, so launch
        // isn't blocked waiting for the user to click the dialog.
        refresh()
        schedulePolling(every: Poll.playing)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func refresh() {
        controller.snapshot { [weak self] snapshot in
            guard let self else { return }
            self.state.apply(snapshot)
            self.artwork.load(snapshot.artworkURL)
            self.announceTrackChangeIfNeeded(snapshot)
            self.layoutMenuBar()
            self.updatePopoverSize()
            self.schedulePolling(every: self.desiredInterval)
        }
    }

    private var desiredInterval: TimeInterval {
        if popover.isShown { return Poll.playing }
        switch state.status {
        case .ok: return state.isPlaying ? Poll.playing : Poll.idle
        case .unreadable: return Poll.idle
        case .notRunning, .permissionDenied: return Poll.dormant
        }
    }

    private func schedulePolling(every interval: TimeInterval) {
        guard interval != pollInterval else { return }
        pollInterval = interval
        timer?.invalidate()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // .common rather than the .default that Timer.scheduledTimer uses. In .default the
        // timer stops firing while a menu is tracking or a slider is being dragged, so the
        // elapsed time froze whenever the right-click menu was open or the scrubber held.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Track change

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.notificationsDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.notificationsDefaultsKey) }
    }

    /// Fires the toast on a genuine track change. The rules live in TrackChangeDetector.
    private func announceTrackChangeIfNeeded(_ snapshot: PlayerSnapshot) {
        guard trackChanges.shouldAnnounce(snapshot), notificationsEnabled else { return }
        guard !popover.isShown else { return }        // already looking at the panel
        guard !isSpotifyFrontmost else { return }     // already looking at Spotify
        guard isStatusItemOnScreen else { return }    // nothing to drop out of
        guard let button = statusItem.button else { return }

        toast.show(title: snapshot.title, artist: snapshot.artist, below: button)
    }

    private var isSpotifyFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.spotifyBundleID
    }

    /// Whether the status item is actually on screen.
    ///
    /// In a fullscreen space the menu bar is hidden, so a toast anchored under the status
    /// item has nothing to anchor to — macOS won't draw it over the fullscreen space anyway,
    /// so it would be a notification the user never sees.
    ///
    /// Measured, because the obvious signals don't work: with another app fullscreen,
    /// `NSMenu.menuBarVisible()` still returns true and the screen's `visibleFrame` is still
    /// inset by the menu bar height. The status item's own window is the thing that knows —
    /// it reports `.occluded`. This also covers a sleeping display, where the answer is the
    /// same.
    private var isStatusItemOnScreen: Bool {
        guard let window = statusItem.button?.window else { return false }
        return window.occlusionState.contains(.visible)
    }

    @objc private func toggleNotifications() {
        notificationsEnabled.toggle()
        if !notificationsEnabled { toast.hide() }
    }

    // MARK: - Layout

    /// Size the menu bar item to exactly what it needs: equalizer + ticker window + time.
    private func layoutMenuBar() {
        guard state.isRunning, !state.title.isEmpty else {
            state.setMenuLayout(tickerWindow: 0, scrollWidth: 0, width: MenuBarLayout.idleWidth)
            setStatusItemLength(MenuBarLayout.idleWidth)
            return
        }
        let ticker = MenuBarLabel.ticker(title: state.title, artist: state.artist)
        let textWidth = width(ticker, MenuBarLayout.tickerNSFont)
        let tickerWidth = min(textWidth, MenuBarLayout.maxTickerWidth)
        let timeWidth = width(TimeFormat.mmss(state.position), MenuBarLayout.timeNSFont)
        let total = MenuBarLayout.totalWidth(ticker: tickerWidth, time: timeWidth)

        // Only scroll when the title was actually clipped. The marquee measures nothing
        // itself, so it needs the full distance handed to it.
        let separator = width(MenuBarLayout.tickerSeparator, MenuBarLayout.tickerNSFont)
        let scrollWidth = textWidth > tickerWidth + 1 ? textWidth + separator : 0

        state.setMenuLayout(tickerWindow: tickerWidth, scrollWidth: scrollWidth, width: total)
        setStatusItemLength(total)
    }

    private func setStatusItemLength(_ length: CGFloat) {
        if statusItem.length != length { statusItem.length = length }
    }

    private func width(_ string: String, _ font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The permission prompt is roughly half the height of the player, and the popover is
    /// pinned to a fixed size, so it used to float in a large empty panel — which is the
    /// first thing every new user sees.
    private func updatePopoverSize() {
        let height = state.permissionDenied ? PanelLayout.permissionHeight : PanelLayout.playerHeight
        let size = NSSize(width: PanelLayout.width, height: height)
        if popover.contentSize != size { popover.contentSize = size }
    }

    // MARK: - Clicks

    // Left-click opens the now-playing panel; right- or control-click shows a menu.
    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isSecondary {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        toast.hide()

        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Spotify", action: #selector(openSpotify), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let notify = NSMenuItem(title: "Notify on Track Change",
                                action: #selector(toggleNotifications),
                                keyEquivalent: "")
        notify.target = self
        notify.state = notificationsEnabled ? .on : .off
        menu.addItem(notify)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SpotifyBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Pop the menu up directly. The previous approach attached it to the status item,
        // faked a click, then detached it — which only worked because menu tracking is
        // modal. If tracking had ever returned early the menu would have stayed attached
        // and left-click would have stopped opening the popover for good.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func openSpotify() {
        controller.activateSpotify()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            schedulePolling(every: desiredInterval)
        } else {
            toast.hide()   // the panel is about to open in the same place
            updatePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            refresh()
        }
    }
}
