import SwiftUI

struct CloudLibrarySettingsView: View {
    @Environment(CloudMusicStore.self) private var cloud
    @State private var endpoint = ""
    @State private var apiKey = ""
    var body: some View {
        Form {
            Section("音乐仓库") {
                TextField("HTTPS 地址", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("设备密钥", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("连接") {
                    Task {
                        await cloud.connect(endpoint: endpoint, apiKey: apiKey)
                        if cloud.connected { apiKey = "" }
                    }
                }.disabled(cloud.busy)
                if cloud.busy { ProgressView() }
                if cloud.connected {
                    Label("已连接音乐仓库", systemImage: "checkmark.circle")
                    Button("断开连接", role: .destructive) { cloud.disconnect(); apiKey = "" }
                }
                if let error = cloud.error { Text(error).foregroundStyle(.red) }
            }
            Section {
                Text("连接后先查找仓库音频，没有时在手机获取音频并上传。Telegram 保存文件，数据库保存索引。取消收藏只移除关系，不删除音频。")
                Text("标准 Telegram 云端播放支持最大 20 MB 的 MP3/M4A。设备密钥保存在此设备的 Keychain。")
            }.font(.footnote).foregroundStyle(.secondary)
        }.localizedNavigationTitle("音乐仓库").onAppear { endpoint = cloud.endpoint }
    }
}

struct OnlineLibraryView: View {
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    var body: some View {
        List {
            Section {
                if account.isSignedIn {
                    Button("同步 YouTube 收藏", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await online.syncFavorites(cookies: account.downloadCookies(), cloud: cloud) }
                    }.disabled(online.syncing)
                }
                if online.syncing { ProgressView("正在同步收藏…") }
                if !account.isSignedIn { Text("登录 YouTube 后可同步收藏。") }
                if let error = online.error ?? cloud.error { Text(error).foregroundStyle(.red) }
            }
            Section("YouTube 收藏") { ForEach(online.liked) { OnlineTrackRow(track: $0) } }
            if cloud.connected {
                Section("仓库收藏") { ForEach(cloud.favorites) { OnlineTrackRow(track: $0.onlineTrack) } }
            }
            Section("YouTube Music 资料库") {
                NavigationLink("播放列表") { MusicCollectionView(browseID: "FEmusic_liked_playlists", title: "播放列表") }
                NavigationLink("专辑") { MusicCollectionView(browseID: "FEmusic_liked_albums", title: "专辑") }
                NavigationLink("艺术家") { MusicCollectionView(browseID: "FEmusic_library_corpus_artists", title: "艺术家") }
            }
        }.localizedNavigationTitle("在线资料库")
            .task(id: "\(account.isSignedIn)-\(cloud.connected)") {
                if account.isSignedIn { await online.syncFavorites(cookies: account.downloadCookies(), cloud: cloud) }
                else { await cloud.refresh() }
            }
    }
}

struct MusicCollectionView: View {
    let browseID: String
    let title: String
    @Environment(YouTubeAccountStore.self) private var account
    @State private var sections: [MusicSection] = []
    @State private var continuation: String?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(more: false) } } }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) { ForEach(section.items) { OnlineTrackRow(track: $0) } }
            }
            if continuation != nil { Button("加载更多") { Task { await load(more: true) } }.disabled(busy) }
        }.navigationTitle(title).task { await load(more: false) }
    }
    private func load(more: Bool) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let page = try await YouTubeMusicClient().browse(browseID, continuation: more ? continuation : nil, cookies: account.downloadCookies())
            sections = more ? sections + page.sections : page.sections; continuation = page.continuation
        } catch { self.error = error.localizedDescription }
    }
}
