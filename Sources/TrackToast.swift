import AppKit
import SwiftUI

/// Contents and visibility of the track-change toast.
final class TrackToastModel: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var shown = false
}

/// A borderless panel that drops out from under the menu bar item when the track changes,
/// holds for a few seconds, then fades.
///
/// It's a window of its own, so the slide and fade run through Core Animation and never
/// touch the status item — which is the expensive thing to redraw on macOS, at roughly
/// 20ms of CPU a go (see AUDIT_REPORT.md, P1). The toast exists for about four seconds a
/// track and costs nothing the rest of the time.
final class TrackToastController {
    private let model = TrackToastModel()
    private let panel: NSPanel
    private var pendingWork: DispatchWorkItem?
    private var isHovered = false

    /// Called when the card is clicked.
    var onTap: (() -> Void)?

    init(artwork: ArtworkLoader) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: ToastLayout.panelWidth,
                                height: ToastLayout.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // .nonactivatingPanel plus a borderless style mask means this can never become key,
        // so it can't swallow a keystroke from whatever you're typing in when a track changes.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false          // the card draws its own, inside the padding
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none  // the SwiftUI view owns the animation
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = TrackToastView(
            model: model,
            artwork: artwork,
            onTap: { [weak self] in self?.handleTap() },
            onHover: { [weak self] hovering in self?.setHovered(hovering) }
        )
        panel.contentView = NSHostingView(rootView: root)
        panel.orderOut(nil)
    }

    /// Show (or refresh) the toast, anchored under the status item.
    func show(title: String, artist: String, below button: NSStatusBarButton) {
        guard let window = button.window else { return }

        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrameOrigin(origin(under: buttonRect, on: window.screen ?? NSScreen.main))

        model.title = title
        model.artist = artist

        pendingWork?.cancel()
        isHovered = false

        if !panel.isVisible {
            model.shown = false          // start collapsed so the drop-in is visible
            panel.orderFrontRegardless()
            // One turn of the run loop, so the panel is on screen before the animation
            // starts. Without it the first frame lands already in its final position.
            DispatchQueue.main.async { [weak self] in self?.model.shown = true }
        } else {
            // Already up for the previous track — just swap the text and restart the clock.
            model.shown = true
        }

        scheduleDismiss()
    }

    func hide() {
        pendingWork?.cancel()
        isHovered = false
        guard panel.isVisible else { return }
        model.shown = false
        after(ToastLayout.transition) { [weak self] in
            guard let self, !self.model.shown else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Positioning

    /// The card's final position is `slide` points below the panel's top edge, so the panel
    /// sits that much higher than the card does.
    private func origin(under buttonRect: NSRect, on screen: NSScreen?) -> NSPoint {
        let cardTop = buttonRect.minY - ToastLayout.menuBarGap
        var x = buttonRect.midX - ToastLayout.panelWidth / 2

        if let visible = screen?.visibleFrame {
            let margin = ToastLayout.screenMargin
            let highest = visible.maxX - ToastLayout.panelWidth - margin
            x = min(max(x, visible.minX + margin), max(highest, visible.minX + margin))
        }
        // The panel extends `shadowMargin` below the card so the shadow has room.
        return NSPoint(x: x, y: cardTop - ToastLayout.height - ToastLayout.shadowMargin)
    }

    // MARK: - Timing

    private func scheduleDismiss() {
        after(ToastLayout.hold) { [weak self] in self?.dismiss() }
    }

    private func dismiss() {
        guard !isHovered else { return }   // pointer is on it, leave it up
        hide()
    }

    private func setHovered(_ hovering: Bool) {
        isHovered = hovering
        if hovering {
            pendingWork?.cancel()
            model.shown = true
        } else {
            scheduleDismiss()
        }
    }

    private func handleTap() {
        onTap?()
        hide()
    }

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        pendingWork?.cancel()
        let work = DispatchWorkItem(block: block)
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

// MARK: - View

struct TrackToastView: View {
    @ObservedObject var model: TrackToastModel
    @ObservedObject var artwork: ArtworkLoader
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        card
            .offset(y: model.shown ? ToastLayout.slide : 0)
            .opacity(model.shown ? 1 : 0)
            .animation(.easeInOut(duration: ToastLayout.transition), value: model.shown)
            .frame(width: ToastLayout.panelWidth,
                   height: ToastLayout.panelHeight,
                   alignment: .top)
    }

    private var card: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
                Text(model.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(ToastLayout.padding)
        .frame(width: ToastLayout.width, height: ToastLayout.height, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: ToastLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ToastLayout.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover(perform: onHover)
        .help("Open Spotify")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25))
            if let cover = artwork.cover {
                Image(nsImage: cover).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: ToastLayout.artworkSide, height: ToastLayout.artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Album-tinted, like the now-playing panel — but built from opaque layers rather than
    /// a vibrancy material.
    ///
    /// The panel behind this is transparent, so `.ultraThinMaterial` sampled whatever was on
    /// the desktop underneath and washed the card out to a pale grey over light content. An
    /// opaque base keeps it dark and legible wherever it lands.
    private var background: some View {
        ZStack {
            Color.black
            if let backdrop = artwork.background {
                Image(nsImage: backdrop).resizable().scaledToFill().opacity(0.55)
            }
            LinearGradient(
                colors: [.black.opacity(0.3), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}
