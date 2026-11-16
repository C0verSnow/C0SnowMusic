import SwiftUI

struct OnlineSearchView: View {
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    @Binding var query: String
    var isActive = false
    @State private var warehouse: [OnlineTrack] = []

    var body: some View {
        VStack(spacing: 0) {
            if !query.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(MusicSearchFilter.allCases) { filter in
                            Button(filter == .all ? "Top Results" : filter.rawValue) { online.filter = filter }
                                .font(.subheadline.bold()).buttonStyle(.bordered)
                                .tint(online.filter == filter ? .pink : .secondary)
                                .buttonBorderShape(.capsule)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 8)
                }.scrollIndicators(.hidden)
            }
            List {
                if query.isEmpty {
                    if !online.searchHistory.isEmpty {
                        Section("Recently Searched") {
                            ForEach(online.searchHistory, id: \.self) { value in
                                Button { query = value } label: { Label(value, systemImage: "magnifyingglass") }
                            }
                            Button("Clear", role: .destructive) { online.clearSearchHistory() }
                        }
                    }
                    if !isActive {
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(Self.categories.enumerated()), id: \.offset) { index, category in
                                Button { query = category } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        LinearGradient(colors: [Self.colors[index], Self.colors[index].opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Image(systemName: "music.note").font(.system(size: 62)).rotationEffect(.degrees(-15))
                                            .foregroundStyle(.white.opacity(0.15)).frame(maxWidth: .infinity, alignment: .trailing).padding(10)
                                        Text(category).font(.headline).foregroundStyle(.white).padding(14)
                                    }.frame(height: 94).clipShape(.rect(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                        }.listRowSeparator(.hidden)
                    }
                    }
                } else {
                    if online.searching && online.results.isEmpty { MusicPlaceholderRows() }
                    ForEach(online.sections) { section in
                        Section(section.title) { ForEach(section.items) { OnlineTrackRow(track: $0) } }
                    }
                    if !warehouseResults.isEmpty {
                        Section("From Your Collection") { ForEach(warehouseResults) { OnlineTrackRow(track: $0) } }
                    }
                    if online.results.isEmpty && warehouseResults.isEmpty && !online.searching {
                        if online.searchError != nil {
                            ContentUnavailableView("Couldn't Load Results", systemImage: "magnifyingglass", description: Text("Check your connection and try again."))
                            Button("Try Again") { submit() }
                        } else { ContentUnavailableView.search(text: query) }
                    }
                    if online.continuation != nil {
                        Button("Show More Results") { online.search(query, cookies: account.downloadCookies(), more: true) }.disabled(online.searching)
                    }
                }
            }.listStyle(.plain)
        }
        .task(id: query) {
            warehouse = []
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            submit()
            if cloud.connected && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let tracks = try? await cloud.search(query)
                if !Task.isCancelled { warehouse = tracks?.map(\.onlineTrack) ?? [] }
            }
        }
        .onChange(of: online.filter) { _, _ in if !query.isEmpty { submit() } }
    }

    private var warehouseResults: [OnlineTrack] {
        let ids = Set(online.results.map(\.id))
        return warehouse.filter { !ids.contains($0.id) && (online.filter == .all || online.filter == .songs) }
    }
    private func submit() { online.search(query, cookies: account.downloadCookies()) }
    private static let categories = ["Pop", "Hip-Hop", "R&B", "Rock", "Dance", "Classical", "Jazz", "Country"]
    private static let colors: [Color] = [.pink, .purple, .indigo, .red, .teal, .orange, .blue, .brown]
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
                    .accessibilityLabel("Play \(track.title), \(track.artist)")
                if online.downloadingID == track.id {
                    Button("Cancel") { online.cancelDownload() }.font(.caption)
                } else {
                Menu {
                    Button("Play", systemImage: "play.fill") { prepare(play: true) }
                    Button("Download", systemImage: "arrow.down.circle") { prepare() }
                    Button("Add to Library", systemImage: "square.and.arrow.down") { prepare(save: true) }
                    if account.isSignedIn, track.kind != .telegram {
                        let liked = online.liked.contains { $0.id == track.id }
                        Button(liked ? "Unlike on YouTube" : "Like on YouTube", systemImage: liked ? "heart.slash" : "heart") {
                            Task { await online.setLiked(track, liked: !liked, cookies: account.downloadCookies(), cloud: cloud) }
                        }.disabled(online.syncing)
                    }
                    if let album = track.albumTitle { Text(album) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .disabled(online.downloadingID != nil).accessibilityLabel("Song actions")
                }
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
            OnlineArtworkView(track: track).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.body.weight(.medium)).lineLimit(2)
                Text(online.downloadingID == track.id ? "Preparing…" : subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(.rect)
    }

    private var subtitle: String {
        let kind = switch track.kind {
        case .album: "Album"
        case .artist: "Artist"
        case .playlist: "Playlist"
        case .video: "Video"
        default: "Song"
        }
        return track.artist.isEmpty ? kind : "\(kind) · \(track.artist)"
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
                LabeledContent("Cache limit", value: "500 MB")
                LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: online.cacheBytes, countStyle: .file))
                Text("The oldest cached audio is removed when the limit is reached. Songs downloaded to your library are excluded and never removed automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Clear audio cache", role: .destructive) {
                    Task { await online.clearCache(playback: playback) }
                }.disabled(online.downloadingID != nil)
            }
            Section("Newest first") {
                ForEach(online.cached) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.track.title)
                        Text(entry.track.artist).font(.caption).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file)).font(.caption2)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await online.remove(entry, playback: playback) }
                        }.disabled(online.downloadingID != nil)
                    }
                }
            }
        }.localizedNavigationTitle("Audio cache").task { await online.refresh() }
    }
}

struct OnlineArtworkView: View {
    let track: OnlineTrack
    @State private var useFallback = false
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: useFallback ? track.fallbackCoverURL : track.coverURL ?? track.fallbackCoverURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        Image(systemName: track.kind == .artist ? "person.fill" : "music.note").font(.title).foregroundStyle(.tertiary)
                    }.onAppear { if case .failure = phase { useFallback = true } }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.clipShape(.rect(cornerRadius: track.kind == .artist ? 100 : 6)).accessibilityHidden(true)
    }
}
