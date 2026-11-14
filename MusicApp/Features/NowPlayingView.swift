import SwiftUI
import MediaPlayer
import AVKit

struct NowPlayingView: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel: PlayerPanel?
    @State private var dragOffset: CGFloat = 0
    @State private var tint = Color.indigo
    @State private var editMetadata = false
    @State private var addingToPlaylist = false
    @State private var scrubPosition: Double?
    @ScaledMetric(relativeTo: .body) private var controlSize = 30

    var body: some View {
        GeometryReader { geometry in
            if let song = playback.currentSong {
                ScrollView {
                    VStack(spacing: 26) {
                        Button("收起播放器", systemImage: "chevron.down") { dismiss() }
                            .labelStyle(.iconOnly).font(.title3.bold()).frame(width: 64, height: 44)
                            .accessibilityIdentifier("collapsePlayer")
                        ArtworkView(id: song.artworkID, thumbnail: false, cornerRadius: 14)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: min(geometry.size.width - 64, geometry.size.height * 0.40))
                            .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
                            .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.94)
                            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: playback.isPlaying)
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(song.title).font(.title2.bold()).lineLimit(3)
                                Text(song.artist).font(.title3).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(song.isFavorite ? "取消收藏" : "收藏", systemImage: song.isFavorite ? "star.fill" : "star") { library.toggleFavorite(song) }
                                .labelStyle(.iconOnly).font(.title3).frame(width: 44, height: 44)
                            Menu {
                                Button("添加到播放列表", systemImage: "text.badge.plus") { addingToPlaylist = true }
                                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") { playback.enqueue(song, next: true) }
                                Button("编辑歌曲信息", systemImage: "pencil") { editMetadata = true }
                                ShareLink(item: library.files.url(for: song.fileRelativePath)) { Label("分享音频", systemImage: "square.and.arrow.up") }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }
                            .accessibilityLabel("歌曲操作")
                        }
                        progress
                        HStack {
                            Button("上一首", systemImage: "backward.fill") { playback.previous() }.font(.system(size: controlSize))
                            Spacer()
                            Button(playback.isPlaying ? "暂停" : "播放", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") { playback.toggle() }
                                .font(.system(size: controlSize * 1.55)).frame(minWidth: 72, minHeight: 64)
                                .accessibilityIdentifier("playerPlayPause")
                                .disabled(playback.isLoading)
                            Spacer()
                            Button("下一首", systemImage: "forward.fill") { playback.next() }.font(.system(size: controlSize))
                        }.labelStyle(.iconOnly).padding(.horizontal, 20)
                        SystemVolumeView().frame(height: 44).accessibilityLabel("系统音量")
                        HStack {
                            Button("歌词", systemImage: "quote.bubble") { panel = .lyrics }.accessibilityIdentifier("showLyrics")
                            Spacer()
                            AirPlayView().frame(width: 44, height: 44).accessibilityLabel("选择音频输出设备")
                            Spacer()
                            Button("播放队列", systemImage: "list.bullet") { panel = .queue }.accessibilityIdentifier("showQueue")
                        }.labelStyle(.iconOnly).font(.title2).frame(minHeight: 44)
                    }
                    .padding(.horizontal, 32).padding(.bottom, 28)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
                .background {
                    LinearGradient(colors: [tint.opacity(0.8), tint.opacity(0.28), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(.black.opacity(0.35)).ignoresSafeArea()
                }
                .offset(y: dragOffset)
                .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { value in
                    if value.startLocation.y < 100, value.translation.height > 0 { dragOffset = value.translation.height }
                }.onEnded { value in
                    if value.startLocation.y < 100, value.predictedEndTranslation.height > 140 { dismiss() }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
                })
                .task(id: song.artworkID) {
                    tint = .indigo
                    if let id = song.artworkID, let payload = await ArtworkCache.shared.load(id: id, files: library.files, thumbnail: false) { tint = Color(uiColor: payload.tint) }
                }
                .onChange(of: song.id) { _, _ in scrubPosition = nil }
                .sheet(isPresented: $editMetadata) { NavigationStack { MetadataEditor(song: song) } }
                .sheet(isPresented: $addingToPlaylist) { NavigationStack { AddToPlaylistView(song: song) } }
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .sheet(item: $panel) { panel in
            NavigationStack {
                Group { if panel == .lyrics { LyricsView() } else { QueueView() } }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { self.panel = nil } } }
            }.presentationDetents([.large])
        }
        .sensoryFeedback(.selection, trigger: playback.currentSong?.id)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { scrubPosition ?? playback.currentTime }, set: { scrubPosition = $0 }), in: 0...max(playback.duration, 1)) { editing in
                if !editing, let position = scrubPosition { playback.seek(to: position); scrubPosition = nil }
            }
            .tint(.white.opacity(0.85)).accessibilityLabel("播放位置")
            .accessibilityValue(playbackTime(scrubPosition ?? playback.currentTime))
            HStack {
                Text(playbackTime(scrubPosition ?? playback.currentTime))
                Spacer()
                Text("−" + playbackTime(playback.duration - (scrubPosition ?? playback.currentTime)))
            }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
        }
    }
}

enum PlayerPanel: String, Identifiable { case lyrics, queue; var id: String { rawValue } }

struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; return view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) { }
}

struct AirPlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = .white; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
