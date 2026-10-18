import CoreImage
import UIKit

/// Combines two shots the way an instant camera does when the film isn't advanced. The second
/// shot stays at full strength; the first shows through where the second is dark, as unexposed
/// film would keep it, and fades out where the second is bright. Screening only in the shadows
/// keeps blacks black instead of lifting both shots into a grey haze. The film stock is applied
/// afterwards, as with any other photo.
nonisolated enum DoubleExposure {
    private static let context = CIContext()
    /// Range of `balance`: -1 favours the first shot (an even, ghostly mix), 0 is the default look,
    /// 1 favours the second (nearly opaque everywhere, shadows included).
    static let balanceRange: ClosedRange<Double> = -1...1

    static func blend(_ first: UIImage, _ second: UIImage, balance: Double = 0) -> UIImage? {
        let balance = min(max(balance, balanceRange.lowerBound), balanceRange.upperBound)
        guard let base = upright(first), let overlay = upright(second) else { return nil }
        // Both shots come from the same lens and zoom, but fill the second onto the first, as the
        // viewfinder does, in case the capture formats differ.
        let scale = max(base.extent.width / overlay.extent.width, base.extent.height / overlay.extent.height)
        let fitted = overlay
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (base.extent.width - overlay.extent.width * scale) / 2,
                y: (base.extent.height - overlay.extent.height * scale) / 2
            ))
            .cropped(to: base.extent)
        // Toward the first shot the second also dims under the screen, so the mix approaches even.
        let screened = fitted.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: interpolate(balance, first: -1, standard: 0, second: 0)
        ]).applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: base.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: interpolate(balance, first: 0, standard: -0.35, second: -0.6)
            ])
        ])
        let blended = fitted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: screened,
            kCIInputMaskImageKey: solidityMask(for: fitted, balance: balance),
        ])
        guard let cgImage = context.createCGImage(blended, from: base.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: first.scale, orientation: .up)
    }

    /// Bakes the photo's orientation (including front-camera mirroring) into its pixels, so shots
    /// line up as they did in the viewfinder.
    private static func upright(_ image: UIImage) -> CIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let oriented = ciImage.oriented(CGImagePropertyOrientation(image.imageOrientation))
        return oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX,
                                                           y: -oriented.extent.minY))
    }

    /// The second shot's luminance, remapped so its shadows let the first shot through and its
    /// midtones and highlights stay mostly solid. Up to the default, the mask is 0 in the deepest
    /// shadows, so blacks come from the screen of two dark shots; toward the second shot it covers
    /// the shadows too, with the second's own blacks. Either way blacks never lift to grey.
    private static func solidityMask(for image: CIImage, balance: Double) -> CIImage {
        let inputs: [Double] = [0, 0.15, 0.4, 0.65, 1]
        let towardFirst: [Double] = [0, 0.05, 0.25, 0.35, 0.4]
        let standard: [Double] = [0, 0.05, 0.6, 0.85, 0.9]
        let towardSecond: [Double] = [0.97, 0.97, 0.98, 0.99, 1]
        var parameters: [String: Any] = [:]
        for i in inputs.indices {
            let y = interpolate(balance, first: towardFirst[i], standard: standard[i], second: towardSecond[i])
            parameters["inputPoint\(i)"] = CIVector(x: inputs[i], y: y)
        }
        return image
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIToneCurve", parameters: parameters)
    }

    /// Piecewise-linear between the value at -1 (`first`), 0 (`standard`) and 1 (`second`).
    private static func interpolate(_ balance: Double, first: Double, standard: Double, second: Double) -> Double {
        balance < 0 ? standard + (standard - first) * balance : standard + (second - standard) * balance
    }
}

private extension CGImagePropertyOrientation {
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
