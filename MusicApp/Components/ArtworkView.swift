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
                else { AppLogoView() }
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
            Label { Text("Your Music Starts Here") } icon: {
                AppLogoView().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
            }
        } description: {
            Text("Find something you love in Search, or add your music from c0versnow music Account → Music Settings.")
        }
    }
}

func playbackTime(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.isFinite ? seconds : 0))
    return "\(value / 60):\(String(format: "%02d", value % 60))"
}

struct MusicPlaceholderRows: View {
    var body: some View {
        ForEach(0..<5, id: \.self) { _ in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).frame(width: 160, height: 12)
                    RoundedRectangle(cornerRadius: 3).frame(width: 110, height: 10)
                }
            }.foregroundStyle(.quaternary).padding(.vertical, 8).accessibilityHidden(true)
        }
    }
}
