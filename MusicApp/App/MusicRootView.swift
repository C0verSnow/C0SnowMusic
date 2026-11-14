import SwiftUI

struct MusicRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerTransition
    @State private var expanded = false
    @State private var importing = false
    @State private var settings = false

    var body: some View {
        @Bindable var library = library
        @Bindable var playback = playback
        TabView {
            Tab("首页", systemImage: "house.fill") { navigation { HomeView() } }
            Tab("发现", systemImage: "square.grid.2x2.fill") { navigation { DiscoverView() } }
            Tab("资料库", systemImage: "music.note.list") { navigation { LibraryView() } }
            Tab("搜索", systemImage: "magnifyingglass", role: .search) { navigation { SearchView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if playback.currentSong != nil {
                MiniPlayerView(expanded: $expanded)
                    .matchedTransitionSource(id: "player", in: playerTransition)
            }
        }
        .fullScreenCover(isPresented: $expanded) {
            if reduceMotion { NowPlayingView() }
            else { NowPlayingView().navigationTransition(.zoom(sourceID: "player", in: playerTransition)) }
        }
        .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: AudioImportService.contentTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): library.startImport(urls)
            case .failure(let error): library.error = error.localizedDescription
            }
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
                        Button("设置", systemImage: "person.crop.circle") { settings = true }
                    }
                }
        }
    }
}
