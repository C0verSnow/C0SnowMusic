import SwiftUI

struct MusicLookupView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var results: [LyricsMatch] = []
    @State private var searching = false
    @State private var downloading: Int?
    @State private var error: String?
    @State private var notice: String?
    @State private var requestID = 0
    @State private var includeCover = true
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("歌曲名称", text: $title).accessibilityIdentifier("lookupTitle")
                TextField("艺术家", text: $artist).accessibilityIdentifier("lookupArtist")
                TextField("专辑（可选）", text: $album)
                Button { requestID += 1 } label: {
                    HStack { Text("搜索歌词"); Spacer(); if searching { ProgressView() } }
                }.disabled(searching || downloading != nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Toggle("同时下载缺失的封面", isOn: $includeCover)
            } footer: {
                Text("搜索会将歌名、艺术家和专辑发给 LRCLIB；封面查询使用 MusicBrainz 和 Cover Art Archive，不发送音频文件。")
            }
            .disabled(downloading != nil)
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let notice { Section { Text(notice) } }
            Section("选择歌曲版本 · 本地时长 \(playbackTime(song.duration))") {
                if !searching, results.isEmpty { Text("修改搜索信息后重试。可清空专辑扩大搜索范围。").foregroundStyle(.secondary) }
                ForEach(results) { match in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(match.trackName).font(.headline)
                        Text("\(match.artistName) · \(match.albumName)").font(.subheadline)
                        HStack {
                            Label(match.isSynced ? "同步歌词" : (match.instrumental ? "纯音乐" : "纯文本歌词"), systemImage: match.isSynced ? "clock" : "text.alignleft")
                            Spacer()
                            Text(match.duration.map(playbackTime) ?? "时长未知").monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                        if let duration = match.duration, abs(duration - song.duration) > 2 {
                            Text("时长相差 \(Int(abs(duration - song.duration))) 秒，请核对录音版本。").font(.caption).foregroundStyle(.orange)
                        } else if match.duration == nil {
                            Text("此版本未提供时长，请核对录音版本。").font(.caption).foregroundStyle(.orange)
                        }
                        Button {
                            downloadTask = Task { await apply(match) }
                        } label: {
                            HStack {
                                Text(match.text == nil ? (song.artworkID == nil ? "下载封面" : "已有封面") : "使用此版本")
                                if downloading == match.id { ProgressView() }
                            }
                        }.disabled(downloading != nil || (match.text == nil && (!includeCover || song.artworkID != nil)))
                    }.padding(.vertical, 6)
                }
            }
            Section {
                Link("歌词来源：LRCLIB", destination: URL(string: "https://lrclib.net")!)
                Link("封面来源：MusicBrainz / CAA", destination: URL(string: "https://musicbrainz.org/doc/Cover_Art_Archive")!)
                Text("先核对专辑和录音版本。下载后保存在本地；纯文本歌词不会伪造播放时间。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .localizedNavigationTitle("歌词与封面").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .onAppear {
            let query = SongLookupQuery(title: song.title, artist: song.artist, album: song.albumTitle, duration: song.duration)
            title = query.title; artist = query.artist; album = query.album
        }
        .task(id: requestID) {
            guard requestID > 0 else { return }
            searching = true; error = nil; notice = nil
            defer { searching = false }
            do {
                results = try await MusicLookupClient.shared.search(SongLookupQuery(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    artist: artist.trimmingCharacters(in: .whitespacesAndNewlines), album: album.trimmingCharacters(in: .whitespacesAndNewlines), duration: song.duration))
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onDisappear { downloadTask?.cancel() }
    }

    private func apply(_ match: LyricsMatch) async {
        downloading = match.id; error = nil; notice = nil
        defer { downloading = nil }
        library.applyDownloadedMatch(match, to: song)
        if let error = library.error { self.error = error; return }
        title = match.trackName; artist = match.artistName
        playback.refreshMediaInfo()
        notice = "歌名和艺术家已更新。"
        if match.text != nil {
            notice = (notice ?? "") + (match.isSynced ? "同步歌词已保存，可离线显示并跟随播放。" : "纯文本歌词已保存；这一版本没有可用时间戳。")
        }
        if includeCover, song.artworkID == nil {
            do {
                let data = try await MusicLookupClient.shared.cover(for: match)
                try Task.checkCancellation()
                try await library.setDownloadedCover(song, data: data)
                playback.refreshMediaInfo()
                notice = (notice.map { $0 + "\n" } ?? "") + "专辑封面已保存。"
            } catch {
                if !Task.isCancelled { self.error = "\(match.text != nil ? "歌词已保存。" : "")封面：\(error.localizedDescription)" }
            }
        }
        if match.text == nil, !includeCover { error = MusicLookupError.noLyrics.localizedDescription }
    }
}
