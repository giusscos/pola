# Build a 3D Interactive Model Card System in SwiftUI (SceneKit + USDZ)

Build a full 3D interactive card/badge system in SwiftUI using SceneKit and USDZ assets. The system has four layers: a reusable 3D scene renderer, a grid cell, a full-screen detail overlay with entry/exit animations, and shimmer placeholders for loading states.

---

## Architecture overview

```
ModelSceneView          — UIViewRepresentable wrapping SCNView, renders .usdz assets
ModelSceneHandle        — Reference object bridging SwiftUI state to SceneKit animations
ModelGridItem           — Grid cell: shows 3D view or flat image, locked/unlocked states
ModelDetailOverlay      — Full-screen detail that zooms the tapped cell to fill the screen
ModelShimmerItem        — Skeleton placeholder shown while data loads
```

---

## 1. `ModelSceneView` — `UIViewRepresentable`

- Subclass `SCNView` as `ModelSCNView` and add an `onLayout: (() -> Void)?` property; call it from `layoutSubviews()` so you know the exact moment SwiftUI has set the final frame (reliable even inside `LazyVGrid`).
- In `makeUIView`:
  - Load the USDZ from a named `NSDataAsset`, write it to a temp file, open with `SCNScene(url:)`.
  - Wrap all scene child nodes in a single `modelContainer: SCNNode` so you have one handle for rotation/scale.
  - Compute the model's bounding box; store `normDim` (normalize by Y height) and `boundingBoxCenter`.
  - Add an **area (rectangle) light** at position `(1, 0.5, 4)` with `areaExtents = simd_float3(5, 13, 1)`, intensity 900, tilted to cast a diagonal highlight across metallic surfaces.
  - Add a soft **ambient light** (white, intensity 250) so metallic faces don't go fully black.
  - Place a `SCNCamera` node at `(0, 0, 2.5)` and assign it as `pointOfView`.
  - Set `autoenablesDefaultLighting = false`, `allowsCameraControl = false`, `antialiasingMode = .multisampling4X`, `backgroundColor = .clear`.
  - Wire `sceneView.onLayout` to call `applyScale(to:coordinator:)`.
  - If `gestureEnabled`, attach a `UIPanGestureRecognizer` to the coordinator's `handlePan`.
  - If `spinOnAppear`, fire `coordinator.triggerEntrySpin()` after a 50 ms `DispatchQueue.main.asyncAfter`.
- `applyScale` — called from `layoutSubviews` and `updateUIView`: skip if bounds are unchanged and padding hasn't changed; center the model node by setting `position = -boundingBoxCenter`; reset scale to `(1,1,1)` (the camera distance handles perceived size).
- `Coordinator`:
  - `triggerEntrySpin()` — `CABasicAnimation` on `eulerAngles.y` from current → current + 2π, duration 0.8 s, `easeInEaseOut`, `isRemovedOnCompletion = true`.
  - `handlePan(_:)` — on `.changed`: freeze `eulerAngles.y` to `presentation.eulerAngles.y`, accumulate `delta.x * 0.01` radians, reset translation. On `.ended/.cancelled`: snap `eulerAngles.y` to the nearest multiple of π using a `CASpringAnimation` (damping 4, stiffness 40, mass 1), so the model always rests at front or back.

### Full implementation

```swift
import SceneKit
import SwiftUI

private class ModelSCNView: SCNView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct ModelSceneView: UIViewRepresentable {
    let assetName: String
    var gestureEnabled: Bool = true
    var spinOnAppear: Bool = false
    var handle: ModelSceneHandle? = nil
    var padding: CGFloat = 16

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = ModelSCNView()
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.antialiasingMode = .multisampling4X

        if let asset = NSDataAsset(name: assetName) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(assetName).usdz")
            try? asset.data.write(to: tempURL)

            if let scene = try? SCNScene(url: tempURL) {
                let modelContainer = SCNNode()
                for child in scene.rootNode.childNodes {
                    modelContainer.addChildNode(child)
                }

                let (minB, maxB) = modelContainer.boundingBox
                let size = SCNVector3(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
                context.coordinator.normDim = size.y > 0 ? size.y : size.x
                context.coordinator.boundingBoxCenter = SCNVector3(
                    (minB.x + maxB.x) / 2,
                    (minB.y + maxB.y) / 2,
                    (minB.z + maxB.z) / 2
                )

                scene.rootNode.addChildNode(modelContainer)

                let rectLight = SCNNode()
                rectLight.light = SCNLight()
                rectLight.light?.type = .area
                rectLight.light?.areaType = .rectangle
                rectLight.light?.areaExtents = simd_float3(5, 13, 1)
                rectLight.light?.intensity = 900
                rectLight.light?.castsShadow = false
                rectLight.position = SCNVector3(1, 0.5, 4)
                rectLight.eulerAngles = SCNVector3(0, 0, -Float(atan2(6.0, 11.0)))
                scene.rootNode.addChildNode(rectLight)

                let ambientLight = SCNNode()
                ambientLight.light = SCNLight()
                ambientLight.light?.type = .ambient
                ambientLight.light?.color = UIColor.white
                ambientLight.light?.intensity = 250
                scene.rootNode.addChildNode(ambientLight)

                let cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                cameraNode.position = SCNVector3(0, 0, 2.5)
                scene.rootNode.addChildNode(cameraNode)
                sceneView.pointOfView = cameraNode

                sceneView.scene = scene
                context.coordinator.modelNode = modelContainer
                handle?.coordinator = context.coordinator
                handle?.sceneView = sceneView
            }
        }

        sceneView.onLayout = { [weak sceneView] in
            guard let sceneView else { return }
            self.applyScale(to: sceneView, coordinator: context.coordinator)
        }

        if gestureEnabled {
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            sceneView.addGestureRecognizer(pan)
        }

        if spinOnAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                context.coordinator.triggerEntrySpin()
            }
        }

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard padding != context.coordinator.lastPadding else { return }
        applyScale(to: uiView, coordinator: context.coordinator)
    }

    private func applyScale(to sceneView: SCNView, coordinator: Coordinator) {
        let bounds = sceneView.bounds
        guard bounds.height > 0, coordinator.normDim > 0,
              let modelNode = coordinator.modelNode else { return }
        guard bounds != coordinator.lastBounds || padding != coordinator.lastPadding else { return }
        coordinator.lastBounds = bounds
        coordinator.lastPadding = padding

        let center = coordinator.boundingBoxCenter
        modelNode.scale = SCNVector3(1, 1, 1)
        modelNode.position = SCNVector3(-center.x, -center.y, -center.z)
    }

    class Coordinator: NSObject {
        var modelNode: SCNNode?
        var normDim: Float = 0
        var boundingBoxCenter: SCNVector3 = SCNVector3Zero
        var lastBounds: CGRect = .zero
        var lastPadding: CGFloat = -1

        func triggerEntrySpin() {
            guard let node = modelNode else { return }
            let spin = CABasicAnimation(keyPath: "eulerAngles.y")
            spin.fromValue = node.eulerAngles.y
            spin.toValue = node.eulerAngles.y + Float.pi * 2
            spin.duration = 0.8
            spin.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            spin.isRemovedOnCompletion = true
            node.addAnimation(spin, forKey: "entrySpin")
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let node = modelNode else { return }
            switch gesture.state {
            case .changed:
                node.removeAllActions()
                node.removeAllAnimations()
                node.eulerAngles = node.presentation.eulerAngles
                let delta = gesture.translation(in: gesture.view)
                node.eulerAngles.y += Float(delta.x) * 0.01
                gesture.setTranslation(.zero, in: gesture.view)
            case .ended, .cancelled:
                let currentAngle = node.presentation.eulerAngles.y
                let target = (currentAngle / .pi).rounded() * Float.pi
                let spring = CASpringAnimation(keyPath: "eulerAngles.y")
                spring.fromValue = currentAngle
                spring.toValue = target
                spring.damping = 4
                spring.stiffness = 40
                spring.mass = 1
                spring.initialVelocity = 0
                spring.duration = spring.settlingDuration
                node.addAnimation(spring, forKey: "springBack")
                node.eulerAngles.y = target
            default:
                break
            }
        }
    }
}
```

---

## 2. `ModelSceneHandle` — Reference bridge

```swift
final class ModelSceneHandle: NSObject {
    weak var coordinator: ModelSceneView.Coordinator?
    var sceneView: SCNView?

    func triggerSpin() {
        coordinator?.triggerEntrySpin()
    }

    @MainActor
    func snapshotFacingFront() -> UIImage? {
        guard let sceneView else { return nil }
        if let node = coordinator?.modelNode {
            node.removeAllAnimations()
            node.eulerAngles.y = 0
        }
        sceneView.backgroundColor = .black
        let image = sceneView.snapshot()
        sceneView.backgroundColor = .clear
        return image
    }

    func triggerFullFlip() {
        guard let node = coordinator?.modelNode else { return }
        node.removeAllAnimations()
        let current = node.presentation.eulerAngles.y
        node.eulerAngles.y = current
        let flip = CABasicAnimation(keyPath: "eulerAngles.y")
        flip.fromValue = current
        flip.toValue = current + Float.pi * 2
        flip.duration = 0.6
        flip.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        flip.isRemovedOnCompletion = true
        node.addAnimation(flip, forKey: "fullFlip")
    }

    @discardableResult
    func flipToFrontIfNeeded() -> TimeInterval {
        guard let node = coordinator?.modelNode else { return 0 }
        node.removeAllAnimations()

        let current = node.presentation.eulerAngles.y
        node.eulerAngles.y = current

        let n = (current / Float.pi).rounded()
        let nInt = Int(n)
        guard abs(nInt) % 2 == 1 else { return 0 }

        let sign: Float = n > 0 ? -1 : 1
        let target = (n + sign) * Float.pi
        let duration: TimeInterval = 0.4

        let flip = CABasicAnimation(keyPath: "eulerAngles.y")
        flip.fromValue = current
        flip.toValue = target
        flip.duration = duration
        flip.timingFunction = CAMediaTimingFunction(name: .linear)

        node.addAnimation(flip, forKey: "flipToFront")
        node.eulerAngles.y = target

        return duration
    }
}
```

---

## 3. `ModelGridItem` — Grid cell view

```swift
struct ModelGridItem: View {
    let assetName: String?       // nil = use flat image fallback
    let imageName: String
    let isUnlocked: Bool
    let progress: CGFloat        // 0.0 – 1.0
    let progressLabel: String
    let displayName: String
    let index: Int
    var isHidden: Bool = false
    var onTap: ((CGRect) -> Void)? = nil

    @State private var scale: CGFloat
    @State private var brightness: Double = 0
    @State private var barFraction: CGFloat = 0

    init(
        assetName: String?,
        imageName: String,
        isUnlocked: Bool,
        progress: CGFloat,
        progressLabel: String,
        displayName: String,
        index: Int,
        isHidden: Bool = false,
        onTap: ((CGRect) -> Void)? = nil
    ) {
        self.assetName = assetName
        self.imageName = imageName
        self.isUnlocked = isUnlocked
        self.progress = progress
        self.progressLabel = progressLabel
        self.displayName = displayName
        self.index = index
        self.isHidden = isHidden
        self.onTap = onTap
        self._scale = State(initialValue: isUnlocked ? 0.72 : 1.0)
    }

    var body: some View {
        VStack(spacing: 2) {
            itemVisual
                .overlay {
                    if let onTap {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { onTap(geo.frame(in: .global)) }
                        }
                    }
                }

            if isUnlocked {
                Text(displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            } else {
                lockedOverlay
            }

            Spacer()
        }
        .scaleEffect(scale)
        .brightness(brightness)
        .opacity(isHidden ? 0 : 1)
        .onAppear {
            guard isUnlocked else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.04)) {
                    barFraction = progress
                }
                return
            }
            let delay = Double(index) * 0.055
            withAnimation(.spring(response: 0.42, dampingFraction: 0.52).delay(delay)) { scale = 1.0 }
            withAnimation(.easeIn(duration: 0.12).delay(delay)) { brightness = 0.38 }
            withAnimation(.easeOut(duration: 0.38).delay(delay + 0.12)) { brightness = 0 }
        }
    }

    @ViewBuilder
    private var itemVisual: some View {
        if let assetName {
            ModelSceneView(assetName: assetName, gestureEnabled: false, padding: 10)
                .aspectRatio(1, contentMode: .fit)
                .saturation(isUnlocked ? 1.0 : 0)
                .opacity(isUnlocked ? 1.0 : 0.35)
        } else {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .saturation(isUnlocked ? 1.0 : 0)
                .opacity(isUnlocked ? 1.0 : 0.35)
        }
    }

    @ViewBuilder
    private var lockedOverlay: some View {
        if progress > 0 {
            VStack(spacing: 4) {
                Text(progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 6)
                    Capsule().fill(.white.opacity(0.8))
                        .scaleEffect(x: barFraction, anchor: .leading)
                        .frame(height: 6)
                }
            }
            .padding(.horizontal, 4)
        } else {
            VStack(spacing: 2) {
                Image(systemName: "lock.fill")
                Text("Locked")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
        }
    }
}
```

---

## 4. `ModelDetailOverlay` — Full-screen zoom-in overlay

The overlay lives in a `.overlay` modifier on the parent (not a sheet), so the 3D model can visually travel from its grid cell to the centre of the screen.

```swift
private struct NaturalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct ModelDetailOverlay: View {
    var assetName: String?
    var imageName: String
    var displayName: String
    var description: String
    var sourceFrame: CGRect
    var isUnlocked: Bool
    @Binding var shouldDismiss: Bool
    var onDismiss: () -> Void

    @State private var naturalFrame: CGRect = .zero
    @State private var animating = false
    @State private var contentVisible = false
    @State private var isDismissing = false
    @State private var sceneHandle = ModelSceneHandle()
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var isGeneratingShare = false

    private var itemScale: CGFloat {
        guard naturalFrame.width > 0 else { return 1 }
        return animating ? 1 : (sourceFrame.width / naturalFrame.width)
    }

    private var itemOffset: CGSize {
        guard naturalFrame != .zero else { return .zero }
        return animating ? .zero : CGSize(
            width: sourceFrame.midX - naturalFrame.midX,
            height: sourceFrame.midY - naturalFrame.midY
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            itemView
                .overlay {
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            guard naturalFrame == .zero else { return }
                            let frame = geo.frame(in: .global)
                            guard frame != .zero else { return }
                            naturalFrame = frame
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                animating = true
                            }
                            withAnimation(.easeIn(duration: 0.25).delay(0.25)) {
                                contentVisible = true
                            }
                            guard isUnlocked else { return }
                            sceneHandle.triggerFullFlip()
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: NaturalFrameKey.self,
                            value: geo.frame(in: .global)
                        )
                    }
                )
                .opacity(naturalFrame == .zero ? 0 : 1)
                .scaleEffect(itemScale)
                .offset(itemOffset)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: animating)
                .task { @MainActor in
                    guard isUnlocked, shareImage == nil else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    _ = sceneHandle.flipToFrontIfNeeded()
                    shareImage = makeShareImage()
                }

            VStack(spacing: 16) {
                Text(displayName)
                    .font(.largeTitle.bold())
                Text(description)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            .padding()
            .opacity(contentVisible ? 1 : 0)
            .animation(.easeIn(duration: 0.2), value: contentVisible)

            Spacer()

            if isUnlocked {
                Button {
                    Task { @MainActor in
                        guard !isGeneratingShare else { return }
                        isGeneratingShare = true
                        _ = sceneHandle.flipToFrontIfNeeded()
                        try? await Task.sleep(for: .milliseconds(50))
                        shareImage = makeShareImage()
                        try? await Task.sleep(for: .milliseconds(50))
                        showShareSheet = shareImage != nil
                        isGeneratingShare = false
                    }
                } label: {
                    Group {
                        if isGeneratingShare {
                            HStack(spacing: 8) {
                                ProgressView().progressViewStyle(.circular).tint(.black)
                                Text("Preparing…")
                            }
                        } else {
                            HStack(alignment: .lastTextBaseline) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                        }
                    }
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.white)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingShare || shareImage == nil)
                .opacity((isGeneratingShare || shareImage == nil) ? 0.6 : 1)
                .sheet(isPresented: $showShareSheet) {
                    if let image = shareImage {
                        ShareSheet(items: [image])
                            .background(Color(.systemBackground))
                    }
                }
                .padding([.horizontal, .bottom])
                .opacity(contentVisible ? 1 : 0)
                .animation(.easeIn(duration: 0.2), value: contentVisible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(NaturalFrameKey.self) { frame in
            guard frame != .zero, !isDismissing, naturalFrame != .zero else { return }
            naturalFrame = frame
        }
        .background(
            Color(.systemBackground)
                .opacity(animating ? 1 : 0)
                .animation(.easeIn(duration: 0.25), value: animating)
        )
        .ignoresSafeArea()
        .onChange(of: shouldDismiss) { _, newValue in
            if newValue { Task { await triggerDismiss() } }
        }
    }

    @ViewBuilder
    private var itemView: some View {
        if let assetName {
            ModelSceneView(
                assetName: assetName,
                gestureEnabled: isUnlocked,
                spinOnAppear: false,
                handle: sceneHandle,
                padding: 30
            )
            .frame(width: 320, height: 320)
            .saturation(isUnlocked ? 1.0 : 0)
            .opacity(isUnlocked ? 1.0 : 0.5)
        } else {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 256, height: 256)
                .saturation(isUnlocked ? 1.0 : 0)
                .opacity(isUnlocked ? 1.0 : 0.5)
        }
    }

    private func makeShareImage() -> UIImage? {
        var snapshot: UIImage?
        if assetName != nil { snapshot = sceneHandle.snapshotFacingFront() }
        let card = ShareCard(snapshot: snapshot, imageName: imageName, displayName: displayName, description: description)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = .init(width: 390, height: 600)
        return renderer.uiImage
    }

    private func triggerDismiss() async {
        isDismissing = true
        withAnimation(.easeOut(duration: 0.25)) { contentVisible = false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { animating = false }
        if isUnlocked { sceneHandle.flipToFrontIfNeeded() }
        try? await Task.sleep(for: .seconds(0.6))
        onDismiss()
    }
}
```

---

## 5. Share card + sheet

```swift
private struct ShareCard: View {
    var snapshot: UIImage?
    var imageName: String
    var displayName: String
    var description: String

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Group {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFit()
                } else {
                    Image(imageName).resizable().scaledToFit()
                }
            }
            .frame(width: 260, height: 260)

            VStack(spacing: 12) {
                Text(displayName).font(.title2.bold()).foregroundStyle(.white)
                Text(description).font(.callout).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 36)

            Spacer()

            Text("YourApp")
                .font(.title2.bold())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 28)
        }
        .frame(width: 390, height: 600)
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

---

## 6. Shimmer placeholders

```swift
struct ModelShimmerItem: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.15))

            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.05), .white.opacity(0.25), .white.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask(
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.1), .white.opacity(0.5), .white.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .offset(x: phase * 240)
                )
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: phase)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { phase = 1.2 }
    }
}

struct ModelShimmerHeader: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.15))
            .frame(width: 80, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.05), .white.opacity(0.25), .white.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .mask(
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.1), .white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .offset(x: phase * 240)
                    )
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: phase)
            )
            .onAppear { phase = 1.2 }
    }
}
```

---

## 7. Parent view wiring

```swift
struct ItemsGridView: View {
    @State private var selectedItem: MyItemModel?
    @State private var tappedCellFrame: CGRect = .zero
    @State private var dismissOverlay = false
    @State private var isLoading = true
    @State private var items: [MyItemModel] = []

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if isLoading {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in ModelShimmerItem() }
                    }
                    .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let isHidden = selectedItem?.id == item.id
                            ModelGridItem(
                                assetName: item.usdzAssetName,
                                imageName: item.imageName,
                                isUnlocked: item.isUnlocked,
                                progress: item.progressFraction,
                                progressLabel: item.progressLabel,
                                displayName: item.displayName,
                                index: index,
                                isHidden: isHidden,
                                onTap: { frame in
                                    dismissOverlay = false
                                    tappedCellFrame = frame
                                    selectedItem = item
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Your Collection")
        }
        .interactiveDismissDisabled(selectedItem != nil)
        .overlay {
            if let item = selectedItem {
                ModelDetailOverlay(
                    assetName: item.usdzAssetName,
                    imageName: item.imageName,
                    displayName: item.displayName,
                    description: item.description,
                    sourceFrame: tappedCellFrame,
                    isUnlocked: item.isUnlocked,
                    shouldDismiss: $dismissOverlay
                ) {
                    // Re-sort or update data, then clear selection
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.45))
                        selectedItem = nil
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { dismissOverlay = true } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding([.top, .trailing])
                }
                .zIndex(1)
                .transition(.identity) // animation is fully manual — no SwiftUI transition
            }
        }
    }
}
```

---

## 8. USDZ asset delivery

Store each USDZ file as a **Data set** (`NSDataAsset`) in the Xcode asset catalogue — not a regular file reference. This lets `NSDataAsset(name:)` load it at runtime without SCNScene's direct asset-catalogue path limitations.

Steps:
1. In the asset catalogue, add a new **Data** asset set.
2. Drop the `.usdz` file into the set (Universal slot).
3. Name the set (e.g. `badge_3_streak`) — this is the `assetName` you pass to `ModelSceneView`.
4. At runtime, write it to `FileManager.default.temporaryDirectory` and open with `SCNScene(url:)`.

---

## Key animation timing reference

| Animation | Duration | Curve |
|---|---|---|
| Grid cell pop-in (scale) | 0.42 s | spring(response: 0.42, dampingFraction: 0.52) |
| Grid cell stagger delay | index × 0.055 s | — |
| Grid cell brightness flash | 0.12 s in / 0.38 s out | easeIn / easeOut |
| Progress bar fill on appear | 0.6 s | spring(response: 0.6, dampingFraction: 0.8) |
| Overlay entry (scale+offset) | 0.5 s | spring(response: 0.5, dampingFraction: 0.82) |
| Overlay content fade-in | 0.25 s, delay 0.25 s | easeIn |
| Entry full flip (360°) | 0.6 s | easeInEaseOut (CABasicAnimation) |
| Entry spin (grid) | 0.8 s | easeInEaseOut (CABasicAnimation) |
| Pan spring-back | settlingDuration | CASpringAnimation(damping: 4, stiffness: 40, mass: 1) |
| Flip to front | 0.4 s | linear (CABasicAnimation) |
| Overlay dismiss content | 0.25 s | easeOut |
| Overlay dismiss scale | 0.3 s | spring(response: 0.3, dampingFraction: 0.85) |
| Total dismiss wait | 0.6 s | — |
| Post-dismiss re-sort delay | 0.45 s | spring(response: 0.55, dampingFraction: 0.82) |
| Shimmer sweep | 1.2 s | linear, repeatForever |

