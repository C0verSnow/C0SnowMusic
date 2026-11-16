import SwiftUI

struct ArtworkView: View {
    @Environment(LibraryStore.self) private var library
    let id: String?
    var thumbnail = true
    var cornerRadius: CGFloat = 10
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else {
                    Image("AppLogo").resizable().scaledToFill()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .task(id: "\(id ?? "")-\(thumbnail)") {
            image = nil
            if let id {
                let loaded = await ArtworkCache.shared.load(id: id, files: library.files, thumbnail: thumbnail)?.image
                if !Task.isCancelled { image = loaded }
            }
        }
    }
}

struct AlbumCard: View {
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(id: album.artworkID, thumbnail: false).aspectRatio(1, contentMode: .fit)
            Text(album.title).font(.subheadline.weight(.medium)).lineLimit(2)
            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("你的音乐，从这里开始", systemImage: "music.note.house")
        } description: {
            Text("搜索 YouTube 开始聆听；本地文件可从账户的 Music Settings 导入。")
        }
    }
}

func playbackTime(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.isFinite ? seconds : 0))
    return "\(value / 60):\(String(format: "%02d", value % 60))"
}
