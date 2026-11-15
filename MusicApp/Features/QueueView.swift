import SwiftUI

struct QueueView: View {
    @Environment(PlaybackStore.self) private var playback
    var body: some View {
        List {
            Section {
                HStack {
                    Button("随机播放", systemImage: "shuffle") { playback.toggleShuffle() }
                        .tint(playback.shuffleEnabled ? .pink : .secondary)
                        .accessibilityValue(playback.shuffleEnabled ? "已开启" : "已关闭")
                    Spacer()
                    Button(LocalizedStringKey(playback.repeatMode.title), systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat") { playback.cycleRepeat() }
                        .tint(playback.repeatMode == .off ? .secondary : .pink)
                }.buttonStyle(.bordered)
            }
            Section("播放队列") {
                ForEach(Array(playback.queue.entries.enumerated()), id: \.element.id) { index, entry in
                    if let song = playback.song(for: entry) {
                        Button { playback.jump(to: index) } label: {
                            HStack(spacing: 12) {
                                ArtworkView(id: song.artworkID).frame(width: 44, height: 44)
                                VStack(alignment: .leading) {
                                    Text(song.title).foregroundStyle(.primary)
                                    Text(song.artist).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if index == playback.currentQueueIndex { Image(systemName: playback.isPlaying ? "waveform" : "pause.fill").foregroundStyle(.pink) }
                            }
                        }
                    }
                }
                .onDelete { playback.removeQueueEntries(at: $0) }
                .onMove { playback.moveQueueEntries(from: $0, to: $1) }
            }
        }
        .localizedNavigationTitle("播放队列").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .overlay { if playback.queue.entries.isEmpty { ContentUnavailableView("队列为空", systemImage: "list.bullet") } }
    }
}
