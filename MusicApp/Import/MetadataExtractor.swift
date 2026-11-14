import AVFoundation
import AudioToolbox
import Foundation

struct AudioMetadata: Sendable {
    var title = ""
    var artist = "未知艺术家"
    var album = "未知专辑"
    var albumArtist = ""
    var duration: Double = 0
    var format = ""
    var sampleRate: Double = 0
    var channels = 0
    var bitDepth: Int?
    var track = 0
    var disc = 0
    var genre = "未分类"
    var year: Int?
    var lyrics = ""
    var artwork: Data?
}

enum MetadataExtractor {
    static func extract(_ url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw MusicError.unsupportedAudio }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw MusicError.unsupportedAudio }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MusicError.unsupportedAudio }
        // Read decoded PCM, not just a container header, before admitting a file.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(output)
        guard reader.startReading(), output.copyNextSampleBuffer() != nil else { throw MusicError.unsupportedAudio }
        reader.cancelReading()

        var result = AudioMetadata()
        result.title = url.deletingPathExtension().lastPathComponent
        result.duration = duration
        result.format = url.pathExtension.uppercased()
        if let descriptions = try? await track.load(.formatDescriptions), let first = descriptions.first,
           let stream = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee {
            result.sampleRate = stream.mSampleRate
            result.channels = Int(stream.mChannelsPerFrame)
            result.bitDepth = stream.mBitsPerChannel > 0 ? Int(stream.mBitsPerChannel) : nil
        }
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        var items = common
        for format in formats { items += (try? await asset.loadMetadata(for: format)) ?? [] }
        for item in items {
            let key = item.commonKey?.rawValue ?? item.identifier?.rawValue ?? String(describing: item.key)
            let lower = key.lowercased()
            if lower.contains("artwork") || lower.contains("apic") || lower.contains("covr") {
                if result.artwork == nil { result.artwork = try? await item.load(.dataValue) }
                continue
            }
            if lower.contains("trkn") || lower.contains("disk") {
                if let data = try? await item.load(.dataValue), data.count >= 4 {
                    let number = Int(data[2]) << 8 | Int(data[3])
                    if lower.contains("trkn") { result.track = number } else { result.disc = number }
                }
                continue
            }
            guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }
            if lower == "title" || lower.contains("tit2") || lower.contains("©nam") { result.title = value }
            else if lower.contains("albumartist") || lower.contains("album_artist") || lower.contains("tpe2") || lower.contains("aart") { result.albumArtist = value }
            else if lower == "artist" || lower.contains("tpe1") || lower.contains("©art") { result.artist = value }
            else if lower.contains("albumname") || lower == "album" || lower.contains("talb") || lower.contains("©alb") { result.album = value }
            else if lower.contains("lyric") || lower.contains("uslt") || lower.contains("©lyr") { result.lyrics = value }
            else if lower.contains("genre") || lower.contains("tcon") || lower.contains("©gen") || lower.contains("gnre") { result.genre = value }
            else if lower.contains("year") || lower.contains("date") || lower.contains("tdrc") || lower.contains("tyer") || lower.contains("©day") { result.year = Int(value.prefix(4)) }
            else if lower.contains("track") || lower.contains("trck") { result.track = Int(value.split(separator: "/").first ?? "") ?? 0 }
            else if lower.contains("disc") || lower.contains("tpos") { result.disc = Int(value.split(separator: "/").first ?? "") ?? 0 }
        }
        // FLAC Vorbis comments and pictures are not consistently exposed as AVMetadataItems.
        if let flac = try? FLACMetadata.read(url) { flac.apply(to: &result) }
        if result.albumArtist.isEmpty { result.albumArtist = result.artist }
        return result
    }
}
