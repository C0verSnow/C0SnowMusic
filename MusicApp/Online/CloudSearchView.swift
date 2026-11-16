import SwiftUI

struct CloudSearchView: View {
    @Environment(CloudMusicStore.self) private var cloud
    @Environment(OnlineMusicStore.self) private var online
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
                if let error = error ?? online.error { Text(error).foregroundStyle(.red) }
                ForEach(results) { OnlineTrackRow(track: $0.onlineTrack) }
                if results.isEmpty, !busy, error == nil { ContentUnavailableView.search(text: query) }
            }
        }
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
