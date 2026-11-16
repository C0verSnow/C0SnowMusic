import SwiftUI
import AVFAudio

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
            .padding(.horizontal, 12).padding(.vertical, 4).tint(.primary)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "music.note").font(.title3).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32).background(.quaternary, in: .rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "iPhone")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Text("Not Playing").font(.caption.bold())
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("Play", systemImage: "play.fill") { }.labelStyle(.iconOnly).disabled(true).frame(width: 32, height: 36)
                if placement != .inline {
                    Button("Next", systemImage: "forward.fill") { }.labelStyle(.iconOnly).disabled(true).frame(width: 32, height: 36)
                }
            }.padding(.horizontal, 12).padding(.vertical, 4).accessibilityIdentifier("emptyMiniPlayer")
        }
    }
}
