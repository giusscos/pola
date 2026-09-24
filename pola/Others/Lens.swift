import CoreImage
import SwiftUI

// MARK: - Lens

/// Optical and grain character applied on top of any film stock, the way a camera body
/// keeps its lens whatever film is loaded.
enum Lens: String, CaseIterable, Identifiable {
    case glimt = "GLIMT"  // cheap plastic lens: bulge, colour fringing, soft corners
    case korn  = "KORN"   // coarse, clumpy grain
    case leka  = "LEKA"   // worn toy camera: all of the above plus a light leak

    var id: String { rawValue }
    var name: String { rawValue }

    var color: Color {
        switch self {
        case .glimt: Color(red: 0.55, green: 0.80, blue: 0.95)
        case .korn:  Color(red: 0.62, green: 0.58, blue: 0.52)
        case .leka:  Color(red: 1.0,  green: 0.50, blue: 0.20)
        }
    }

    var isNew: Bool { false }

    func isLocked(for premium: PremiumManager) -> Bool {
        !premium.isPremium
    }

    init?(name: String?) {
        guard let name else { return nil }
        self.init(rawValue: name)
    }

    private struct Recipe {
        var distortion: CGFloat = 0
        var fringe: CGFloat = 0
        /// Corner blur radius as a fraction of the image's short side.
        var softCorners: CGFloat = 0
        var vignette: CGFloat = 0
        /// 0...1, how far grain pushes away from neutral grey.
        var grain: CGFloat = 0
        /// Multiplier on the resolution-relative grain size.
        var grainSize: CGFloat = 1
        var lightLeak = false
    }

    private var recipe: Recipe {
        switch self {
        case .glimt:
            Recipe(distortion: 0.12, fringe: 0.004, softCorners: 0.005, vignette: 0.8, grain: 0.12)
        case .korn:
            Recipe(softCorners: 0.002, vignette: 0.5, grain: 0.35, grainSize: 1.6)
        case .leka:
            Recipe(distortion: 0.2, fringe: 0.008, softCorners: 0.007, vignette: 1.3,
                   grain: 0.3, grainSize: 1.3, lightLeak: true)
        }
    }

    var viewfinderGrainOpacity: Double { Double(recipe.grain) * 1.2 }
    var hasLightLeak: Bool { recipe.lightLeak }

    private static let lensKernel: CIKernel? = {
        guard let data = PolaroidKernels.data else { return nil }
        return try? CIKernel(functionName: "vintageLensKernel", fromMetalLibraryData: data)
    }()

    // MARK: Stages

    /// What the lens does to the light before it reaches the film.
    func applyOptics(to input: CIImage) -> CIImage {
        let recipe = recipe
        var result = input
        if recipe.distortion > 0 || recipe.fringe > 0 {
            result = warp(result, distortion: recipe.distortion, fringe: recipe.fringe)
        }
        if recipe.softCorners > 0 {
            result = softenCorners(result, amount: recipe.softCorners)
        }
        if recipe.vignette > 0, let vignette = CIFilter(name: "CIVignette") {
            vignette.setValue(result,           forKey: kCIInputImageKey)
            vignette.setValue(recipe.vignette,  forKey: kCIInputIntensityKey)
            vignette.setValue(1.6,              forKey: kCIInputRadiusKey)
            result = vignette.outputImage ?? result
        }
        return result
    }

    /// Grain and leaks sit on the developed print, so they go on after the film's colour grade.
    /// `orientation` is how the pixels will be displayed, so the leak lands where the viewfinder shows it.
    func applyFinish(to input: CIImage, orientation: CGImagePropertyOrientation) -> CIImage {
        let recipe = recipe
        var result = input
        if recipe.lightLeak {
            result = addLightLeak(result, orientation: orientation)
        }
        if recipe.grain > 0 {
            result = addGrain(result, strength: recipe.grain, size: recipe.grainSize)
        }
        return result
    }

    // MARK: Effects

    private func warp(_ input: CIImage, distortion: CGFloat, fringe: CGFloat) -> CIImage {
        guard let kernel = Self.lensKernel else { return input }
        let extent = input.extent
        let radius = hypot(extent.width, extent.height) / 2
        // Red fringing samples slightly past the edge; the clamped input fills that in.
        let pad = ceil(radius * fringe) + 2
        let output = kernel.apply(
            extent: extent,
            roiCallback: { _, _ in extent.insetBy(dx: -pad, dy: -pad) },
            arguments: [
                input.clampedToExtent(),
                CIVector(x: extent.midX, y: extent.midY),
                radius,
                distortion,
                fringe,
            ]
        )
        return output ?? input
    }

    private func softenCorners(_ input: CIImage, amount: CGFloat) -> CIImage {
        let extent = input.extent
        let halfDiagonal = hypot(extent.width, extent.height) / 2
        guard let gradient = CIFilter(name: "CIRadialGradient"),
              let blur = CIFilter(name: "CIMaskedVariableBlur") else { return input }
        gradient.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
        gradient.setValue(halfDiagonal * 0.45, forKey: "inputRadius0")
        gradient.setValue(halfDiagonal,        forKey: "inputRadius1")
        gradient.setValue(CIColor.black,       forKey: "inputColor0")
        gradient.setValue(CIColor.white,       forKey: "inputColor1")
        guard let mask = gradient.outputImage?.cropped(to: extent) else { return input }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(mask,                    forKey: "inputMask")
        blur.setValue(min(extent.width, extent.height) * amount, forKey: kCIInputRadiusKey)
        return blur.outputImage?.cropped(to: extent) ?? input
    }

    private func addGrain(_ input: CIImage, strength: CGFloat, size: CGFloat) -> CIImage {
        let extent = input.extent
        // One noise sample per pixel averages away when a 12 MP photo is shown on screen,
        // so grains are sized relative to the image and look the same at every resolution.
        let grainPixels = max(1, min(extent.width, extent.height) / 900 * size)
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage,
              let matrix = CIFilter(name: "CIColorMatrix"),
              let overlay = CIFilter(name: "CIOverlayBlendMode") else { return input }
        let scaled = noise
            .transformed(by: CGAffineTransform(scaleX: grainPixels, y: grainPixels))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        // Monochrome grain centred on 0.5, which overlay treats as "no change".
        let bias = 0.5 - 0.5 * strength
        matrix.setValue(scaled, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: strength, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: strength, y: 0, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: strength, y: 0, z: 0, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1),        forKey: "inputAVector")
        matrix.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
        guard let grain = matrix.outputImage else { return input }
        overlay.setValue(grain, forKey: kCIInputImageKey)
        overlay.setValue(input, forKey: kCIInputBackgroundImageKey)
        return overlay.outputImage?.cropped(to: extent) ?? input
    }

    private func addLightLeak(_ input: CIImage, orientation: CGImagePropertyOrientation) -> CIImage {
        let extent = input.extent
        let shortSide = min(extent.width, extent.height)
        guard let gradient = CIFilter(name: "CIRadialGradient"),
              let screen = CIFilter(name: "CIScreenBlendMode") else { return input }
        // Near the top-left corner as displayed (Core Image's y axis points up).
        let toDisplay = input.orientationTransform(for: orientation)
        let displayed = extent.applying(toDisplay)
        let center = CGPoint(x: displayed.minX + displayed.width * 0.04, y: displayed.minY + displayed.height * 0.78)
            .applying(toDisplay.inverted())
        gradient.setValue(CIVector(cgPoint: center), forKey: kCIInputCenterKey)
        gradient.setValue(0,                forKey: "inputRadius0")
        gradient.setValue(shortSide * 0.7,  forKey: "inputRadius1")
        gradient.setValue(CIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 0.45), forKey: "inputColor0")
        gradient.setValue(CIColor(red: 1.0, green: 0.25, blue: 0.10, alpha: 0.0), forKey: "inputColor1")
        guard let leak = gradient.outputImage?.cropped(to: extent) else { return input }
        screen.setValue(leak,  forKey: kCIInputImageKey)
        screen.setValue(input, forKey: kCIInputBackgroundImageKey)
        return screen.outputImage ?? input
    }
}

// MARK: - Pipeline

enum FilmPipeline {
    private static let context = CIContext()

    /// Lens optics first, then the film stock's grade, then the lens grain and leaks on the print.
    static func apply(to image: UIImage, film: FilmFilterEffect?, lens: Lens?) -> UIImage {
        guard film != nil || lens != nil,
              let input = CIImage(image: image) else { return image }
        var result = lens?.applyOptics(to: input) ?? input
        if let film {
            result = film.apply(to: result)
        }
        if let lens {
            result = lens.applyFinish(to: result, orientation: CGImagePropertyOrientation(image.imageOrientation))
        }
        // Rendering the input's extent keeps blur-based effects from growing the photo.
        guard let cgImage = context.createCGImage(result, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
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

// MARK: - Viewfinder hint

/// The live preview can't run Core Image, so this approximates the lens with moving grain,
/// darker corners and the light leak.
struct LensViewfinderHint: View {
    let lens: Lens

    private static let grainTile: UIImage? = {
        let size: CGFloat = 256
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage,
              let mono = CIFilter(name: "CIColorControls") else { return nil }
        mono.setValue(noise.transformed(by: CGAffineTransform(scaleX: 1.5, y: 1.5)), forKey: kCIInputImageKey)
        mono.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = mono.outputImage,
              let cgImage = CIContext().createCGImage(output, from: CGRect(x: 0, y: 0, width: size, height: size))
        else { return nil }
        return UIImage(cgImage: cgImage)
    }()

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [.clear, .black.opacity(0.45)],
                center: .center,
                startRadius: 110,
                endRadius: 320
            )

            if lens.hasLightLeak {
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.42, blue: 0.12).opacity(0.45), .clear],
                    center: UnitPoint(x: 0.04, y: 0.22),
                    startRadius: 0,
                    endRadius: 300
                )
                .blendMode(.screen)
            }

            if let tile = Self.grainTile {
                TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
                    let seed = context.date.timeIntervalSinceReferenceDate
                    let offset = CGSize(
                        width: -CGFloat(Int(seed * 997) % 256),
                        height: -CGFloat(Int(seed * 631) % 256)
                    )
                    GeometryReader { proxy in
                        Image(uiImage: tile)
                            .resizable(resizingMode: .tile)
                            .frame(width: proxy.size.width + 256, height: proxy.size.height + 256)
                            .offset(offset)
                    }
                    .clipped()
                }
                .blendMode(.overlay)
                .opacity(lens.viewfinderGrainOpacity)
            }
        }
        .allowsHitTesting(false)
    }
}
