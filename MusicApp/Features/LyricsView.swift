import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
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
                                    .accessibilityValue(activeID == line.id ? "Current lyric" : "")
                                    .accessibilityLabel("\(line.text), skip to \(playbackTime(timeline.playbackTime(for: line)))")
                                }
                            }.padding(28)
                        } else if !song.lyrics.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("Plain lyrics · No synchronized timestamps").font(.caption).foregroundStyle(.secondary)
                                Text(song.lyrics).font(.title2).lineSpacing(14)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                        } else {
                            ContentUnavailableView {
                                Label("No lyrics", systemImage: "quote.bubble")
                            } description: {
                                Text("Lyrics aren't available for this song. You can find or add lyrics in Lyrics Settings.")
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
                                    Text(offset == 0 ? "Original timing" : "Lyrics \(offset > 0 ? "later" : "earlier") by \(String(format: "%.1f", abs(offset))) seconds")
                                }
                                HStack {
                                    Button("Reset timing") { offset = 0 }
                                    Spacer()
                                    Button("Follow playback") { manualUntil = .distantPast; if let activeID { proxy.scrollTo(activeID, anchor: .center) } }
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
            } else { MusicUnavailableView(title: "No song selected") }
        }
        .localizedNavigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Menu {
                    Button("Find Lyrics and Artwork", systemImage: "magnifyingglass") { onlineSearch = true }
                        .accessibilityIdentifier("lookupLyrics")
                    Button("Import LRC", systemImage: "plus") { importing = true }
                    if !lines.isEmpty {
                        Button("Lyrics Timing", systemImage: "slider.horizontal.3") { calibrating.toggle() }
                    }
                    Button("Close Lyrics", systemImage: "xmark") { dismiss() }
                } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                    .disabled(playback.currentSong == nil)
                    .accessibilityLabel("Lyrics Settings")
                    .accessibilityIdentifier("lyricsSettings")
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
