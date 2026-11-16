import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var importing = false
    @State private var onlineSearch = false
    @State private var calibrating = false
    @State private var lines: [LyricLine] = []
    @State private var manualUntil = Date.distantPast
    @State private var offset: Double = 0
    private var timeline: LyricTimeline { LyricTimeline(lines: lines, offset: offset) }
    private var activeID: Int? { timeline.activeLine(at: playback.currentTime) }

    var body: some View {
        Group {
            if let song = playback.currentSong {
                ScrollViewReader { proxy in
                    ScrollView {
                        if !lines.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 28) {
                                ForEach(lines) { line in
                                    Button { playback.seek(to: timeline.playbackTime(for: line)); manualUntil = .distantPast } label: {
                                        Text(line.text.isEmpty ? "♪" : line.text).font(.title.bold())
                                            .foregroundStyle(activeID == line.id ? .primary : .secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain).id(line.id)
                                    .accessibilityIdentifier("lyric-line-\(line.id)")
                                    .accessibilityValue(activeID == line.id ? "当前歌词" : "")
                                    .accessibilityLabel("\(line.text)，跳到 \(playbackTime(timeline.playbackTime(for: line)))")
                                }
                            }.padding(28)
                        } else if !song.lyrics.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("纯文本歌词 · 此版本没有同步时间戳").font(.caption).foregroundStyle(.secondary)
                                Text(song.lyrics).font(.title2).lineSpacing(14)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                        } else {
                            ContentUnavailableView {
                                Label("暂无歌词", systemImage: "quote.bubble")
                            } description: {
                                Text("可在线查找同步歌词、导入 LRC 文件，或读取音频内嵌歌词。")
                            } actions: {
                                Button("在线查找歌词与封面", systemImage: "magnifyingglass") { onlineSearch = true }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting || phase == .tracking || phase == .decelerating { manualUntil = .now.addingTimeInterval(6) }
                    }
                    .onChange(of: activeID) { _, id in
                        guard let id, playback.isPlaying, Date.now >= manualUntil else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if calibrating, !lines.isEmpty {
                            VStack(spacing: 10) {
                                Stepper(value: $offset, in: -30...30, step: 0.5) {
                                    Text(offset == 0 ? "与原时间戳一致" : "歌词\(offset > 0 ? "延后" : "提前") \(String(format: "%.1f", abs(offset))) 秒")
                                }
                                HStack {
                                    Button("恢复原时间戳") { offset = 0 }
                                    Spacer()
                                    Button("跟随当前播放") { manualUntil = .distantPast; if let activeID { proxy.scrollTo(activeID, anchor: .center) } }
                                }.font(.caption)
                            }.padding().background(.bar)
                        }
                    }
                    .task(id: song.id.uuidString + song.lyrics) {
                        lines = LRCParser.parse(song.lyrics)
                        offset = UserDefaults.standard.double(forKey: "lyricsOffset.\(song.id)")
                        manualUntil = .distantPast
                        if let activeID { proxy.scrollTo(activeID, anchor: .center) }
                    }
                    .onChange(of: offset) { _, value in UserDefaults.standard.set(value, forKey: "lyricsOffset.\(song.id)") }
                }
                .sheet(isPresented: $onlineSearch) { NavigationStack { MusicLookupView(song: song) } }
            } else { ContentUnavailableView("尚未选择歌曲", systemImage: "music.note") }
        }
        .localizedNavigationTitle("歌词").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("导入 LRC", systemImage: "plus") { importing = true } }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("查找歌词与封面", systemImage: "magnifyingglass") { onlineSearch = true }
                    .disabled(playback.currentSong == nil)
                    .accessibilityIdentifier("lookupLyrics")
                Spacer()
                if !lines.isEmpty { Button("歌词时间校准", systemImage: "slider.horizontal.3") { calibrating.toggle() } }
            }
        }
        .sheet(isPresented: $importing) {
            DocumentImportPicker(types: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]) { urls in
                importing = false
                guard let song = playback.currentSong, let url = urls.first else { return }
                Task {
                    do {
                        let lyrics = try await library.importer.readLyrics(url)
                        if playback.isCachedSong { try playback.setCachedLyrics(lyrics, for: song) }
                        else { library.transaction { song.lyrics = lyrics } }
                    } catch { library.error = error.localizedDescription }
                }
            } onCancel: { importing = false }
        }
    }
}
