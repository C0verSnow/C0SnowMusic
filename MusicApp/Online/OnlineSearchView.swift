import SwiftUI

struct OnlineSearchView: View {
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @State private var query = ""

    var body: some View {
        @Bindable var online = online
        List {
            if online.searching { ProgressView("正在搜索 YouTube…") }
            if let message = online.error {
                Text(message).foregroundStyle(.red)
                Button("重试搜索") { online.search(query, cookies: account.downloadCookies()) }
            }
            if online.results.isEmpty, !online.searching {
                ContentUnavailableView("搜索 YouTube", systemImage: "network", description: Text("输入歌名或歌手，提交后联网搜索。"))
            }
            ForEach(online.results) { track in
                OnlineTrackRow(track: track)
            }
            if !online.cached.isEmpty {
                Section("音频缓存 · 从新到旧") {
                    ForEach(online.cached) { entry in
                        OnlineTrackRow(track: entry.track)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "YouTube 歌名、歌手")
        .onSubmit(of: .search) { online.search(query, cookies: account.downloadCookies()) }
        .task { await online.refresh() }
        .safeAreaInset(edge: .bottom) {
            if online.downloadingID != nil {
                HStack {
                    ProgressView()
                    Text("正在预下载音频…").font(.caption)
                    Spacer()
                    Button("取消") { online.cancelDownload() }
                }.padding().background(.bar)
            }
        }
    }
}

private struct OnlineTrackRow: View {
    let track: OnlineTrack
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.coverURL) { image in image.resizable().scaledToFill() } placeholder: {
                Image(systemName: "music.note").font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
            }.frame(width: 72, height: 64).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.headline).lineLimit(2)
                Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if online.cached.contains(where: { $0.id == track.id }) {
                    Label("已缓存", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("播放", systemImage: "play.fill") { online.prepare(track, play: true, playback: playback, cookies: account.downloadCookies()) }
                Button("预下载", systemImage: "arrow.down.circle") { online.prepare(track, cookies: account.downloadCookies()) }
                Button("下载到资料库", systemImage: "square.and.arrow.down") { online.prepare(track, saveTo: library, cookies: account.downloadCookies()) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }.disabled(online.downloadingID != nil).accessibilityLabel("歌曲操作")
        }
        .padding(10).background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .contentShape(.rect)
        .onTapGesture { if online.downloadingID == nil { online.prepare(track, play: true, playback: playback, cookies: account.downloadCookies()) } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("播放")) { online.prepare(track, play: true, playback: playback, cookies: account.downloadCookies()) }
    }
}

struct OnlineCacheView: View {
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(PlaybackStore.self) private var playback
    var body: some View {
        List {
            Section {
                LabeledContent("缓存上限", value: "500 MB")
                LabeledContent("已用空间", value: ByteCountFormatter.string(fromByteCount: online.cacheBytes, countStyle: .file))
                Text("超过上限先删除最旧缓存。下载到资料库的歌曲不计入缓存，也不会被自动清理。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("清空音频缓存", role: .destructive) {
                    if playback.isCachedSong { playback.pause() }
                    Task { await online.clearCache() }
                }.disabled(online.downloadingID != nil)
            }
            Section("从新到旧") {
                ForEach(online.cached) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.track.title)
                        Text(entry.track.artist).font(.caption).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file)).font(.caption2)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            if playback.isCachedSong { playback.pause() }
                            Task { await online.remove(entry) }
                        }.disabled(online.downloadingID != nil)
                    }
                }
            }
        }.navigationTitle("音频缓存").task { await online.refresh() }
    }
}
