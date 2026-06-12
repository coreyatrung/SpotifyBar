import AppKit
import SwiftUI

/// Hosts the menu bar SwiftUI label but passes clicks through to the status button underneath,
/// so clicking anywhere on the equalizer/ticker still toggles the popover.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private let state = PlayerState()
    private let controller = SpotifyController()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self

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
        let content = NSHostingController(rootView: NowPlayingView(state: state, controller: controller))
        content.sizingOptions = []   // don't let the controller resize the popover to fit; keep it fixed
        popover.contentSize = NSSize(width: 280, height: 460)
        popover.contentViewController = content

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private let tickerFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    // Monospaced digits so the measured width matches the displayed (monospaced) time
    // and doesn't change as the seconds tick — otherwise the whole item wobbles each second.
    private let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let maxTicker: CGFloat = 150   // cap so a long title can't eat the menu bar

    private func refresh() {
        state.apply(controller.currentSnapshot())
        layoutMenuBar()
    }

    /// Size the menu bar item to exactly what it needs: equalizer + ticker window + time.
    private func layoutMenuBar() {
        guard state.isRunning, !state.title.isEmpty else {
            state.tickerWindow = 0
            state.menuWidth = 30
            statusItem.length = 30
            return
        }
        let ticker = "\(state.title) — \(state.artist)"
        let window = min(width(ticker, tickerFont), maxTicker)
        let timeW = width(MenuBarLabel.fmt(state.position), timeFont)
        // 6 (lead) + 18 (eq) + 6 + window + 6 + time + 6 (trail)
        let total = 6 + 18 + 6 + window + 6 + timeW + 6
        state.tickerWindow = window
        state.menuWidth = total
        statusItem.length = total
    }

    private func width(_ s: String, _ font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
