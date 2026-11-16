import SwiftUI

struct OnlineSearchView: View {
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @State private var query = ""

    var body: some View {
        @Bindable var online = online
        List {
            Section {
                Picker("搜索分类", selection: $online.filter) {
                    ForEach(MusicSearchFilter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                Button("重置搜索") { query = ""; online.resetSearch() }
            }
            if online.searching { ProgressView("正在搜索 YouTube…") }
            if let message = online.error {
                Text(message).foregroundStyle(.red)
                Button("重试搜索") { submit() }
            }
            if online.results.isEmpty, !online.searching {
                if query.isEmpty, !online.searchHistory.isEmpty {
                    Section("搜索历史") {
                        ForEach(online.searchHistory, id: \.self) { value in
                            Button(value) { query = value; submit() }
                        }
                        Button("清除搜索历史", role: .destructive) { online.clearSearchHistory() }
                    }
                } else {
                    ContentUnavailableView("搜索 YouTube", systemImage: "network", description: Text("输入歌名或歌手，提交后联网搜索。"))
                }
            }
            ForEach(online.sections) { section in
                Section(section.title) { ForEach(section.items) { OnlineTrackRow(track: $0) } }
            }
            if online.continuation != nil {
                Button("加载更多") { online.search(query, cookies: account.downloadCookies(), more: true) }.disabled(online.searching)
            }
            if !online.cached.isEmpty {
                Section("音频缓存 · 从新到旧") {
                    ForEach(online.cached) { OnlineTrackRow(track: $0.track) }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "YouTube 歌名、歌手")
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { online.resetSearch() }
            else { submit() }
        }
        .onChange(of: online.filter) { _, _ in if !query.isEmpty { submit() } }
        .task { await online.refresh() }
        .safeAreaInset(edge: .bottom) {
            if online.downloadingID != nil {
                HStack {
                    ProgressView()
                    Text("正在准备音频…").font(.caption)
                    Spacer()
                    Button("取消") { online.cancelDownload() }
                }.padding().background(.bar)
            }
        }
    }
    private func submit() { online.search(query, cookies: account.downloadCookies()) }
}

struct OnlineTrackRow: View {
    let track: OnlineTrack
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback

    var body: some View {
        HStack(spacing: 12) {
            if track.isPlayable {
                Button { prepare(play: true) } label: { label }.buttonStyle(.plain)
                    .disabled(online.downloadingID != nil)
                    .accessibilityLabel("播放 \(track.title)，\(track.artist)")
                Menu {
                    Button("播放", systemImage: "play.fill") { prepare(play: true) }
                    Button("预下载", systemImage: "arrow.down.circle") { prepare() }
                    Button("下载到资料库", systemImage: "square.and.arrow.down") { prepare(save: true) }
                    if account.isSignedIn, track.kind != .telegram {
                        let liked = online.liked.contains { $0.id == track.id }
                        Button(liked ? "取消 YouTube 收藏" : "收藏到 YouTube", systemImage: liked ? "heart.slash" : "heart") {
                            Task { await online.setLiked(track, liked: !liked, cookies: account.downloadCookies(), cloud: cloud) }
                        }.disabled(online.syncing)
                    }
                    if let album = track.albumTitle { Text(album) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .disabled(online.downloadingID != nil).accessibilityLabel("歌曲操作")
            } else if let browseID = track.browseID {
                NavigationLink { MusicCollectionView(browseID: browseID, title: track.title) } label: { label }
            }
        }
        .padding(.vertical, 8)
        .listRowSeparator(.visible).listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.coverURL) { image in image.resizable().scaledToFill() } placeholder: {
                Image("AppLogo").resizable().scaledToFill()
            }.frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 4)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.body.weight(.medium)).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if online.cached.contains(where: { $0.id == track.id }) {
                    Label("已缓存", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(.rect)
    }

    private func prepare(play: Bool = false, save: Bool = false) {
        online.prepare(track, play: play, saveTo: save ? library : nil, playback: playback, cookies: account.downloadCookies(), cloud: cloud)
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
                    Task { await online.clearCache(playback: playback) }
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
                            Task { await online.remove(entry, playback: playback) }
                        }.disabled(online.downloadingID != nil)
                    }
                }
            }
        }.localizedNavigationTitle("音频缓存").task { await online.refresh() }
    }
}
