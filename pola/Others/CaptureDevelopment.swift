import ImageIO
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
}

extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}
