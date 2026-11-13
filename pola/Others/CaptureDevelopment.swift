import UIKit

/// Film rendering and JPEG encoding for new captures. A 12 MP render takes long enough to freeze
/// the shutter, so both run off the main actor and only the finished data comes back to insert.
nonisolated enum CaptureDevelopment {
    static let jpegQuality: CGFloat = 0.9

    @concurrent
    static func developedJPEG(from image: UIImage, film: FilmFilterEffect?, lens: Lens?) async -> Data {
        let developed = FilmPipeline.apply(to: image, film: film, lens: lens)
        return developed.jpegData(compressionQuality: jpegQuality) ?? Data()
    }

    @concurrent
    static func developed(_ images: [UIImage], film: FilmFilterEffect?, lens: Lens?) async -> [UIImage] {
        images.map { FilmPipeline.apply(to: $0, film: film, lens: lens) }
    }
}
