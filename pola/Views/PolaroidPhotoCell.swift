import AVFoundation
import MapKit
import SwiftUI

enum PolaroidFontWeight: String, CaseIterable {
    case thin
    case regular
    case semibold
    case bold

    var displayName: String {
        switch self {
        case .thin: NSLocalizedString("Thin", comment: "Font weight")
        case .regular: NSLocalizedString("Normal", comment: "Font weight")
        case .semibold: NSLocalizedString("Semibold", comment: "Font weight")
        case .bold: NSLocalizedString("Bold", comment: "Font weight")
        }
    }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .thin: .thin
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var uiFontWeight: UIFont.Weight {
        switch self {
        case .thin: .thin
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum PolaroidFont: String, CaseIterable {
    case handwriting
    case sansNormal
    case sansExpanded
    case sansCondensed
    case serif
    case rounded

    var displayName: String {
        switch self {
        case .handwriting: NSLocalizedString("Handwriting", comment: "Caption font")
        case .sansNormal: NSLocalizedString("Default", comment: "Caption font")
        case .sansExpanded: NSLocalizedString("Default Wide", comment: "Caption font")
        case .sansCondensed: NSLocalizedString("Default Narrow", comment: "Caption font")
        case .serif: NSLocalizedString("Serif", comment: "Caption font")
        case .rounded: NSLocalizedString("Rounded", comment: "Caption font")
        }
    }

    func swiftUIFont(size: CGFloat, weight: PolaroidFontWeight = .regular) -> Font {
        switch self {
        case .handwriting: .custom("Bradley Hand", size: size)
        case .sansNormal: .system(size: size, weight: weight.swiftUIWeight)
        case .sansExpanded: .system(size: size, weight: weight.swiftUIWeight).width(.expanded)
        case .sansCondensed: .system(size: size, weight: weight.swiftUIWeight).width(.condensed)
        case .serif: .system(size: size, weight: weight.swiftUIWeight, design: .serif)
        case .rounded: .system(size: size, weight: weight.swiftUIWeight, design: .rounded)
        }
    }

    func uiFont(size: CGFloat, weight: PolaroidFontWeight = .regular) -> UIFont {
        let w = weight.uiFontWeight
        switch self {
        case .handwriting:
            return UIFont(name: "Bradley Hand", size: size) ?? UIFont.systemFont(ofSize: size, weight: w)
        case .sansNormal:
            return UIFont.systemFont(ofSize: size, weight: w)
        case .sansExpanded:
            return UIFont.systemFont(ofSize: size, weight: w, width: .expanded)
        case .sansCondensed:
            return UIFont.systemFont(ofSize: size, weight: w, width: .condensed)
        case .serif:
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            guard let designed = base.withDesign(.serif) else { return UIFont.systemFont(ofSize: size, weight: w) }
            let weighted = designed.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: w.rawValue]])
            return UIFont(descriptor: weighted.withSize(size), size: size)
        case .rounded:
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            guard let designed = base.withDesign(.rounded) else { return UIFont.systemFont(ofSize: size, weight: w) }
            let weighted = designed.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: w.rawValue]])
            return UIFont(descriptor: weighted.withSize(size), size: size)
        }
    }
}

struct PolaroidPhotoCell: View {
    var image: UIImage? = nil
    var videoURL: URL? = nil
    var isTimelapse: Bool = false
    var playVideo: Bool = true
    var isVideoPlaying: Bool = true
    var isVideoLooping: Bool = true
    var developmentProgress: Double = 1.0
    var animatedExternally: Bool = false
    var caption: String = ""
    var backText: String = ""
    var showMap: Bool = true
    var coordinate: CLLocationCoordinate2D? = nil
    var timestamp: Date? = nil
    var filterName: String? = nil
    var packName: String? = nil
    var packColorHex: String? = nil
    var fontScale: CGFloat = 1.0
    var onDeveloped: (() -> Void)? = nil
    var onSingleTap: (() -> Void)? = nil

    @AppStorage("polaroidFont") private var polaroidFontRaw: String = PolaroidFont.handwriting.rawValue
    @AppStorage("polaroidFontWeight") private var polaroidFontWeightRaw: String = PolaroidFontWeight.regular.rawValue
    @AppStorage("dateStampEnabled") private var dateStampEnabled = false
    @State private var localReveal: Double
    @State private var flipAngle: Double = 0
    @State private var showingBack = false

    private var currentFont: PolaroidFont { PolaroidFont(rawValue: polaroidFontRaw) ?? .handwriting }
    private var currentWeight: PolaroidFontWeight { PolaroidFontWeight(rawValue: polaroidFontWeightRaw) ?? .regular }

    init(
        image: UIImage? = nil,
        videoURL: URL? = nil,
        isTimelapse: Bool = false,
        playVideo: Bool = true,
        isVideoPlaying: Bool = true,
        isVideoLooping: Bool = true,
        developmentProgress: Double = 1.0,
        animatedExternally: Bool = false,
        caption: String = "",
        backText: String = "",
        showMap: Bool = true,
        coordinate: CLLocationCoordinate2D? = nil,
        timestamp: Date? = nil,
        filterName: String? = nil,
        packName: String? = nil,
        packColorHex: String? = nil,
        fontScale: CGFloat = 1.0,
        onDeveloped: (() -> Void)? = nil,
        onSingleTap: (() -> Void)? = nil
    ) {
        self.image = image
        self.videoURL = videoURL
        self.isTimelapse = isTimelapse
        self.playVideo = playVideo
        self.isVideoPlaying = isVideoPlaying
        self.isVideoLooping = isVideoLooping
        self.developmentProgress = developmentProgress
        self.animatedExternally = animatedExternally
        self.caption = caption
        self.backText = backText
        self.showMap = showMap
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.filterName = filterName
        self.packName = packName
        self.packColorHex = packColorHex
        self.fontScale = fontScale
        self.onDeveloped = onDeveloped
        self.onSingleTap = onSingleTap

        if developmentProgress >= 1.0 {
            self._localReveal = State(initialValue: 1.0)
        } else if animatedExternally {
            self._localReveal = State(initialValue: developmentProgress)
        } else if let ts = timestamp {
            let elapsed = Date().timeIntervalSince(ts)
            let timeBased = min(1.0, elapsed / 30.0)
            self._localReveal = State(initialValue: max(developmentProgress, timeBased))
        } else {
            self._localReveal = State(initialValue: 0.0)
        }

        self._flipAngle = State(initialValue: 0)
        self._showingBack = State(initialValue: false)
    }

    private var revealProgress: Double {
        animatedExternally ? developmentProgress : localReveal
    }

    private var borderColor: Color {
        if let hex = packColorHex, let c = Color(hex: hex) { return c }
        guard let packName else { return .white }
        return polaPackColors.first(where: { $0.name == packName })?.color ?? .white
    }

    var body: some View {
        ZStack {
            frontFace
                .opacity(showingBack ? 0 : 1)

            if showingBack {
                backFace.scaleEffect(x: -1)
            }
        }
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    guard revealProgress >= 1.0 else { return }
                    flipCard()
                }
                .exclusively(before: TapGesture(count: 1).onEnded {
                    onSingleTap?()
                })
        )
        .onChange(of: developmentProgress) { _, newValue in
            guard !animatedExternally else { return }
            if newValue >= 1.0 {
                localReveal = 1.0
            } else if newValue > localReveal {
                localReveal = newValue
            }
        }
        .onAppear {
            guard !animatedExternally, localReveal < 1.0 else { return }
            let remaining = 30.0 * (1.0 - localReveal)
            guard remaining > 0 else {
                localReveal = 1.0
                onDeveloped?()
                return
            }
            withAnimation(.linear(duration: remaining)) {
                localReveal = 1.0
            }
            Task {
                try? await Task.sleep(for: .seconds(remaining))
                onDeveloped?()
            }
        }
    }

    // MARK: - Watermark

    private var showWatermark: Bool {
        PremiumManager.shared.shouldWatermarkExports
    }

    private var dateStamp: String? {
        guard dateStampEnabled, PremiumManager.shared.isPremium, let timestamp else { return nil }
        return polaroidDateStampText(timestamp)
    }

    private func dateStampOverlay(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 9 * fontScale, weight: .semibold, design: .monospaced))
            .foregroundStyle(polaroidDateStampColor)
            .shadow(color: polaroidDateStampColor.opacity(0.8), radius: 2 * fontScale)
            .padding(5 * fontScale)
    }

    private var watermarkOverlay: some View {
        HStack(spacing: 3 * fontScale) {
            if let icon = UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8 * fontScale, height: 8 * fontScale)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * fontScale * 0.22))
            }
            Text(verbatim: "Poly")
                .font(.system(size: 8 * fontScale, weight: .semibold).width(.expanded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .shadow(color: .black.opacity(0.6), radius: 2 * fontScale, x: 0, y: 0.5 * fontScale)
        .padding(5 * fontScale)
    }

    // MARK: - Front face

    private var frontFace: some View {
        VStack(spacing: 0) {
            Color.clear
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                    }
                }
                .overlay {
                    if let videoURL, playVideo {
                        LoopingVideoView(url: videoURL, isPlaying: isVideoPlaying, isLooping: isVideoLooping)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if let dateStamp {
                        dateStampOverlay(dateStamp)
                    }
                }
                .overlay {
                    Color.black
                        .opacity(max(0, 1.0 - revealProgress))
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if videoURL != nil && !playVideo {
                        Image(systemName: isTimelapse ? "timer" : "video.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showWatermark && revealProgress >= 1.0 {
                        watermarkOverlay
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

            Text(caption.isEmpty ? " " : caption)
                .font(currentFont.swiftUIFont(size: 13 * fontScale, weight: currentWeight))
                .foregroundStyle(.black.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(height: 32 * fontScale, alignment: .center)
        }
        .background(borderColor)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
    }

    // MARK: - Back face

    private var backFace: some View {
        VStack(spacing: 0) {
            Group {
                if showMap, let coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )), interactionModes: []) {
                        Marker("", coordinate: coordinate)
                    }
                } else {
                    backDecoration
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack(spacing: 2) {
                if let ts = timestamp {
                    Text(ts, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 11 * fontScale, weight: .medium, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.5))
                }
                if let fn = filterName {
                    Text(fn)
                        .font(.system(size: 10 * fontScale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.4))
                }
            }
            .frame(height: 32 * fontScale, alignment: .center)
        }
        .background(borderColor)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
    }

    private var backDecoration: some View {
        ZStack {
            Color(white: 0.96)
            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.07))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 8)
            if !backText.isEmpty {
                Text(backText)
                    .font(currentFont.swiftUIFont(size: 14 * fontScale, weight: currentWeight))
                    .foregroundStyle(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Flip

    private func flipCard() {
        Task { @MainActor in
            let targetAngle: Double = showingBack ? 0 : 180
            withAnimation(.easeIn(duration: 0.18)) { flipAngle = 90 }
            try? await Task.sleep(for: .seconds(0.18))
            showingBack.toggle()
            withAnimation(.easeOut(duration: 0.18)) { flipAngle = targetAngle }
        }
    }
}

// MARK: - Looping video view

struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var isPlaying: Bool = true
    var isLooping: Bool = true

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.configure(url: url, isLooping: isLooping)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.setLooping(isLooping)
        isPlaying ? uiView.play() : uiView.pause()
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.pause()
    }

    final class PlayerView: UIView {
        private var player: AVPlayer?
        private var token: NSObjectProtocol?
        private var loops: Bool = true

        // Behave like Image.resizable() — no intrinsic size, stretches to fill container
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            setContentHuggingPriority(.defaultLow, for: .horizontal)
            setContentHuggingPriority(.defaultLow, for: .vertical)
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
        required init?(coder: NSCoder) { fatalError() }

        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }

        func configure(url: URL, isLooping: Bool = true) {
            loops = isLooping
            let p = AVPlayer(url: url)
            p.actionAtItemEnd = .none
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = p
            token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem,
                queue: .main
            ) { [weak self, weak p] _ in
                if self?.loops == true {
                    p?.seek(to: .zero)
                    p?.play()
                } else {
                    p?.pause()
                    p?.seek(to: .zero)
                }
            }
            player = p
            p.play()
        }

        func play() { player?.play() }
        func pause() { player?.pause() }
        func setLooping(_ loops: Bool) { self.loops = loops }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            player?.pause()
        }
    }
}

// Returns shareable items: composited polaroid video for video entries, rendered frame for photos.
func prepareShareItems(for entries: [PolaroidEntry], videoDirectory: URL) async -> [Any] {
    var items: [Any] = []
    for entry in entries {
        if let filename = entry.videoFilename {
            let srcURL = videoDirectory.appendingPathComponent(filename)
            if let composited = await compositePolaroidVideo(entry, sourceURL: srcURL) {
                items.append(composited)
            } else {
                items.append(srcURL)
            }
        } else {
            let frame = await MainActor.run { renderPolaroidFrame(entry) }
            items.append(frame)
        }
    }
    return items
}

// Composites the polaroid frame (border + caption) over a video and exports to a temp .mp4.
func compositePolaroidVideo(_ entry: PolaroidEntry, sourceURL: URL) async -> URL? {
    let sourceURL = sourceURL

    let asset = AVURLAsset(url: sourceURL)
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
    let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
    let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
    let duration = (try? await asset.load(.duration)) ?? .zero

    // Display size after rotation
    let tSize = naturalSize.applying(preferredTransform)
    let displaySize = CGSize(width: abs(tSize.width), height: abs(tSize.height))
    guard displaySize.width > 0, displaySize.height > 0 else { return nil }

    // Polaroid dimensions at 3x; height rounded to an even pixel count for the H.264 encoder
    let s: CGFloat = 3
    let frameW: CGFloat = 270 * s
    let frameH: CGFloat = (frameW / entry.frameFormat.frameAspect / 2).rounded() * 2
    let pad: CGFloat = 8 * s
    let captionH: CGFloat = 26 * 1.7 * s
    let imgW = frameW - 2 * pad, imgH = frameH - captionH - pad
    let renderSize = CGSize(width: frameW, height: frameH)

    // Scale-to-fill the image area
    let fillScale = max(imgW / displaySize.width, imgH / displaySize.height)
    let scaledW = displaySize.width * fillScale, scaledH = displaySize.height * fillScale

    // Position in image area using BL (bottom-left) coordinates used by AVFoundation
    let tx = pad - (scaledW - imgW) / 2
    let ty = captionH - 64 - (scaledH - imgH) / 2
    let finalTransform = preferredTransform
        .concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
        .concatenating(CGAffineTransform(translationX: tx, y: ty))

    // Composition
    let composition = AVMutableComposition()
    guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
    try? compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)

    if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
       let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try? compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
    }

    // CALayer overlay: polaroid border + caption with transparent video window
    // isGeometryFlipped = true makes sublayers use UIKit (top-left, y-down) coordinates
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.isGeometryFlipped = true

    let videoLayer = CALayer()
    videoLayer.frame = CGRect(origin: .zero, size: renderSize)

    // In UIKit coords: top-padding | image area | caption (bottom)
    let imageHole = CGRect(x: pad, y: pad, width: imgW, height: imgH)
    let captionRect = CGRect(x: 0, y: pad + imgH, width: frameW, height: captionH)
    let packColor: UIColor = {
        if let hex = entry.packColorHex, let c = Color(hex: hex) { return UIColor(c) }
        return UIColor(polaPackColors.first(where: { $0.name == entry.packName })?.color ?? .white)
    }()
    let storedFontName = UserDefaults.standard.string(forKey: "polaroidFont") ?? PolaroidFont.handwriting.rawValue
    let storedWeightName = UserDefaults.standard.string(forKey: "polaroidFontWeight") ?? PolaroidFontWeight.regular.rawValue
    let captionFont = (PolaroidFont(rawValue: storedFontName) ?? .handwriting)
        .uiFont(size: 13 * 1.7 * 3, weight: PolaroidFontWeight(rawValue: storedWeightName) ?? .regular)
    let dateStampEnabled = UserDefaults.standard.bool(forKey: "dateStampEnabled") && PremiumManager.shared.isPremium
    let overlayImage = makePolaroidOverlayImage(
        size: renderSize, imageHole: imageHole, captionRect: captionRect,
        caption: entry.caption, packColor: packColor, captionFont: captionFont,
        dateStamp: dateStampEnabled ? polaroidDateStampText(entry.timestamp) : nil
    )

    let overlayLayer = CALayer()
    overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
    overlayLayer.contents = overlayImage.cgImage
    overlayLayer.contentsScale = 1

    parentLayer.addSublayer(videoLayer)
    parentLayer.addSublayer(overlayLayer)

    let animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

    let videoComposition: AVVideoComposition
    if #available(iOS 26, *) {
        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compTrack)
        layerConfig.setTransform(finalTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        let instructionConfig = AVVideoCompositionInstruction.Configuration(
            backgroundColor: nil,
            enablePostProcessing: true,
            layerInstructions: [layerInstruction],
            requiredSourceSampleDataTrackIDs: [],
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        let vcConfig = AVVideoComposition.Configuration(
            animationTool: animationTool,
            colorPrimaries: nil, colorTransferFunction: nil, colorYCbCrMatrix: nil,
            customVideoCompositorClass: nil,
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [instruction],
            outputBufferDescription: nil,
            renderScale: 1.0,
            renderSize: renderSize,
            sourceSampleDataTrackIDs: [],
            sourceTrackIDForFrameTiming: kCMPersistentTrackID_Invalid,
            spatialVideoConfigurations: []
        )
        videoComposition = AVVideoComposition(configuration: vcConfig)
    } else {
        let mutableComposition = AVMutableVideoComposition()
        mutableComposition.renderSize = renderSize
        mutableComposition.frameDuration = CMTime(value: 1, timescale: 30)
        mutableComposition.animationTool = animationTool

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        mutableComposition.instructions = [instruction]
        videoComposition = mutableComposition
    }

    // Export
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
    export.videoComposition = videoComposition
    guard await exportPolaroidVideo(export, to: outputURL) else { return nil }
    return outputURL
}

private func exportPolaroidVideo(_ export: AVAssetExportSession, to outputURL: URL) async -> Bool {
    do {
        try await export.export(to: outputURL, as: .mp4)
        return true
    } catch {
        return false
    }
}

private func drawPolaroidWatermark(in ctx: CGContext, imageRect: CGRect, scale: CGFloat) {
    guard PremiumManager.shared.shouldWatermarkExports else { return }
    let margin: CGFloat = 5 * scale
    let fontSize: CGFloat = 8 * scale
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold, width: .expanded)
    let text = "Poly" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor.white.withAlphaComponent(0.8)
    ]
    let textSize = text.size(withAttributes: attrs)
    let iconSize: CGFloat = textSize.height
    let spacing: CGFloat = 3 * scale
    let originX = imageRect.minX + margin
    let originY = imageRect.maxY - textSize.height - margin

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: 0.5 * scale),
        blur: 2 * scale,
        color: UIColor.black.withAlphaComponent(0.6).cgColor
    )

    // Draw app icon with rounded corners to the left of the text
    if let icon = UIImage(named: "AppIcon") {
        let iconRect = CGRect(x: originX, y: originY, width: iconSize, height: iconSize)
        ctx.saveGState()
        let cornerRadius = iconSize * 0.22
        let path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        icon.draw(in: iconRect)
        ctx.restoreGState()
    }

    let textRect = CGRect(
        x: originX + iconSize + spacing,
        y: originY,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attrs)
    ctx.restoreGState()
}

private func drawPolaroidDateStamp(_ text: String, in ctx: CGContext, imageRect: CGRect, scale: CGFloat) {
    let color = UIColor(polaroidDateStampColor)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedSystemFont(ofSize: 9 * scale, weight: .semibold),
        .foregroundColor: color
    ]
    let str = text as NSString
    let size = str.size(withAttributes: attrs)
    let margin = 5 * scale
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 2 * scale, color: color.withAlphaComponent(0.8).cgColor)
    str.draw(at: CGPoint(x: imageRect.maxX - size.width - margin, y: imageRect.maxY - size.height - margin), withAttributes: attrs)
    ctx.restoreGState()
}

private func makePolaroidOverlayImage(size: CGSize, imageHole: CGRect, captionRect: CGRect, caption: String, packColor: UIColor, captionFont: UIFont, dateStamp: String?) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { ctx in
        let cgCtx = ctx.cgContext
        packColor.setFill()
        cgCtx.fill(CGRect(origin: .zero, size: size))
        cgCtx.clear(imageHole)
        drawPolaroidWatermark(in: cgCtx, imageRect: imageHole, scale: 3)
        if let dateStamp {
            drawPolaroidDateStamp(dateStamp, in: cgCtx, imageRect: imageHole, scale: 3)
        }
        guard !caption.isEmpty else { return }
        let font = captionFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black.withAlphaComponent(0.65)
        ]
        let str = caption as NSString
        let textSize = str.boundingRect(with: captionRect.size, options: .usesLineFragmentOrigin, attributes: attrs, context: nil).size
        let textRect = CGRect(
            x: captionRect.minX + (captionRect.width - min(textSize.width, captionRect.width)) / 2,
            y: captionRect.minY + (captionRect.height - textSize.height) / 2,
            width: min(textSize.width, captionRect.width),
            height: textSize.height
        )
        str.draw(in: textRect, withAttributes: attrs)
    }
}

// Renders the full polaroid frame (border + caption) as a UIImage for sharing/saving.
@MainActor
func renderPolaroidFrame(_ entry: PolaroidEntry) -> UIImage {
    let cell = PolaroidPhotoCell(
        image: entry.image,
        developmentProgress: 1.0,
        caption: entry.caption,
        backText: entry.backText,
        showMap: entry.showMap,
        coordinate: entry.coordinate,
        timestamp: entry.timestamp,
        filterName: entry.filterName,
        packName: entry.packName,
        packColorHex: entry.packColorHex,
        fontScale: 1.7
    )
    .frame(width: 270, height: (270 / entry.frameFormat.frameAspect).rounded())

    let renderer = ImageRenderer(content: cell)
    renderer.scale = 3.0
    return renderer.uiImage ?? entry.image ?? UIImage()
}

// MARK: - Date stamp

let polaroidDateStampColor = Color(red: 1.0, green: 0.58, blue: 0.2)

// Mimics the orange LED imprint of 90s compact film cameras, e.g. "'26 9 24".
func polaroidDateStampText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "''yy M d"
    return formatter.string(from: date)
}

// MARK: - Color hex helpers

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            .sRGB,
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

#Preview {
    HStack {
        PolaroidPhotoCell(caption: "Summer vibes", filterName: "FLÄRN")
        PolaroidPhotoCell()
        PolaroidPhotoCell(developmentProgress: 0.0, timestamp: Date())
    }
    .padding()
    .background(.gray.opacity(0.2))
}
