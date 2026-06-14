import AVFoundation
import MapKit
import SwiftUI

struct PolaroidPhotoCell: View {
    var image: UIImage? = nil
    var videoURL: URL? = nil
    var isTimelapse: Bool = false
    var playVideo: Bool = true
    var developmentProgress: Double = 1.0
    var animatedExternally: Bool = false
    var caption: String = ""
    var backText: String = ""
    var showMap: Bool = true
    var coordinate: CLLocationCoordinate2D? = nil
    var timestamp: Date? = nil
    var filterName: String? = nil
    var packName: String? = nil
    var fontScale: CGFloat = 1.0
    var onDeveloped: (() -> Void)? = nil
    var onSingleTap: (() -> Void)? = nil

    @State private var localReveal: Double
    @State private var flipAngle: Double = 0
    @State private var showingBack = false

    init(
        image: UIImage? = nil,
        videoURL: URL? = nil,
        isTimelapse: Bool = false,
        playVideo: Bool = true,
        developmentProgress: Double = 1.0,
        animatedExternally: Bool = false,
        caption: String = "",
        backText: String = "",
        showMap: Bool = true,
        coordinate: CLLocationCoordinate2D? = nil,
        timestamp: Date? = nil,
        filterName: String? = nil,
        packName: String? = nil,
        fontScale: CGFloat = 1.0,
        onDeveloped: (() -> Void)? = nil,
        onSingleTap: (() -> Void)? = nil
    ) {
        self.image = image
        self.videoURL = videoURL
        self.isTimelapse = isTimelapse
        self.playVideo = playVideo
        self.developmentProgress = developmentProgress
        self.animatedExternally = animatedExternally
        self.caption = caption
        self.backText = backText
        self.showMap = showMap
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.filterName = filterName
        self.packName = packName
        self.fontScale = fontScale
        self.onDeveloped = onDeveloped
        self.onSingleTap = onSingleTap

        if developmentProgress >= 1.0 || animatedExternally {
            self._localReveal = State(initialValue: 1.0)
        } else if let ts = timestamp {
            let elapsed = Date().timeIntervalSince(ts)
            self._localReveal = State(initialValue: min(1.0, elapsed / 30.0))
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
        .onAppear {
            guard !animatedExternally, localReveal < 1.0, let ts = timestamp else { return }
            let elapsed = Date().timeIntervalSince(ts)
            let remaining = max(0, 30.0 - elapsed)
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

    // MARK: - Front face

    private var frontFace: some View {
        VStack(spacing: 0) {
            Color.clear
                .overlay {
                    Group {
                        if let videoURL, playVideo {
                            LoopingVideoView(url: videoURL)
                                .overlay {
                                    if revealProgress < 1.0 {
                                        Color.black.opacity(1.0 - revealProgress)
                                    }
                                }
                        } else if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .overlay {
                                    if revealProgress < 1.0 {
                                        Color.black.opacity(1.0 - revealProgress)
                                    }
                                }
                        } else {
                            Color.black
                        }
                    }
                }
                .clipped()
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
                .padding(.horizontal, 8)
                .padding(.top, 8)

            Text(caption.isEmpty ? " " : caption)
                .font(.custom("Bradley Hand", size: 13 * fontScale))
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
                    .font(.custom("Bradley Hand", size: 14 * fontScale))
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

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.pause()
    }

    final class PlayerView: UIView {
        private var player: AVPlayer?
        private var token: NSObjectProtocol?

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

        func configure(url: URL) {
            let p = AVPlayer(url: url)
            p.actionAtItemEnd = .none
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = p
            token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem,
                queue: .main
            ) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
            player = p
            p.play()
        }

        func pause() {
            player?.pause()
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            player?.pause()
        }
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
