import MapKit
import SwiftUI

struct PolaroidPhotoCell: View {
    var image: UIImage? = nil
    // When animatedExternally=true, developmentProgress is driven by the caller (ejection overlay).
    // When false, the cell animates itself based on elapsed time since timestamp.
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

        // Compute how far development has already progressed based on elapsed time.
        // For externally-animated cells (ejection overlay), localReveal is irrelevant.
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

    // Externally-controlled cells use the passed-in developmentProgress directly;
    // self-animating cells use localReveal.
    private var revealProgress: Double {
        animatedExternally ? developmentProgress : localReveal
    }

    private var borderColor: Color {
        guard let packName else { return .white }
        return polaPackColors.first(where: { $0.name == packName })?.color ?? .white
    }

    var body: some View {
        ZStack {
            // Always keep frontFace in the ZStack so layout size never changes.
            frontFace
                .opacity(showingBack ? 0 : 1)

            // Only instantiate backFace (with its Map) when actually visible.
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
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .overlay {
                            if revealProgress < 1.0 {
                                Color.black.opacity(1.0 - revealProgress)
                            }
                        }
                } else {
                    Color.black
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

#Preview {
    HStack {
        PolaroidPhotoCell(caption: "Summer vibes", filterName: "FLÄRN")
        PolaroidPhotoCell()
        PolaroidPhotoCell(developmentProgress: 0.0, timestamp: Date())
    }
    .padding()
    .background(.gray.opacity(0.2))
}
