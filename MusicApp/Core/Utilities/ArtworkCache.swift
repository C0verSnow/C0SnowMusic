import Foundation
import ImageIO
import UIKit

struct ArtworkPayload: @unchecked Sendable {
    let image: UIImage
    let tint: UIColor
}

actor ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()
    private var tints: [String: UIColor] = [:]

    init() { cache.totalCostLimit = 32 * 1_024 * 1_024 }

    func load(id: String, files: LibraryFiles, thumbnail: Bool) -> ArtworkPayload? {
        let key = files.root.path + id + (thumbnail ? "-thumb" : "")
        let image: UIImage
        if let cached = cache.object(forKey: key as NSString) { image = cached }
        else {
            guard let source = CGImageSourceCreateWithURL(files.artworkURL(id, thumbnail: thumbnail) as CFURL, nil),
                  let cgImage = Self.downsample(source, pixels: thumbnail ? 160 : 1_024) else { return nil }
            image = UIImage(cgImage: cgImage)
            cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        }
        let tint: UIColor
        if let cached = tints[id] { tint = cached }
        else {
            tint = Self.averageColor(image.cgImage)
            tints[id] = tint
        }
        return ArtworkPayload(image: image, tint: tint)
    }

    @discardableResult func save(_ data: Data, id: String, files: LibraryFiles) throws -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        var saved = 0
        for (pixels, thumbnail) in [(1_024, false), (160, true)] {
            if let image = Self.downsample(source, pixels: pixels), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) {
                try jpeg.write(to: files.artworkURL(id, thumbnail: thumbnail), options: .atomic)
                saved += 1
            }
        }
        return saved == 2
    }

    private static func downsample(_ source: CGImageSource, pixels: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func averageColor(_ image: CGImage?) -> UIColor {
        guard let image else { return .darkGray }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let color = pixel.withUnsafeMutableBytes { buffer -> UIColor in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .darkGray }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let bytes = buffer.bindMemory(to: UInt8.self)
            return UIColor(red: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255, blue: CGFloat(bytes[2]) / 255, alpha: 1)
        }
        return color
    }
}
