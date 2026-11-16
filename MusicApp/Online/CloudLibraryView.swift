import SwiftUI

struct CloudLibrarySettingsView: View {
    @Environment(CloudMusicStore.self) private var cloud
    @State private var endpoint = ""
    @State private var apiKey = ""
    var body: some View {
        Form {
            Section("Music warehouse") {
                TextField("HTTPS endpoint", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Device key", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Connect") {
                    Task {
                        await cloud.connect(endpoint: endpoint, apiKey: apiKey)
                        if cloud.connected { apiKey = "" }
                    }
                }.disabled(cloud.busy)
                if cloud.busy { Text("Connecting…").foregroundStyle(.secondary) }
                if cloud.connected {
                    Label("Connected to music warehouse", systemImage: "checkmark.circle")
                    Button("Disconnect", role: .destructive) { cloud.disconnect(); apiKey = "" }
                }
                if cloud.error != nil { Text("Couldn't connect. Check the address and device key, then try again.").foregroundStyle(.secondary) }
            }
            Section {
                Text("Connect your music storage to keep downloaded music available across your devices. Removing a favorite keeps the audio in storage.")
                Text("Supports MP3 and M4A files up to 20 MB. Your device key is stored securely on this device.")
            }.font(.footnote).foregroundStyle(.secondary)
        }.localizedNavigationTitle("Music warehouse").onAppear { endpoint = cloud.endpoint }
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
            if busy && sections.isEmpty { MusicPlaceholderRows() }
            if error != nil, sections.isEmpty {
                ContentUnavailableView("Couldn't Load This Collection", systemImage: "music.note.list", description: Text("Check your connection and try again."))
                Button("Try Again") { Task { await load(more: false) } }
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) { ForEach(section.items) { OnlineTrackRow(track: $0) } }
            }
            if sections.isEmpty && !busy && error == nil { ContentUnavailableView("No Music Yet", systemImage: "music.note.list") }
            if continuation != nil { Button("Load more") { Task { await load(more: true) } }.disabled(busy) }
        }.listStyle(.plain).navigationTitle(title).task { await load(more: false) }
            .refreshable { await load(more: false) }
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
