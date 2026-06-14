import CoreImage
import SwiftUI

// MARK: - Filter Effect

enum FilmFilterEffect {
    case chrome
    case warm
    case sepia
    case cool
    case noir

    private static let context = CIContext()

    func apply(to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image),
              let output = filtered(ciImage),
              let cgImage = Self.context.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func filtered(_ input: CIImage) -> CIImage? {
        let base: CIImage?
        switch self {
        case .chrome:
            guard let f = CIFilter(name: "CIPhotoEffectChrome") else { return nil }
            f.setValue(input, forKey: kCIInputImageKey)
            base = f.outputImage

        case .warm:
            guard let f = CIFilter(name: "CIColorMatrix") else { return nil }
            f.setValue(input, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 1.12, y: 0, z: 0, w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: 1.06, z: 0, w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0.82, w: 0), forKey: "inputBVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            base = f.outputImage

        case .sepia:
            guard let f = CIFilter(name: "CISepiaTone") else { return nil }
            f.setValue(input, forKey: kCIInputImageKey)
            f.setValue(0.75, forKey: kCIInputIntensityKey)
            base = f.outputImage

        case .cool:
            guard let f = CIFilter(name: "CIColorMatrix") else { return nil }
            f.setValue(input, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 0.88, y: 0, z: 0, w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: 0, y: 0.90, z: 0, w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: 0, y: 0, z: 1.20, w: 0), forKey: "inputBVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            base = f.outputImage

        case .noir:
            guard let f = CIFilter(name: "CIPhotoEffectNoir") else { return nil }
            f.setValue(input, forKey: kCIInputImageKey)
            base = f.outputImage
        }

        guard let base else { return nil }
        guard let vignette = CIFilter(name: "CIVignette") else { return base }
        vignette.setValue(base, forKey: kCIInputImageKey)
        vignette.setValue(0.5, forKey: kCIInputIntensityKey)
        vignette.setValue(1.8, forKey: kCIInputRadiusKey)
        return vignette.outputImage
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
