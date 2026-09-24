import CoreImage
import SwiftUI

// MARK: - Filter Effect

enum FilmFilterEffect {
    case chrome   // FLÄRN — Kodachrome-inspired pushed contrast
    case warm     // SOLVA — warm analog, Ektar-like
    case sepia    // BRÖKK — old Polaroid SX-70, heavy fade
    case cool     // VYLUR — cross-processed, cyan/purple cast
    case noir     // GRÅLT — silver-gelatin B&W, heavy grain
    case lomur    // LÖMUR — false-color thermal imaging
    case dreki    // DREKI — infrared film
    case skrim    // SKRÍM — horror VHS
    case frosinn  // FROSINN — cyanotype / blueprint
    case nott     // NÓTT — lo-fi night vision

    private static let thermalKernel: CIColorKernel? = {
        guard let data = PolaroidKernels.data else { return nil }
        return try? CIColorKernel(functionName: "thermalKernel", fromMetalLibraryData: data)
    }()

    private static let cyanotypeKernel: CIColorKernel? = {
        guard let data = PolaroidKernels.data else { return nil }
        return try? CIColorKernel(functionName: "cyanotypeKernel", fromMetalLibraryData: data)
    }()

    private static let nightVisionKernel: CIColorKernel? = {
        guard let data = PolaroidKernels.data else { return nil }
        return try? CIColorKernel(functionName: "nightVisionKernel", fromMetalLibraryData: data)
    }()

    private static let vhsKernel: CIKernel? = {
        guard let data = PolaroidKernels.data else { return nil }
        return try? CIKernel(functionName: "vhsKernel", fromMetalLibraryData: data)
    }()

    func apply(to image: UIImage) -> UIImage {
        FilmPipeline.apply(to: image, film: self, lens: nil)
    }

    func apply(to input: CIImage) -> CIImage {
        guard let graded = colorGraded(input) else { return input }
        var result = graded
        if let lift = shadowLift {
            result = fadeFilm(result, lift: lift) ?? result
        }
        if let grain = grainContrast {
            result = addFilmGrain(result, contrast: grain) ?? result
        }
        if let strength = vignetteStrength {
            result = addVignette(result, strength: strength, radius: vignetteRadius) ?? result
        }
        if appliesGloom {
            result = addGloom(result) ?? result
        }
        // Never let an effect change the photo's size.
        return result.cropped(to: input.extent)
    }

    private var shadowLift: CGFloat? {
        switch self {
        case .chrome: return 0.04
        case .warm:   return 0.04
        case .sepia:  return 0.07
        case .cool:   return 0.03
        case .noir:   return 0.0
        case .lomur, .dreki, .skrim, .frosinn, .nott: return nil
        }
    }

    private var grainContrast: CGFloat? {
        switch self {
        case .chrome:  return 0.75
        case .warm:    return 0.65
        case .sepia:   return 0.80
        case .cool:    return 0.72
        case .noir:    return 1.10
        case .skrim:   return 1.40
        case .nott:    return 1.60
        case .lomur, .dreki, .frosinn: return nil
        }
    }

    private var vignetteStrength: CGFloat? {
        switch self {
        case .chrome:  return 1.2
        case .warm:    return 0.9
        case .sepia:   return 1.4
        case .cool:    return 1.2
        case .noir:    return 1.8
        case .lomur:   return 0.8
        case .nott:    return 2.0
        case .dreki, .skrim, .frosinn: return nil
        }
    }

    private var vignetteRadius: CGFloat {
        switch self {
        case .nott: return 1.5
        default:    return 1.75
        }
    }

    private var appliesGloom: Bool {
        if case .skrim = self { return true }
        return false
    }

    private func fadeFilm(_ input: CIImage, lift: CGFloat) -> CIImage? {
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

    private func addFilmGrain(_ input: CIImage, contrast: CGFloat) -> CIImage? {
        guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
              let rawNoise = noiseFilter.outputImage else { return input }
        let cropped = rawNoise.cropped(to: input.extent)
        guard let controls = CIFilter(name: "CIColorControls") else { return input }
        controls.setValue(cropped, forKey: kCIInputImageKey)
        controls.setValue(0.0,      forKey: kCIInputSaturationKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        guard let grain = controls.outputImage else { return input }
        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return input }
        blend.setValue(grain, forKey: kCIInputImageKey)
        blend.setValue(input, forKey: kCIInputBackgroundImageKey)
        return blend.outputImage
    }

    private func addVignette(_ input: CIImage, strength: CGFloat, radius: CGFloat) -> CIImage? {
        guard let vignette = CIFilter(name: "CIVignette") else { return input }
        vignette.setValue(input,    forKey: kCIInputImageKey)
        vignette.setValue(strength, forKey: kCIInputIntensityKey)
        vignette.setValue(radius,   forKey: kCIInputRadiusKey)
        return vignette.outputImage
    }

    // CIGloom blurs, so it samples past the edges and grows the extent: clamp first so the
    // borders don't fade to transparent, then crop back to the original frame.
    private func addGloom(_ input: CIImage) -> CIImage? {
        guard let gloom = CIFilter(name: "CIGloom") else { return input }
        gloom.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        gloom.setValue(5.0,   forKey: kCIInputRadiusKey)
        gloom.setValue(0.4,   forKey: kCIInputIntensityKey)
        return gloom.outputImage?.cropped(to: input.extent)
    }

    private func applyColorKernel(_ kernel: CIColorKernel?, to input: CIImage) -> CIImage {
        guard let kernel else { return input }
        return kernel.apply(extent: input.extent, roiCallback: { _, rect in rect }, arguments: [input]) ?? input
    }

    private func applyGeneralKernel(_ kernel: CIKernel?, to input: CIImage) -> CIImage {
        guard let kernel else { return input }
        let bleed: CGFloat = 4
        return kernel.apply(
            extent: input.extent,
            roiCallback: { _, rect in rect.insetBy(dx: -bleed, dy: 0) },
            arguments: [input, 0.0 as Any]
        ) ?? input
    }

    private func liftBlacks(_ input: CIImage, by lift: CGFloat) -> CIImage? {
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return input }
        let scale = 1.0 - lift
        matrix.setValue(input, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: scale, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: scale, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: scale, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0,     w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: lift, y: lift, z: lift, w: 0), forKey: "inputBiasVector")
        return matrix.outputImage
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

        case .lomur:
            guard let mono = CIFilter(name: "CIPhotoEffectMono") else { return input }
            mono.setValue(input, forKey: kCIInputImageKey)
            guard let monoOut = mono.outputImage else { return input }
            return applyColorKernel(Self.thermalKernel, to: monoOut)

        case .dreki:
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return input }
            matrix.setValue(input, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0.1, y: 1.2, z: 0.3, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0,   y: 0.4, z: 0,   w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0,   y: 0,   z: 0.5, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            guard let matrixOut = matrix.outputImage else { return input }

            guard let controls = CIFilter(name: "CIColorControls") else { return matrixOut }
            controls.setValue(matrixOut, forKey: kCIInputImageKey)
            controls.setValue(0.3,   forKey: kCIInputSaturationKey)
            controls.setValue(1.15, forKey: kCIInputContrastKey)
            guard let controlsOut = controls.outputImage else { return matrixOut }

            guard let fade = CIFilter(name: "CIPhotoEffectFade") else { return controlsOut }
            fade.setValue(controlsOut, forKey: kCIInputImageKey)
            guard let faded = fade.outputImage else { return controlsOut }

            guard let dissolve = CIFilter(name: "CIDissolveTransition") else { return controlsOut }
            dissolve.setValue(controlsOut, forKey: kCIInputImageKey)
            dissolve.setValue(faded,       forKey: kCIInputTargetImageKey)
            dissolve.setValue(0.5,         forKey: kCIInputTimeKey)
            guard let blended = dissolve.outputImage else { return controlsOut }

            guard let vignette = CIFilter(name: "CIVignette") else { return blended }
            vignette.setValue(blended, forKey: kCIInputImageKey)
            vignette.setValue(1.1,     forKey: kCIInputIntensityKey)
            vignette.setValue(2.0,     forKey: kCIInputRadiusKey)
            guard let vignetted = vignette.outputImage else { return blended }

            return liftBlacks(vignetted, by: 0.05) ?? vignetted

        case .skrim:
            guard let temp     = CIFilter(name: "CITemperatureAndTint"),
                  let controls = CIFilter(name: "CIColorControls") else { return input }
            temp.setValue(input, forKey: kCIInputImageKey)
            temp.setValue(CIVector(x: 6500, y: 0),    forKey: "inputNeutral")
            temp.setValue(CIVector(x: 6500, y: -80),  forKey: "inputTargetNeutral")
            guard let tempOut = temp.outputImage else { return input }
            controls.setValue(tempOut, forKey: kCIInputImageKey)
            controls.setValue(1.3,    forKey: kCIInputSaturationKey)
            controls.setValue(0.95,   forKey: kCIInputContrastKey)
            controls.setValue(-0.05,  forKey: kCIInputBrightnessKey)
            guard let graded = controls.outputImage else { return tempOut }
            return applyGeneralKernel(Self.vhsKernel, to: graded)

        case .frosinn:
            guard let mono = CIFilter(name: "CIPhotoEffectMono") else { return input }
            mono.setValue(input, forKey: kCIInputImageKey)
            guard let monoOut = mono.outputImage else { return input }
            var result = applyColorKernel(Self.cyanotypeKernel, to: monoOut)
            guard let controls = CIFilter(name: "CIColorControls") else { return result }
            controls.setValue(result, forKey: kCIInputImageKey)
            controls.setValue(1.05, forKey: kCIInputContrastKey)
            result = controls.outputImage ?? result
            return result

        case .nott:
            return applyColorKernel(Self.nightVisionKernel, to: input)
        }
    }
}

// MARK: - Model

struct FilmFilter: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let imageName: String?
    let effect: FilmFilterEffect?
    var isFree: Bool = false
    var isNew: Bool = false

    var previewSaturation: Double {
        guard let effect else { return 1.0 }
        switch effect {
        case .noir:    return 0.2
        case .cool:    return 1.1
        case .frosinn: return 0.4
        case .nott:    return 0.3
        case .lomur:   return 1.2
        default:       return 1.0
        }
    }

    var previewTintColor: Color? {
        guard effect != nil else { return nil }
        return color
    }
}

let filmFilters: [FilmFilter] = [
    FilmFilter(name: "FLÄRN", color: Color(red: 0.95, green: 0.78, blue: 0.12), imageName: "filter_flarn", effect: .chrome),
    FilmFilter(name: "SOLVA", color: Color(red: 0.96, green: 0.72, blue: 0.54), imageName: "filter_solva", effect: .warm, isFree: true),
    FilmFilter(name: "BRÖKK", color: Color(red: 0.78, green: 0.43, blue: 0.22), imageName: "filter_brokk", effect: .sepia),
    FilmFilter(name: "VYLUR", color: Color(red: 0.68, green: 0.27, blue: 0.82), imageName: "filter_vylur", effect: .cool),
    FilmFilter(name: "GRÅLT", color: Color(red: 0.28, green: 0.28, blue: 0.28), imageName: "filter_gralt", effect: .noir),
]

let weirdFilters: [FilmFilter] = [
    FilmFilter(name: "LÖMUR",  color: Color(red: 1.0,  green: 0.45, blue: 0.0),  imageName: nil, effect: .lomur, isNew: true),
    FilmFilter(name: "DREKI",  color: Color(red: 0.95, green: 0.85, blue: 0.90), imageName: nil, effect: .dreki, isNew: true),
    FilmFilter(name: "SKRÍM",  color: Color(red: 0.15, green: 0.75, blue: 0.35), imageName: nil, effect: .skrim, isNew: true),
    FilmFilter(name: "FROSINN", color: Color(red: 0.1, green: 0.35, blue: 0.75),  imageName: nil, effect: .frosinn, isNew: true),
    FilmFilter(name: "NÓTT",   color: Color(red: 0.18, green: 0.88, blue: 0.42), imageName: nil, effect: .nott, isNew: true),
]

let allFilters: [FilmFilter] = filmFilters + weirdFilters

extension FilmFilter {
    func isLocked(for premium: PremiumManager) -> Bool {
        !isFree && !premium.isPremium
    }
}

/// Bump `latestDropID` whenever a new filter pack ships so the NEW badges and the FILM dot reappear.
enum FilmDrops {
    static let latestDropID = 1
    static let seenKey = "seenFilmDropID"
}

func filmFilter(named name: String?) -> FilmFilter? {
    guard let name else { return nil }
    return allFilters.first { $0.name == name }
}

// MARK: - Pack Model

struct PolaPackColor: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    var isFree: Bool = false

    func isLocked(for premium: PremiumManager) -> Bool {
        !isFree && !premium.isPremium
    }
}

let polaPackColors: [PolaPackColor] = [
    PolaPackColor(name: "FLÄRN", color: Color(red: 0.95, green: 0.78, blue: 0.12)),
    PolaPackColor(name: "SOLVA", color: Color(red: 0.96, green: 0.72, blue: 0.54), isFree: true),
    PolaPackColor(name: "BRÖKK", color: Color(red: 0.78, green: 0.43, blue: 0.22)),
    PolaPackColor(name: "VYLUR", color: Color(red: 0.68, green: 0.27, blue: 0.82)),
    PolaPackColor(name: "GRÅLT", color: Color(red: 0.28, green: 0.28, blue: 0.28)),
]

// MARK: - FiltersView

struct FiltersView: View {
    @Binding var selectedFilterName: String?
    @Binding var selectedLens: Lens?
    @Binding var selectedPackName: String?
    @Binding var selectedFrameFormatRaw: String
    var onPaywallRequested: ((PaywallContext) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(PremiumManager.self) private var premium
    @AppStorage(FilmDrops.seenKey) private var seenDropID = 0

    private let referenceImage: UIImage? = UIImage(named: "filter_reference")
    @State private var filterPreviews: [String: UIImage] = [:]
    // Keyed by lens name, with "" for no lens; each shows the selected film through that lens.
    @State private var lensPreviews: [String: UIImage] = [:]
    // Captured on open so NEW badges stay visible for this visit even though we mark the drop as seen.
    @State private var showNewBadges = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(LocalizedStringKey(premium.isPremium
                         ? "Pick a stock to give your polaroids an analog film look."
                         : "Tap any stock to preview it in the viewfinder. SOLVA is on the house."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    // Pack names are product names and stay in English, like the stock names.
                    Text(verbatim: "Classic Film")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    filterGrid(for: filmFilters, includeOriginal: true)

                    HStack(spacing: 8) {
                        Text(verbatim: "Weird Film")
                            .font(.headline)
                        if showNewBadges {
                            NewBadge()
                        }
                    }
                    .padding(.horizontal, 20)

                    filterGrid(for: weirdFilters, includeOriginal: false)

                    HStack(spacing: 8) {
                        Text("Lens")
                            .font(.headline)
                        if showNewBadges {
                            NewBadge()
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("Grain and vintage optics, stacked on top of any film.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, -12)

                    lensGrid

                    Text("Frame")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    frameRow

                    Text("Format")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    formatRow
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.large)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            showNewBadges = seenDropID < FilmDrops.latestDropID
            seenDropID = FilmDrops.latestDropID
        }
        .task {
            await generatePreviews()
        }
    }

    private func filterGrid(for filters: [FilmFilter], includeOriginal: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            if includeOriginal {
                originalCell
            }

            ForEach(filters) { filter in
                let isSelected = selectedFilterName == filter.name
                let locked = filter.isLocked(for: premium)
                Button {
                    // Locked stocks can still be picked: the viewfinder previews them and the
                    // shutter asks to unlock, so people see the look before being asked to pay.
                    if locked && !isSelected {
                        Analytics.track(.lockedFilterPreviewed, ["filter": filter.name])
                    }
                    selectedFilterName = isSelected ? nil : filter.name
                    dismiss()
                } label: {
                    FilterItemCell(
                        name: filter.name,
                        color: filter.color,
                        imageName: filter.imageName,
                        isSelected: isSelected,
                        locked: locked,
                        showNewBadge: showNewBadges && filter.isNew,
                        showFreeBadge: filter.isFree && !premium.isPremium,
                        previewImage: filterPreviews[filter.name]
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var lensGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            lensCell(nil)
            ForEach(Lens.allCases) { lens in
                lensCell(lens)
            }
        }
        .padding(.horizontal, 16)
    }

    // Unlike film stocks, picking a lens keeps the sheet open so it can be paired with a stock.
    private func lensCell(_ lens: Lens?) -> some View {
        let isSelected = selectedLens == lens
        let locked = lens?.isLocked(for: premium) ?? false
        return Button {
            if let lens, locked, !isSelected {
                Analytics.track(.lockedFilterPreviewed, ["filter": lens.name])
            }
            selectedLens = lens
        } label: {
            FilterItemCell(
                name: lens?.name ?? NSLocalizedString("No lens", comment: ""),
                color: lens?.color ?? .secondary,
                imageName: lens == nil ? "filter_reference" : nil,
                isSelected: isSelected,
                locked: locked,
                showNewBadge: showNewBadges && lens?.isNew == true,
                previewImage: lensPreviews[lens?.name ?? ""]
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedLens)
    }

    private var frameRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                frameSwatch(name: nil, color: .white, locked: false)
                ForEach(polaPackColors) { pack in
                    frameSwatch(name: pack.name, color: pack.color, locked: pack.isLocked(for: premium))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var formatRow: some View {
        HStack(spacing: 10) {
            ForEach(FrameFormat.allCases) { format in
                formatChip(format)
            }
        }
        .padding(.horizontal, 20)
    }

    private func formatChip(_ format: FrameFormat) -> some View {
        let isSelected = selectedFrameFormatRaw == format.rawValue
        let locked = !format.isFree && !premium.isPremium
        return Button {
            if locked {
                onPaywallRequested?(.feature(.frameFormats))
            } else {
                selectedFrameFormatRaw = format.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Miniature polaroid in the format's proportions
                    let height: CGFloat = 46
                    let width = min(56, height * format.frameAspect)
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .padding([.horizontal, .top], 3)
                        Color.clear.frame(height: 8)
                    }
                    .frame(width: width, height: width / format.frameAspect)
                    .background(.white)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(LocalizedStringKey(format.displayName))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(locked ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedFrameFormatRaw)
    }

    private func frameSwatch(name: String?, color: Color, locked: Bool) -> some View {
        let isSelected = selectedPackName == name
        return Button {
            if locked {
                onPaywallRequested?(.feature(.frameColors))
            } else {
                selectedPackName = name
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 44, height: 54)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 36, height: 36)
                                .padding(.top, 4)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Circle())
                            .offset(y: -6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                        .padding(-4)
                )

                Text(name ?? NSLocalizedString("Classic", comment: ""))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(locked ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedPackName)
    }

    private var originalCell: some View {
        let isSelected = selectedFilterName == nil
        return Button {
            selectedFilterName = nil
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let ref = referenceImage {
                        Image(uiImage: ref)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .background(.white, in: .circle)
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.blue : .clear, lineWidth: 3)
                )

                Text("Original")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func generatePreviews() async {
        guard let ref = referenceImage else { return }
        let size = CGSize(width: 240, height: 240)
        let small = ref.preparingThumbnail(of: size) ?? ref
        var previews: [String: UIImage] = [:]
        for filter in allFilters {
            guard let effect = filter.effect else { continue }
            previews[filter.name] = effect.apply(to: small)
        }
        filterPreviews = previews

        let film = filmFilter(named: selectedFilterName)?.effect
        var lensed: [String: UIImage] = ["": previews[selectedFilterName ?? ""] ?? small]
        for lens in Lens.allCases {
            lensed[lens.name] = FilmPipeline.apply(to: small, film: film, lens: lens)
        }
        lensPreviews = lensed
    }
}

struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.system(size: 9, weight: .heavy).width(.expanded))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: 1.0, green: 0.8, blue: 0.3), in: Capsule())
    }
}

#Preview {
    FiltersView(selectedFilterName: .constant(nil), selectedLens: .constant(nil), selectedPackName: .constant(nil), selectedFrameFormatRaw: .constant("classic"))
        .environment(PremiumManager.shared)
}
