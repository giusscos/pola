import CoreLocation
import ImageIO
import SwiftData
import UIKit

@Model
final class PolaroidEntry: Identifiable {
    var id: UUID = UUID()
    // Stored as an external file by SwiftData; CloudKit syncs it as a CKAsset.
    @Attribute(.externalStorage) var imageData: Data = Data()
    var videoFilename: String? = nil
    var isTimelapse: Bool = false
    var caption: String = ""
    var backText: String = ""
    var showMap: Bool = true
    var latitude: Double? = nil
    var longitude: Double? = nil
    var developmentProgress: Double = 0.0
    var timestamp: Date = Date()
    var filterName: String? = nil
    var lensName: String? = nil
    var packName: String? = nil
    var packColorHex: String? = nil
    var frameFormatRaw: String = FrameFormat.classic.rawValue

    init(
        image: UIImage,
        videoFilename: String? = nil,
        isTimelapse: Bool = false,
        filterName: String? = nil,
        lensName: String? = nil,
        packName: String? = nil,
        frameFormat: FrameFormat = .classic,
        coordinate: CLLocationCoordinate2D? = nil
    ) {
        self.id = UUID()
        self.imageData = image.jpegData(compressionQuality: 0.9) ?? Data()
        self.videoFilename = videoFilename
        self.isTimelapse = isTimelapse
        self.filterName = filterName
        self.lensName = lensName
        self.packName = packName
        self.frameFormatRaw = frameFormat.rawValue
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.timestamp = Date()
        self.developmentProgress = 0.0
    }

    var frameFormat: FrameFormat {
        get { FrameFormat(rawValue: frameFormatRaw) ?? .classic }
        set { frameFormatRaw = newValue.rawValue }
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }

    /// Downsampled image for grids. Decoding full-resolution photos for every cell exhausts
    /// memory with large libraries, so this decodes straight to `maxPixelSize` and caches it.
    /// `imageData` never changes after creation, so the entry ID is a safe cache key.
    func thumbnail(maxPixelSize: CGFloat) -> UIImage? {
        let bucket = max(64, Int(maxPixelSize.rounded(.up)))
        let key = "\(id.uuidString)-\(bucket)" as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }

        let thumbnail = UIImage(cgImage: cgImage)
        Self.thumbnailCache.setObject(thumbnail, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return thumbnail
    }

    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 150 * 1024 * 1024
        return cache
    }()

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func videoURL(in directory: URL) -> URL? {
        guard let filename = videoFilename else { return nil }
        return directory.appendingPathComponent(filename)
    }
}
