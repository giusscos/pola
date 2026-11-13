import CoreLocation
import ImageIO
import SwiftData
import SwiftUI

/// A photo picked from the Photos library, decoded and scaled off the main actor.
struct ImportedPhoto: Sendable {
    /// At most the camera's 12 MP, upright.
    let image: UIImage
    /// About screen size, for the live preview.
    let preview: UIImage
    let date: Date?
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated enum PhotoImporter {
    /// The camera's ceiling (4032 × 3024); panoramas and 48 MP shots are scaled down to it.
    private static let maxPixels: Double = 4032 * 3024
    private static let previewPixelSize = 1200

    @concurrent
    static func load(_ data: Data) async -> ImportedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        let scale = min(1, (maxPixels / (width * height)).squareRoot())
        let longSide = Int((max(width, height) * scale).rounded(.down))
        guard let image = upright(source, maxPixelSize: longSide),
              let preview = upright(source, maxPixelSize: previewPixelSize) else { return nil }
        let gps = gpsCoordinate(properties)
        return ImportedPhoto(image: image, preview: preview, date: captureDate(properties),
                             latitude: gps?.latitude, longitude: gps?.longitude)
    }

    private static func upright(_ source: CGImageSource, maxPixelSize: Int) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }

    /// EXIF "2026:11:13 15:42:07", with its UTC offset when the camera wrote one.
    private static func captureDate(_ properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let text = exif?[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: text + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: text)
    }

    private static func gpsCoordinate(_ properties: [CFString: Any]) -> (latitude: Double, longitude: Double)? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              var longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { longitude = -longitude }
        return (latitude, longitude)
    }
}

/// Gives a photo from the library the same film, lens, frame and format choices as the camera,
/// then prints it. Imports don't count as shots: no milestone paywall, review prompt or photo count.
struct ImportPhotoView: View {
    let photo: ImportedPhoto
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(PremiumManager.self) private var premium
    @AppStorage("captionPromptEnabled") private var captionPromptEnabled = true
    @AppStorage("printAnimationEnabled") private var printAnimationEnabled = true

    @State private var filterName: String?
    @State private var lens: Lens?
    @State private var packName: String?
    @State private var frameFormatRaw: String
    @State private var developedPreview: UIImage?
    @State private var showFilters = false
    @State private var pendingPaywall: PaywallContext?
    @State private var paywallContext: PaywallContext?
    @State private var isDeveloping = false
    @State private var printingEntry: PolaroidEntry?

    init(photo: ImportedPhoto, onFinish: @escaping () -> Void) {
        self.photo = photo
        self.onFinish = onFinish
        // Starts from the camera's frame format and default stock.
        let defaults = UserDefaults.standard
        _frameFormatRaw = State(initialValue: defaults.string(forKey: "selectedFrameFormat") ?? FrameFormat.classic.rawValue)
        _filterName = State(initialValue: filmFilter(named: defaults.string(forKey: "defaultFilter"))?.name)
    }

    private var filter: FilmFilter? { filmFilter(named: filterName) }

    private var frameFormat: FrameFormat {
        let format = FrameFormat(rawValue: frameFormatRaw) ?? .classic
        return format.isFree || premium.isPremium ? format : .classic
    }

    private var lockedPreview: (name: String, context: PaywallContext)? {
        if let filter, filter.isLocked(for: premium) { return (filter.name, .filter(filter.name)) }
        if let lens, lens.isLocked(for: premium) { return (lens.name, .feature(.filmStocks)) }
        return nil
    }

    /// Re-renders the preview whenever the look changes.
    private var lookKey: String { "\(filterName ?? "-")|\(lens?.name ?? "-")" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PolaroidPhotoCell(
                    image: developedPreview ?? photo.preview,
                    developmentProgress: 1.0,
                    timestamp: photo.date,
                    filterName: filterName,
                    packName: packName,
                    fontScale: 1.4
                )
                .aspectRatio(frameFormat.frameAspect, contentMode: .fit)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if let locked = lockedPreview {
                        lockedBanner(name: locked.name, context: locked.context)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Preview"))
                .accessibilityValue(Text(verbatim: filterName ?? NSLocalizedString("Original", comment: "")))

                HStack(spacing: 12) {
                    Button { showFilters = true } label: {
                        Label("Film & Frame", systemImage: "camera.filters")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button { Task { await printPhoto() } } label: {
                        Group {
                            if isDeveloping {
                                ProgressView()
                            } else {
                                Label("Develop", systemImage: "camera.aperture")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDeveloping)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("Import Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinish)
                        .disabled(isDeveloping)
                }
            }
        }
        .sheet(isPresented: $showFilters, onDismiss: {
            if let pending = pendingPaywall {
                pendingPaywall = nil
                paywallContext = pending
            }
        }) {
            FiltersView(selectedFilterName: $filterName, selectedLens: $lens, selectedPackName: $packName,
                        selectedFrameFormatRaw: $frameFormatRaw, onPaywallRequested: { context in
                pendingPaywall = context
                showFilters = false
            })
            .environment(PremiumManager.shared)
        }
        .sheet(item: $paywallContext) { context in
            PaywallView(context: context, previewImage: photo.preview, onClose: { paywallContext = nil })
                .environment(PremiumManager.shared)
        }
        .overlay {
            if let entry = printingEntry {
                PolaroidPrintAnimationView(entry: entry, captionEnabled: captionPromptEnabled, onComplete: onFinish)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .task(id: lookKey) {
            let film = filter?.effect
            let lens = lens
            guard film != nil || lens != nil else {
                developedPreview = nil
                return
            }
            let jpeg = await CaptureDevelopment.developedJPEG(from: photo.preview, film: film, lens: lens)
            guard !Task.isCancelled else { return }
            developedPreview = UIImage(data: jpeg)
        }
    }

    private func lockedBanner(name: String, context: PaywallContext) -> some View {
        Button { paywallContext = context } label: {
            HStack(spacing: 8) {
                Text(String(format: NSLocalizedString("Previewing %@", comment: ""), name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Unlock")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 1.0, green: 0.8, blue: 0.3), in: Capsule())
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .frame(minHeight: 44)
            .background(.black.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func printPhoto() async {
        if let locked = lockedPreview {
            Analytics.track(.lockedFilterCaptureBlocked, ["filter": locked.name, "source": "import"])
            paywallContext = locked.context
            return
        }
        isDeveloping = true
        let jpeg = await CaptureDevelopment.developedJPEG(from: photo.image, film: filter?.effect, lens: lens)
        let entry = PolaroidEntry(
            imageData: jpeg,
            filterName: filterName,
            lensName: lens?.name,
            packName: packName,
            frameFormat: frameFormat,
            coordinate: photo.coordinate
        )
        if let date = photo.date { entry.timestamp = date }
        modelContext.insert(entry)
        isDeveloping = false
        Analytics.track(.importCompleted, ["filter": filterName ?? "none", "lens": lens?.name ?? "none"])
        if printAnimationEnabled {
            withAnimation(.easeIn(duration: 0.15)) { printingEntry = entry }
        } else {
            onFinish()
        }
    }
}
