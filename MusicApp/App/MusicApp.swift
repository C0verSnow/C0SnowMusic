import SwiftUI
import SwiftData

@main struct C0SnowMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            Group {
                if let library = runtime.library, let playback = runtime.playback {
                    MusicRootView()
                        .environment(library)
                        .environment(playback)
                } else if let error = runtime.error {
                    ContentUnavailableView {
                        Label("无法打开音乐库", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("重试") { runtime.open() }
                    }
                } else { ProgressView("正在打开音乐库…") }
            }
            .tint(.pink)
            .task { if runtime.library == nil { runtime.open() }; await runtime.importTestFixturesIfRequested() }
            .onOpenURL { runtime.receive($0) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { runtime.playback?.saveSession() }
            }
        }
    }
}

@MainActor @Observable final class AppRuntime {
    var library: LibraryStore?
    var playback: PlaybackStore?
    var error: String?
    private var container: ModelContainer?
    private var pendingURLs: [URL] = []

    func open() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let files = testing ? LibraryFiles(root: URL.temporaryDirectory.appending(path: "C0SnowMusic-UITests-\(UUID())")) : LibraryFiles()
            try files.createDirectories()
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let configuration = testing
                ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                : ModelConfiguration(schema: schema, url: files.url(for: "Library.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration])
            let library = try LibraryStore(context: container.mainContext, files: files)
            let playback = try PlaybackStore(library: library)
            self.container = container; self.library = library; self.playback = playback; error = nil
            if !pendingURLs.isEmpty { library.startImport(pendingURLs); pendingURLs = [] }
        } catch { self.error = error.localizedDescription }
    }

    func receive(_ url: URL) {
        if let library { library.startImport([url]) } else { pendingURLs.append(url) }
    }

    func importTestFixturesIfRequested() async {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--fixture-library"), let library else { return }
        if let url = Bundle.main.url(forResource: "Test Tone", withExtension: "wav", subdirectory: "Fixtures") {
            do { try await library.importOne(url) }
            catch { library.error = error.localizedDescription }
        }
        #endif
    }
}
