import Foundation
import CryptoKit

struct LibraryFiles: Sendable {
    let root: URL

    init(root: URL = URL.applicationSupportDirectory.appending(path: "MusicLibrary", directoryHint: .isDirectory)) {
        self.root = root
    }

    func createDirectories() throws {
        for name in ["Audio", "Artwork", "Staging", "Removed"] {
            try FileManager.default.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
        }
    }

    func url(for relativePath: String) -> URL { root.appending(path: relativePath) }
    func artworkURL(_ id: String, thumbnail: Bool = false) -> URL {
        root.appending(path: "Artwork/\(id)\(thumbnail ? "-thumb" : "").jpg")
    }

    static func hash(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func copy(_ source: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }
}

enum MusicError: LocalizedError {
    case unsupportedAudio, unreadableFile, insufficientSpace, invalidLyrics, emptyName
    var errorDescription: String? {
        switch self {
        case .unsupportedAudio: "The system cannot decode this audio. Convert it to ALAC, M4A, or WAV and import again."
        case .unreadableFile: "Cannot read this file. Make sure it is downloaded to your device and is not damaged."
        case .insufficientSpace: "Not enough storage. Free some space and retry."
        case .invalidLyrics: "Cannot read these lyrics. Choose an LRC file encoded as UTF-8 or UTF-16."
        case .emptyName: "Name cannot be empty."
        }
    }
}
