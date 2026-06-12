import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var state: PlayerState
    let controller: SpotifyController

    @State private var scrubPos: Double = 0
    @State private var isScrubbing = false
    @State private var localVolume: Double = 50
    @State private var isVolEditing = false

    var body: some View {
        Group {
            if state.permissionDenied {
                permissionPrompt.padding(16)
            } else {
                player
            }
        }
        .frame(width: 280)
        .background(background)
    }

    // MARK: - Player

    private var player: some View {
        VStack(spacing: 14) {
            artwork
            trackInfo
            seekBar
            controls
            volumeBar
        }
        .padding(16)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.25))
            if let url = URL(string: state.artworkURL), !state.artworkURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 220, height: 220)
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
            Text(state.artist)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private var displayTitle: String {
        if !state.isRunning { return "Spotify not open" }
        if state.title.isEmpty { return "Nothing playing" }
        return state.title
    }

    // MARK: - Seek bar

    private var seekBar: some View {
        let shown = isScrubbing ? scrubPos : state.position
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let dur = max(state.duration, 1)
                let fraction = min(max(shown / dur, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: geo.size.width * fraction)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            isScrubbing = true
                            scrubPos = frac(v.location.x, geo.size.width) * dur
                        }
                        .onEnded { v in
                            let target = frac(v.location.x, geo.size.width) * dur
                            scrubPos = target
                            controller.seek(to: target)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isScrubbing = false }
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(fmt(shown))
                Spacer()
                Text("-" + fmt(max(state.duration - shown, 0)))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
        .opacity(state.duration > 0 ? 1 : 0)
    }

    private func frac(_ x: CGFloat, _ w: CGFloat) -> Double {
        guard w > 0 else { return 0 }
        return Double(min(max(x / w, 0), 1))
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 28) {
            Button { controller.previous() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            Button {
                state.stateValue = state.isPlaying ? .paused : .playing   // optimistic flip
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
                isVolEditing = editing
                if !editing { controller.setVolume(Int(localVolume)) }
            }
            .tint(.white)
            Image(systemName: "speaker.wave.3.fill").font(.caption2)
        }
        .foregroundStyle(.white.opacity(0.7))
        .disabled(!state.isRunning)
        .onChange(of: state.volume) { newVolume in
            if !isVolEditing { localVolume = newVolume }
        }
        .onAppear { localVolume = state.volume }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            if let url = URL(string: state.artworkURL), !state.artworkURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Color.black
                    }
                }
                .blur(radius: 40)
                .opacity(0.7)
            } else {
                Color.black
            }
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipped()
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
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
