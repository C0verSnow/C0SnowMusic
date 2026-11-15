import SwiftUI

struct MusicRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerTransition
    @State private var expanded = false
    @State private var importing = false
    @State private var settings = false
    @AppStorage("appLanguage") private var language = "system"

    var body: some View {
        @Bindable var library = library
        @Bindable var playback = playback
        TabView {
            Tab(AppLanguage.text("首页", language: language), systemImage: "house.fill") { navigation { HomeView() } }
            Tab(AppLanguage.text("发现", language: language), systemImage: "square.grid.2x2.fill") { navigation { DiscoverView() } }
            Tab(AppLanguage.text("资料库", language: language), systemImage: "music.note.list") { navigation { LibraryView() } }
            Tab(AppLanguage.text("搜索", language: language), systemImage: "magnifyingglass", role: .search) { navigation { SearchView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(PlayerAccessoryModifier(enabled: playback.currentSong != nil, expanded: $expanded, namespace: playerTransition))
        .fullScreenCover(isPresented: $expanded) {
            if reduceMotion { NowPlayingView() }
            else { NowPlayingView().navigationTransition(.zoom(sourceID: "player", in: playerTransition)) }
        }
        .sheet(isPresented: $settings) { NavigationStack { AccountView() } }
        .sheet(isPresented: $importing) {
            DocumentImportPicker(types: AudioImportService.contentTypes, multiple: true) { urls in
                importing = false
                library.startImport(urls)
            } onCancel: { importing = false }
        }
        .overlay(alignment: .top) {
            if let progress = library.importProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(library.importStatus).font(.caption).lineLimit(2)
                        Spacer()
                        Button("取消") { library.cancelImport() }
                    }
                    ProgressView(value: progress)
                }
                .padding().background(.regularMaterial, in: .rect(cornerRadius: 20)).padding()
                .accessibilityElement(children: .contain)
            }
        }
        .alert("音乐库操作失败", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("好") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .alert("播放失败", isPresented: Binding(get: { playback.playbackError != nil }, set: { if !$0 { playback.playbackError = nil } })) {
            Button("好") { playback.playbackError = nil }
        } message: { Text(playback.playbackError ?? "") }
        .onChange(of: playback.currentSong?.id) { _, id in if id == nil { expanded = false } }
    }

    private func navigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: LibraryRoute.self) { LibraryRouteView(route: $0) }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("导入音乐", systemImage: "plus") { importing = true }
                            .accessibilityIdentifier("importMusic")
                            .disabled(library.importProgress != nil)
                        Button("账户", systemImage: "person.crop.circle") { settings = true }
                            .accessibilityIdentifier("accountSettings")
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
