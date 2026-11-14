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
        case .unsupportedAudio: "系统无法解码这份音频。请尝试转换为 ALAC、M4A 或 WAV 后导入。"
        case .unreadableFile: "无法读取文件，请确认文件已下载到设备且没有损坏。"
        case .insufficientSpace: "设备空间不足，请清理存储后重试。"
        case .invalidLyrics: "无法读取歌词，请选择 UTF-8 或 UTF-16 编码的 LRC 文件。"
        case .emptyName: "名称不能为空。"
        }
    }
}
