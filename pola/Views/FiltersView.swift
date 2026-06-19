import CoreImage
import SwiftUI

// MARK: - Filter Effect

enum FilmFilterEffect {
    case chrome   // FLÄRN — Kodachrome-inspired pushed contrast
    case warm     // SOLVA — warm analog, Ektar-like
    case sepia    // BRÖKK — old Polaroid SX-70, heavy fade
    case cool     // VYLUR — cross-processed, cyan/purple cast
    case noir     // GRÅLT — silver-gelatin B&W, heavy grain

    private static let context = CIContext()

    func apply(to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image),
              let graded  = colorGraded(ciImage)
        else { return image }
        var result = graded
        result = fadeFilm(result) ?? result
        result = addFilmGrain(result) ?? result
        result = addVignette(result) ?? result
        guard let cgImage = Self.context.createCGImage(result, from: result.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    // How much to lift the black point (faded-film look). Noir keeps deep blacks.
    private var shadowLift: CGFloat {
        switch self {
        case .chrome: return 0.04
        case .warm:   return 0.04
        case .sepia:  return 0.07
        case .cool:   return 0.03
        case .noir:   return 0.0
        }
    }

    // Contrast value fed to CIColorControls on the noise: lower = subtler grain.
    private var grainContrast: CGFloat {
        switch self {
        case .chrome: return 0.75
        case .warm:   return 0.65
        case .sepia:  return 0.80
        case .cool:   return 0.72
        case .noir:   return 1.10
        }
    }

    private var vignetteStrength: CGFloat {
        switch self {
        case .chrome: return 1.2
        case .warm:   return 0.9
        case .sepia:  return 1.4
        case .cool:   return 1.2
        case .noir:   return 1.8
        }
    }

    // Lift blacks to simulate faded / aged film stock.
    private func fadeFilm(_ input: CIImage) -> CIImage? {
        let lift = shadowLift
        guard lift > 0,
              let matrix = CIFilter(name: "CIColorMatrix") else { return input }
        let scale = 1.0 - lift
        matrix.setValue(input, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0,     w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: lift, y: lift, z: lift, w: 0), forKey: "inputBiasVector")
        return matrix.outputImage
    }

    // Overlay random grayscale noise via soft-light blend for a film-grain look.
    private func addFilmGrain(_ input: CIImage) -> CIImage? {
        guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
              let rawNoise = noiseFilter.outputImage else { return input }
        let cropped = rawNoise.cropped(to: input.extent)
        guard let controls = CIFilter(name: "CIColorControls") else { return input }
        controls.setValue(cropped, forKey: kCIInputImageKey)
        controls.setValue(0.0,         forKey: kCIInputSaturationKey)
        controls.setValue(grainContrast, forKey: kCIInputContrastKey)
        guard let grain = controls.outputImage else { return input }
        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return input }
        blend.setValue(grain, forKey: kCIInputImageKey)
        blend.setValue(input, forKey: kCIInputBackgroundImageKey)
        return blend.outputImage
    }

    private func addVignette(_ input: CIImage) -> CIImage? {
        guard let vignette = CIFilter(name: "CIVignette") else { return input }
        vignette.setValue(input,            forKey: kCIInputImageKey)
        vignette.setValue(vignetteStrength, forKey: kCIInputIntensityKey)
        vignette.setValue(1.75,             forKey: kCIInputRadiusKey)
        return vignette.outputImage
    }

    private func colorGraded(_ input: CIImage) -> CIImage? {
        switch self {
        case .chrome:
            guard let chrome   = CIFilter(name: "CIPhotoEffectChrome"),
                  let controls = CIFilter(name: "CIColorControls") else { return input }
            chrome.setValue(input, forKey: kCIInputImageKey)
            guard let out = chrome.outputImage else { return input }
            controls.setValue(out, forKey: kCIInputImageKey)
            controls.setValue(1.08, forKey: kCIInputContrastKey)
            controls.setValue(1.06, forKey: kCIInputSaturationKey)
            return controls.outputImage ?? out

        case .warm:
            guard let temp     = CIFilter(name: "CITemperatureAndTint"),
                  let controls = CIFilter(name: "CIColorControls") else { return input }
            temp.setValue(input, forKey: kCIInputImageKey)
            temp.setValue(CIVector(x: 6500, y: 0),  forKey: "inputNeutral")
            temp.setValue(CIVector(x: 5000, y: 20), forKey: "inputTargetNeutral")
            guard let out = temp.outputImage else { return input }
            controls.setValue(out, forKey: kCIInputImageKey)
            controls.setValue(0.92, forKey: kCIInputSaturationKey)
            controls.setValue(0.03, forKey: kCIInputBrightnessKey)
            return controls.outputImage ?? out

        case .sepia:
            guard let f        = CIFilter(name: "CISepiaTone"),
                  let controls = CIFilter(name: "CIColorControls") else { return input }
            f.setValue(input, forKey: kCIInputImageKey)
            f.setValue(0.88,  forKey: kCIInputIntensityKey)
            guard let out = f.outputImage else { return input }
            controls.setValue(out, forKey: kCIInputImageKey)
            controls.setValue(0.90, forKey: kCIInputContrastKey)
            return controls.outputImage ?? out

        case .cool:
            guard let matrix   = CIFilter(name: "CIColorMatrix"),
                  let controls = CIFilter(name: "CIColorControls") else { return input }
            matrix.setValue(input, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0.82, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 0.94, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1.28, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0,    w: 1), forKey: "inputAVector")
            guard let out = matrix.outputImage else { return input }
            controls.setValue(out, forKey: kCIInputImageKey)
            controls.setValue(1.12, forKey: kCIInputSaturationKey)
            return controls.outputImage ?? out

        case .noir:
            guard let noir     = CIFilter(name: "CIPhotoEffectNoir"),
                  let controls = CIFilter(name: "CIColorControls") else { return input }
            noir.setValue(input, forKey: kCIInputImageKey)
            guard let out = noir.outputImage else { return input }
            controls.setValue(out, forKey: kCIInputImageKey)
            controls.setValue(1.18, forKey: kCIInputContrastKey)
            return controls.outputImage ?? out
        }
    }
}

// MARK: - Model

struct FilmFilter: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let usdzName: String?
    let effect: FilmFilterEffect?

    var previewSaturation: Double {
        guard let effect else { return 1.0 }
        if case .noir = effect { return 0.2 }
        if case .cool = effect { return 1.1 }
        return 1.0
    }

    var previewTintColor: Color? {
        guard effect != nil else { return nil }
        return color
    }
}

let filmFilters: [FilmFilter] = [
    FilmFilter(name: "FLÄRN", color: Color(red: 0.95, green: 0.78, blue: 0.12), usdzName: "FLARN_film35", effect: .chrome),
    FilmFilter(name: "SOLVA", color: Color(red: 0.96, green: 0.72, blue: 0.54), usdzName: "SOLVA_film35", effect: .warm),
    FilmFilter(name: "BRÖKK", color: Color(red: 0.78, green: 0.43, blue: 0.22), usdzName: "BROKK_film35", effect: .sepia),
    FilmFilter(name: "VYLUR", color: Color(red: 0.68, green: 0.27, blue: 0.82), usdzName: "VYLUR_film35", effect: .cool),
    FilmFilter(name: "GRÅLT", color: Color(red: 0.28, green: 0.28, blue: 0.28), usdzName: "GRALT_film35", effect: .noir),
]

// MARK: - Pack Model

struct PolaPackColor: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let usdzName: String
}

let polaPackColors: [PolaPackColor] = [
    PolaPackColor(name: "FLÄRN", color: Color(red: 0.95, green: 0.78, blue: 0.12), usdzName: "FLARN_instant_pack"),
    PolaPackColor(name: "SOLVA", color: Color(red: 0.96, green: 0.72, blue: 0.54), usdzName: "SOLVA_instant_pack"),
    PolaPackColor(name: "BRÖKK", color: Color(red: 0.78, green: 0.43, blue: 0.22), usdzName: "BROKK_instant_pack"),
    PolaPackColor(name: "VYLUR", color: Color(red: 0.68, green: 0.27, blue: 0.82), usdzName: "VYLUR_instant_pack"),
    PolaPackColor(name: "GRÅLT", color: Color(red: 0.28, green: 0.28, blue: 0.28), usdzName: "GRALT_instant_pack"),
]

// MARK: - FiltersView

struct FiltersView: View {
    @Binding var selectedFilterName: String?
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(filmFilters) { filter in
                        let isSelected = selectedFilterName == filter.name
                        Button {
                            selectedFilterName = isSelected ? nil : filter.name
                            dismiss()
                        } label: {
                            FilterItemCell(filter: filter, isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: .center, spacing: 0) {
                        Text("Filters")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                        Text("\(filmFilters.count) filters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    FiltersView(selectedFilterName: .constant(nil))
}
