import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var state: PlayerState
    /// Shared with the track-change toast and driven by AppDelegate, so the artwork for a
    /// track is fetched once and both views use it.
    @ObservedObject var artwork: ArtworkLoader
    let controller: SpotifyController

    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var localVolume: Double = 50
    @State private var isVolumeEditing = false

    var body: some View {
        Group {
            if state.permissionDenied {
                permissionPrompt.padding(PanelLayout.padding)
            } else {
                player
            }
        }
        .frame(width: PanelLayout.width)
        .background(background)
        .onAppear { localVolume = state.volume }
    }

    // MARK: - Player

    private var player: some View {
        VStack(spacing: 14) {
            artworkView
            trackInfo
            seekBar
            controls
            volumeBar
        }
        .padding(PanelLayout.padding)
    }

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.25))
            if let cover = artwork.cover {
                Image(nsImage: cover).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: PanelLayout.artworkSide, height: PanelLayout.artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .onTapGesture { controller.activateSpotify() }
        .help("Open Spotify")
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 44))
            .foregroundStyle(.white.opacity(0.6))
    }

    private var trackInfo: some View {
        VStack(spacing: 2) {
            Text(displayTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
            Text(displaySubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    /// A failed read used to be reported as "Spotify not open", which was wrong and
    /// unhelpful whenever Spotify was open but a property came back empty.
    private var displayTitle: String {
        switch state.status {
        case .notRunning: return "Spotify not open"
        case .permissionDenied: return "Permission needed"
        case .unreadable: return "Can't read Spotify"
        case .ok: return state.title.isEmpty ? "Nothing playing" : state.title
        }
    }

    private var displaySubtitle: String {
        switch state.status {
        case .ok: return state.artist
        case .unreadable: return "Spotify didn't answer — try again in a moment"
        default: return ""
        }
    }

    // MARK: - Seek bar

    private var seekBar: some View {
        let shown = isScrubbing ? scrubPosition : state.position
        return VStack(spacing: 6) {
            GeometryReader { geometry in
                let duration = state.duration
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: geometry.size.width * clampedFraction(shown, of: duration))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubPosition = fractionAlong(value.location.x, width: geometry.size.width) * duration
                        }
                        .onEnded { value in
                            let target = fractionAlong(value.location.x, width: geometry.size.width) * duration
                            controller.seek(to: target)
                            // Show it straight away and ignore polls until Spotify catches up.
                            state.holdPosition(target)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(TimeFormat.mmss(shown))
                Spacer()
                Text("-" + TimeFormat.mmss(max(state.duration - shown, 0)))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
        .opacity(state.duration > 0 ? 1 : 0)
        // The transport buttons were disabled when Spotify was closed but the scrubber
        // wasn't, so it could be dragged, firing seeks into nothing.
        .disabled(!state.isRunning || state.duration <= 0)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 28) {
            Button { controller.previous() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            Button {
                state.optimisticallyTogglePlayback()
                controller.playPause()
            } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            Button { controller.next() } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .disabled(!state.isRunning)
    }

    // MARK: - Volume

    private var volumeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.caption2)
            Slider(value: $localVolume, in: 0...100) { editing in
                isVolumeEditing = editing
                guard !editing else { return }
                controller.setVolume(Int(localVolume.rounded()))
                // Same hold as the scrubber. Without it the next poll reported the old
                // volume and the slider jumped back before jumping forward again.
                state.holdVolume(localVolume)
            }
            .tint(.white)
            Image(systemName: "speaker.wave.3.fill").font(.caption2)
        }
        .foregroundStyle(.white.opacity(0.7))
        .disabled(!state.isRunning)
        .onChange(of: state.volume) { newVolume in
            if !isVolumeEditing { localVolume = newVolume }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black
            // Already blurred and downsampled by ArtworkLoader, so there's no per-frame
            // GPU blur here any more.
            if let backdrop = artwork.background {
                Image(nsImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.7)
            }
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipped()
    }

    // MARK: - Permission prompt

    private var permissionPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.8))
            Text("Let SpotifyBar control Spotify")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Open Privacy settings, find SpotifyBar under Automation, and switch on Spotify.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Open Automation Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 12)
    }
}
