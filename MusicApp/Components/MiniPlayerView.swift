import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Binding var expanded: Bool
    var body: some View {
        if let song = playback.currentSong {
            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    Button { expanded = true } label: {
                        HStack(spacing: 10) {
                            ArtworkView(id: song.artworkID, cornerRadius: 6).frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                if placement != .inline { Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open player: \(song.title), \(song.artist)")
                    .accessibilityIdentifier("miniPlayer")
                    Group {
                        Button(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") { playback.toggle() }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44).disabled(playback.isLoading)
                    }
                    if placement != .inline {
                        Button("Next", systemImage: "forward.fill") { playback.next() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        }
    }
}
