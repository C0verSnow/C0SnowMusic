import SwiftUI

struct CloudSearchView: View {
    @Environment(CloudMusicStore.self) private var cloud
    @State private var query = ""
    @State private var results: [CloudTrack] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        List {
            if !cloud.connected {
                NavigationLink { CloudLibrarySettingsView() } label: { Label("连接音乐仓库", systemImage: "cloud") }
            } else {
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(results) { OnlineTrackRow(track: $0.onlineTrack) }
                if results.isEmpty, !busy, error == nil { ContentUnavailableView.search(text: query) }
            }
        }
        .searchable(text: $query, prompt: "仓库歌名、歌手")
        .task(id: "\(query)-\(cloud.connected)") {
            guard cloud.connected else { return }
            busy = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(300))
                let values = try await cloud.search(query)
                try Task.checkCancellation()
                results = values; busy = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { busy = false; self.error = error.localizedDescription } }
        }
    }
}
