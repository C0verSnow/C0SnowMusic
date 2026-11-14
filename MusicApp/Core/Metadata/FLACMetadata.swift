import Foundation

struct FLACMetadata {
    var comments: [String: String] = [:]
    var picture: Data?
    var sampleRate: Double?
    var channels: Int?
    var bitDepth: Int?

    static func read(_ url: URL) throws -> FLACMetadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("fLaC".utf8) else { return FLACMetadata() }
        var result = FLACMetadata()
        while let header = try handle.read(upToCount: 4), header.count == 4 {
            let kind = header[0] & 0x7f
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if (kind == 0 || kind == 4 || kind == 6), length <= 16_777_216,
               let block = try handle.read(upToCount: length), block.count == length {
                var cursor = MetadataCursor(data: block)
                if kind == 0 {
                    guard block.count == 34 else { throw MusicError.unreadableFile }
                    let stream = block[10..<18].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                    result.sampleRate = Double((stream >> 44) & 0xfffff)
                    result.channels = Int((stream >> 41) & 7) + 1
                    result.bitDepth = Int((stream >> 36) & 31) + 1
                } else if kind == 4 {
                    let vendorLength = try cursor.integer(littleEndian: true)
                    _ = try cursor.bytes(vendorLength)
                    let count = try cursor.integer(littleEndian: true)
                    for _ in 0..<count {
                        let size = try cursor.integer(littleEndian: true)
                        let text = String(decoding: try cursor.bytes(size), as: UTF8.self)
                        if let separator = text.firstIndex(of: "=") {
                            result.comments[String(text[..<separator]).uppercased()] = String(text[text.index(after: separator)...])
                        }
                    }
                } else {
                    let type = try cursor.integer()
                    let mime = try cursor.integer(); _ = try cursor.bytes(mime)
                    let description = try cursor.integer(); _ = try cursor.bytes(description)
                    _ = try cursor.bytes(16)
                    let size = try cursor.integer()
                    let picture = try cursor.bytes(size)
                    if result.picture == nil || type == 3 { result.picture = picture }
                }
            } else {
                try handle.seek(toOffset: handle.offsetInFile + UInt64(length))
            }
            if header[0] & 0x80 != 0 { break }
        }
        return result
    }

    func apply(to metadata: inout AudioMetadata) {
        if let value = comments["TITLE"] { metadata.title = value }
        if let value = comments["ARTIST"] { metadata.artist = value }
        if let value = comments["ALBUM"] { metadata.album = value }
        if let value = comments["ALBUMARTIST"] ?? comments["ALBUM_ARTIST"] { metadata.albumArtist = value }
        if let value = comments["GENRE"] { metadata.genre = value }
        if let value = comments["DATE"] { metadata.year = Int(value.prefix(4)) }
        if let value = comments["TRACKNUMBER"] { metadata.track = Int(value.split(separator: "/").first ?? "") ?? 0 }
        if let value = comments["DISCNUMBER"] { metadata.disc = Int(value.split(separator: "/").first ?? "") ?? 0 }
        if let value = comments["LYRICS"] ?? comments["UNSYNCEDLYRICS"] { metadata.lyrics = value }
        if let picture { metadata.artwork = picture }
        if let sampleRate { metadata.sampleRate = sampleRate }
        if let channels { metadata.channels = channels }
        if let bitDepth { metadata.bitDepth = bitDepth }
    }
}

private struct MetadataCursor {
    let data: Data
    var position = 0
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count - position else { throw MusicError.unreadableFile }
        defer { position += count }
        return data.subdata(in: position..<(position + count))
    }
    mutating func integer(littleEndian: Bool = false) throws -> Int {
        let value = try bytes(4)
        let ordered = littleEndian ? Array(value.reversed()) : Array(value)
        return ordered.reduce(0) { $0 << 8 | Int($1) }
    }
}
