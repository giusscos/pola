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
    /// memory with large libraries, so this decodes straight to `maxPixelSize`, from the memory or
    /// disk cache when it can. Synchronous; views that scroll use `loadThumbnail` instead.
    func thumbnail(maxPixelSize: CGFloat) -> UIImage? {
        let bucket = ThumbnailCache.bucket(for: maxPixelSize)
        if let cached = ThumbnailCache.memoryImage(id: id, bucket: bucket)
            ?? ThumbnailCache.diskImage(id: id, bucket: bucket) {
            return cached
        }
        guard let image = ThumbnailCache.makeThumbnail(from: imageData, id: id, bucket: bucket, persist: false) else {
            return nil
        }
        ThumbnailCache.writeInBackground(image, id: id, bucket: bucket)
        return image
    }

    /// The thumbnail if it is already in memory; never touches the disk or the photo.
    func cachedThumbnail(maxPixelSize: CGFloat) -> UIImage? {
        ThumbnailCache.memoryImage(id: id, bucket: ThumbnailCache.bucket(for: maxPixelSize))
    }

    /// Like `thumbnail`, but the disk read and the decode happen off the main actor.
    func loadThumbnail(maxPixelSize: CGFloat) async -> UIImage? {
        let bucket = ThumbnailCache.bucket(for: maxPixelSize)
        let id = id
        if let cached = ThumbnailCache.memoryImage(id: id, bucket: bucket) { return cached }
        if let cached = await ThumbnailCache.diskImageInBackground(id: id, bucket: bucket) { return cached }
        return await ThumbnailCache.makeThumbnailInBackground(from: imageData, id: id, bucket: bucket)
    }

    /// The most recent thumbnail made for this entry, whatever its size, if one is still in memory.
    /// Lets a bigger view show something at once while it loads its own size.
    var latestThumbnail: UIImage? {
        ThumbnailCache.latestImage(id: id)
    }

    /// `imageData` downsampled to screen size off the main actor; kept in memory only.
    func downsampledImage(maxPixelSize: CGFloat) async -> UIImage? {
        let bucket = ThumbnailCache.bucket(for: maxPixelSize)
        if let cached = ThumbnailCache.memoryImage(id: id, bucket: bucket) { return cached }
        return await ThumbnailCache.makeThumbnailInBackground(from: imageData, id: id, bucket: bucket, persist: false)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func videoURL(in directory: URL) -> URL? {
        guard let filename = videoFilename else { return nil }
        return directory.appendingPathComponent(filename)
    }
}
