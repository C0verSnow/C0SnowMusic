import SwiftUI

struct MusicRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(OnlineMusicStore.self) private var online
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerTransition
    @State private var expanded = false
    @State private var settings = false
    @State private var editingLibrary = false
    @State private var creatingPlaylist = false
    @State private var selectedTab = MusicTab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: MusicTab.home) { navigation { HomeView(onSearch: { selectedTab = .search }) } }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: MusicTab.radio) { navigation(titleDisplay: .inline) { RadioView() } }
            Tab("Library", systemImage: "music.note", value: MusicTab.library) {
                navigation(libraryControls: true) { LibraryView(editing: $editingLibrary) }
            }
            Tab("Search", systemImage: "magnifyingglass", value: MusicTab.search) { navigation { SearchView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(PlayerAccessoryModifier(enabled: true, expanded: $expanded, namespace: playerTransition))
        .fullScreenCover(isPresented: $expanded) {
            if reduceMotion { NowPlayingView() }
            else { NowPlayingView().navigationTransition(.zoom(sourceID: "player", in: playerTransition)) }
        }
        .sheet(isPresented: $settings) { NavigationStack { AccountView() } }
        .sheet(isPresented: $creatingPlaylist) { NavigationStack { PlaylistCreationView() } }
        .overlay(alignment: .top) {
            if let progress = library.importProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(library.importStatus).font(.caption).lineLimit(2)
                        Spacer()
                        Button("Cancel") { library.cancelImport() }
                    }
                    ProgressView(value: progress)
                }
                .padding().background(.regularMaterial, in: .rect(cornerRadius: 20)).padding()
                .accessibilityElement(children: .contain)
            }
        }
        .alert("Couldn't Import Music", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text("Some changes couldn't be saved. Check Music Settings for import details, then try again.") }
        .alert("Couldn't Play This Song", isPresented: Binding(get: { playback.playbackError != nil }, set: { if !$0 { playback.playbackError = nil } })) {
            Button("OK") { playback.playbackError = nil }
        } message: { Text("Try playing the song again. If it was removed, add it to your library again.") }
        .alert("Couldn't Complete This Action", isPresented: Binding(get: { online.error != nil }, set: { if !$0 { online.error = nil } })) {
            Button("OK") { online.error = nil }
        } message: { Text("Check your connection and try again. Your saved music is still available.") }
        .task(id: "\(account.isSignedIn)-\(cloud.connected)") {
            await online.refresh(playback: playback)
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            if account.isSignedIn { await online.loadLibrary(cookies: account.downloadCookies(), cloud: cloud) }
            else if cloud.connected { await cloud.refresh() }
        }
        .onChange(of: playback.currentSong?.id) { _, id in if id == nil { expanded = false } }
    }

    private func navigation<Content: View>(titleDisplay: ToolbarTitleDisplayMode = .inlineLarge, libraryControls: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbarTitleDisplayMode(titleDisplay)
                .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
                .toolbar {
                    if libraryControls {
                        if editingLibrary {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done", systemImage: "checkmark") { editingLibrary = false }
                                    .labelStyle(.iconOnly).buttonStyle(.glassProminent)
                                    .accessibilityIdentifier("editLibrary")
                            }
                        } else {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button("New Playlist", systemImage: "text.badge.plus") { creatingPlaylist = true }
                                    .tint(.primary).accessibilityIdentifier("newLibraryPlaylist")
                                Button("Edit Library", systemImage: "checklist") { editingLibrary = true }
                                    .tint(.primary).accessibilityIdentifier("editLibrary")
                            }
                        }
                    }
                    if !libraryControls || !editingLibrary {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { settings = true } label: { AccountAvatar().frame(width: 40, height: 40) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("c0vermusic Account")
                                .accessibilityIdentifier("accountSettings")
                        }.sharedBackgroundVisibility(.hidden)
                    }
                }
        }
    }
}

private struct PlayerAccessoryModifier: ViewModifier {
    let enabled: Bool
    @Binding var expanded: Bool
    let namespace: Namespace.ID

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { accessory }
        } else {
            content.tabViewBottomAccessory { if enabled { accessory } }
        }
    }

    private var accessory: some View {
        MiniPlayerView(expanded: $expanded)
            .matchedTransitionSource(id: "player", in: namespace)
    }

}

private enum MusicTab: Hashable { case home, radio, library, search }
