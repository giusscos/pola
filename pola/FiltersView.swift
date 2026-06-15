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
              let output  = colorGraded(ciImage),
              let cgImage = Self.context.createCGImage(output, from: output.extent)
        else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
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
