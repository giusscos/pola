#if targetEnvironment(simulator)
import SwiftData
import UIKit

/// The simulator has no camera, so the viewfinder shows a still photo and the shutter "captures" it.
/// Drop JPG/PNG files into the app's Documents/SimulatorFeed folder to cycle through your own;
/// otherwise the bundled reference photo is used.
final class SimulatorFeed {
    static let shared = SimulatorFeed()
    static let didAdvance = Notification.Name("SimulatorFeedDidAdvance")

    private let images: [UIImage]
    private var index = 0

    private init() {
        let folder = URL.documentsDirectory.appending(path: "SimulatorFeed")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let loaded = files
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { UIImage(contentsOfFile: $0.path) }
        images = loaded.isEmpty ? [UIImage(named: "filter_reference")].compactMap { $0 } : loaded
    }

    var current: UIImage? { images.isEmpty ? nil : images[index] }

    /// Returns the photo in the viewfinder, then moves on to the next one.
    func capture() -> UIImage? {
        let shot = current
        if images.count > 1 {
            index = (index + 1) % images.count
            NotificationCenter.default.post(name: Self.didAdvance, object: nil)
        }
        return shot
    }

    // MARK: - Screenshot library

    private struct SeedPrint {
        let photo: Int
        let film: String
        var lens: Lens? = nil
        var frame: String? = nil
        var format: FrameFormat = .classic
        let caption: String
    }

    /// A varied library for App Store screenshots: every photo on several stocks, frames and formats.
    private static let seedPrints: [SeedPrint] = [
        SeedPrint(photo: 0, film: "FLÄRN", caption: "Big Sur"),
        SeedPrint(photo: 1, film: "SOLVA", frame: "SOLVA", format: .square, caption: "Micio"),
        SeedPrint(photo: 2, film: "SKIFT", frame: "VYLUR", caption: "Space"),
        SeedPrint(photo: 0, film: "LILJA", format: .wide, caption: "Golden hour"),
        SeedPrint(photo: 1, film: "RÖDA", frame: "FLÄRN", format: .mini, caption: "Nap time"),
        SeedPrint(photo: 0, film: "GRÅLT", frame: "GRÅLT", format: .square, caption: "Dusk"),
        SeedPrint(photo: 0, film: "SKRÍM", lens: .leka, caption: "Last light"),
        SeedPrint(photo: 1, film: "FLÄRN", frame: "BRÖKK", format: .wide, caption: "Sunday"),
    ]

    /// Fills the library once when launched after
    /// `xcrun simctl spawn booted defaults write com.giusscos.pola SeedScreenshotLibrary -bool YES`.
    static func seedLibraryIfRequested(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "SeedScreenshotLibrary") else { return }
        defaults.set(false, forKey: "SeedScreenshotLibrary")
        let photos = shared.images
        guard !photos.isEmpty else { return }

        for (i, print) in seedPrints.enumerated() {
            let film = filmFilter(named: print.film)
            let image = FilmPipeline.apply(to: photos[print.photo % photos.count], film: film?.effect, lens: print.lens)
            let entry = PolaroidEntry(image: image, filterName: film?.name, lensName: print.lens?.name,
                                      packName: print.frame, frameFormat: print.format)
            entry.caption = print.caption
            entry.developmentProgress = 1
            // Newest first in the library, a day apart.
            entry.timestamp = Date().addingTimeInterval(-Double(i) * 86_400)
            context.insert(entry)
        }
        try? context.save()
    }
}
#endif
