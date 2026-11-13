import UIKit

/// Downsampled photos, in memory and in `Caches/Thumbnails`, keyed by entry ID and a pixel bucket.
/// `imageData` never changes after an entry is created, so the ID is a safe key; files are removed
/// when an entry is deleted and pruned when the library no longer has the entry.
nonisolated enum ThumbnailCache {
    // NSCache is thread-safe.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 150 * 1024 * 1024
        return cache
    }()

    nonisolated(unsafe) private static let latest: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = caches.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Sizes are rounded up to steps of 64 px so nearby layouts share files.
    static func bucket(for maxPixelSize: CGFloat) -> Int {
        max(64, Int((maxPixelSize / 64).rounded(.up)) * 64)
    }

    // MARK: Memory

    static func memoryImage(id: UUID, bucket: Int) -> UIImage? {
        memory.object(forKey: key(id, bucket))
    }

    /// The most recent thumbnail made for this entry, whatever its size.
    static func latestImage(id: UUID) -> UIImage? {
        latest.object(forKey: id.uuidString as NSString)
    }

    static func remember(_ image: UIImage, id: UUID, bucket: Int) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memory.setObject(image, forKey: key(id, bucket), cost: cost)
        latest.setObject(image, forKey: id.uuidString as NSString, cost: cost)
    }

    // MARK: Disk

    static func diskImage(id: UUID, bucket: Int) -> UIImage? {
        guard let url = fileURL(id: id, bucket: bucket),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)?.preparingForDisplay() else { return nil }
        remember(image, id: id, bucket: bucket)
        return image
    }

    @concurrent
    static func diskImageInBackground(id: UUID, bucket: Int) async -> UIImage? {
        diskImage(id: id, bucket: bucket)
    }

    /// Downsamples `data`, keeps the result in memory and writes it to disk.
    static func makeThumbnail(from data: Data, id: UUID, bucket: Int, persist: Bool = true) -> UIImage? {
        guard let image = ImageDownsampler.downsample(data, maxPixelSize: bucket) else { return nil }
        remember(image, id: id, bucket: bucket)
        if persist { write(image, id: id, bucket: bucket) }
        return image
    }

    static func writeInBackground(_ image: UIImage, id: UUID, bucket: Int) {
        Task.detached(priority: .utility) {
            write(image, id: id, bucket: bucket)
        }
    }

    private static func write(_ image: UIImage, id: UUID, bucket: Int) {
        guard let url = fileURL(id: id, bucket: bucket),
              let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        try? jpeg.write(to: url, options: .atomic)
    }

    @concurrent
    static func makeThumbnailInBackground(from data: Data, id: UUID, bucket: Int, persist: Bool = true) async -> UIImage? {
        makeThumbnail(from: data, id: id, bucket: bucket, persist: persist)
    }

    /// The smallest cached file for `id` that is at least `minimumPixelSize` on its longer side.
    static func diskFileURL(id: UUID, minimumPixelSize: Int) -> URL? {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        let prefix = id.uuidString + "-"
        let bucket = names
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count).dropLast(4)) }
            .filter { $0 >= minimumPixelSize }
            .min()
        return bucket.flatMap { fileURL(id: id, bucket: $0) }
    }

    static func remove(id: UUID) {
        latest.removeObject(forKey: id.uuidString as NSString)
        Task.detached(priority: .utility) {
            removeFiles { $0.hasPrefix(id.uuidString) }
        }
    }

    /// Removes files for entries that no longer exist, e.g. deleted on another device.
    @concurrent
    static func prune(keeping ids: Set<UUID>) async {
        let kept = Set(ids.map(\.uuidString))
        removeFiles { !kept.contains(String($0.prefix(36))) }
    }

    private static func removeFiles(where shouldRemove: (String) -> Bool) {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where shouldRemove(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func fileURL(id: UUID, bucket: Int) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString)-\(bucket).jpg")
    }

    private static func key(_ id: UUID, _ bucket: Int) -> NSString {
        "\(id.uuidString)-\(bucket)" as NSString
    }
}
