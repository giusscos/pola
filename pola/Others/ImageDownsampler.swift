import ImageIO
import UIKit

/// Decodes a JPEG straight to a smaller size, without ever holding the full-resolution bitmap.
nonisolated enum ImageDownsampler {
    static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @concurrent
    static func downsampleInBackground(_ data: Data, maxPixelSize: Int) async -> UIImage? {
        downsample(data, maxPixelSize: maxPixelSize)
    }
}
