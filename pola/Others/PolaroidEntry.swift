import CoreLocation
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

    convenience init(
        image: UIImage,
        videoFilename: String? = nil,
        isTimelapse: Bool = false,
        filterName: String? = nil,
        lensName: String? = nil,
        packName: String? = nil,
        frameFormat: FrameFormat = .classic,
        coordinate: CLLocationCoordinate2D? = nil
    ) {
        self.init(
            imageData: image.jpegData(compressionQuality: CaptureDevelopment.jpegQuality) ?? Data(),
            videoFilename: videoFilename,
            isTimelapse: isTimelapse,
            filterName: filterName,
            lensName: lensName,
            packName: packName,
            frameFormat: frameFormat,
            coordinate: coordinate
        )
    }

    /// Takes an already encoded JPEG, so the encoding can happen off the main actor.
    init(
        imageData: Data,
        videoFilename: String? = nil,
        isTimelapse: Bool = false,
        filterName: String? = nil,
        lensName: String? = nil,
        packName: String? = nil,
        frameFormat: FrameFormat = .classic,
        coordinate: CLLocationCoordinate2D? = nil
    ) {
        self.id = UUID()
        self.imageData = imageData
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
        guard let thumbnail = ImageDownsampler.downsample(imageData, maxPixelSize: bucket) else { return nil }
        remember(thumbnail, key: key)
        return thumbnail
    }

    /// The most recent thumbnail made for this entry, whatever its size, if one is still in memory.
    /// Lets a bigger view show something at once while it loads its own size.
    var latestThumbnail: UIImage? {
        Self.latestThumbnails.object(forKey: id.uuidString as NSString)
    }

    /// `imageData` downsampled to `maxPixelSize` off the main actor. Only the data read is on main.
    func downsampledImage(maxPixelSize: CGFloat) async -> UIImage? {
        let bucket = max(64, Int(maxPixelSize.rounded(.up)))
        let key = "\(id.uuidString)-\(bucket)" as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached }
        guard let image = await ImageDownsampler.downsampleInBackground(imageData, maxPixelSize: bucket) else { return nil }
        remember(image, key: key)
        return image
    }

    private func remember(_ image: UIImage, key: NSString) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        Self.thumbnailCache.setObject(image, forKey: key, cost: cost)
        Self.latestThumbnails.setObject(image, forKey: id.uuidString as NSString, cost: cost)
    }

    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 150 * 1024 * 1024
        return cache
    }()

    private static let latestThumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 60 * 1024 * 1024
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
