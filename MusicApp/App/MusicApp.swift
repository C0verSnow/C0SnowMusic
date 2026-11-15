import SwiftUI
import SwiftData
import GoogleSignIn

@main struct C0SnowMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime = AppRuntime()
    @State private var account = GoogleAccountStore()
    @State private var online = OnlineMusicStore()
    @AppStorage("appLanguage") private var language = "system"

    var body: some Scene {
        WindowGroup {
            Group {
                if let library = runtime.library, let playback = runtime.playback {
                    MusicRootView()
                        .environment(library)
                        .environment(playback)
                        .environment(account)
                        .environment(online)
                } else if let error = runtime.error {
                    ContentUnavailableView {
                        Label("无法打开音乐库", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("重试") { runtime.open() }
                    }
                } else { ProgressView("正在打开音乐库…") }
            }
            .tint(.pink)
            .environment(\.locale, language == "system" ? .autoupdatingCurrent : Locale(identifier: language))
            .task { if runtime.library == nil { runtime.open() }; await runtime.importTestFixturesIfRequested() }
            .task { await account.restore() }
            .onOpenURL { if !GIDSignIn.sharedInstance.handle($0) { runtime.receive($0) } }
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
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--fixture-library") || arguments.contains("--picker-fixture"), let library else { return }
        if let url = Bundle.main.url(forResource: "Test Tone", withExtension: "wav", subdirectory: "Fixtures") {
            do {
                if arguments.contains("--picker-fixture") {
                    let destination = URL.documentsDirectory.appending(path: "Test Tone.wav")
                    try FileManager.default.createDirectory(at: .documentsDirectory, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    try FileManager.default.copyItem(at: url, to: destination)
                    if let lrc = Bundle.main.url(forResource: "Fixture", withExtension: "lrc", subdirectory: "Fixtures") {
                        let lyricsURL = URL.documentsDirectory.appending(path: "Fixture.lrc")
                        if FileManager.default.fileExists(atPath: lyricsURL.path) { try FileManager.default.removeItem(at: lyricsURL) }
                        try FileManager.default.copyItem(at: lrc, to: lyricsURL)
                    }
                } else { try await library.importOne(url) }
            } catch { library.error = error.localizedDescription }
        }
        #endif
    }
}
