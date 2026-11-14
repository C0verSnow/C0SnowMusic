import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var importing = false
    @State private var lines: [LyricLine] = []
    @State private var manualUntil = Date.distantPast
    private var activeID: Int? { lines.last { $0.time <= playback.currentTime }?.id }

    var body: some View {
        Group {
            if let song = playback.currentSong {
                ScrollViewReader { proxy in
                    ScrollView {
                        if !lines.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                ForEach(lines) { line in
                                    Button { playback.seek(to: line.time); manualUntil = .distantPast } label: {
                                        Text(line.text.isEmpty ? "♪" : line.text).font(.title.bold())
                                            .foregroundStyle(activeID == line.id ? .primary : .secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain).id(line.id)
                                    .accessibilityLabel("\(line.text)，跳到 \(playbackTime(line.time))")
                                }
                            }.padding(28)
                        } else if !song.lyrics.isEmpty {
                            Text(song.lyrics).font(.title2).lineSpacing(14).frame(maxWidth: .infinity, alignment: .leading).padding(28)
                        } else {
                            ContentUnavailableView("暂无歌词", systemImage: "quote.bubble", description: Text("可导入 LRC 文件，或使用音频内嵌歌词。"))
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting || phase == .tracking || phase == .decelerating { manualUntil = .now.addingTimeInterval(6) }
                    }
                    .onChange(of: activeID) { _, id in
                        guard let id, playback.isPlaying, Date.now >= manualUntil else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .task(id: song.id.uuidString + song.lyrics) { lines = LRCParser.parse(song.lyrics) }
                }
            } else { ContentUnavailableView("尚未选择歌曲", systemImage: "music.note") }
        }
        .navigationTitle("歌词").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("导入 LRC", systemImage: "plus") { importing = true } } }
        .sheet(isPresented: $importing) {
            DocumentImportPicker(types: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]) { urls in
                importing = false
                guard let song = playback.currentSong, let url = urls.first else { return }
                Task {
                    do {
                        let lyrics = try await library.importer.readLyrics(url)
                        library.transaction { song.lyrics = lyrics }
                    } catch { library.error = error.localizedDescription }
                }
            } onCancel: { importing = false }
        }
    }
}
