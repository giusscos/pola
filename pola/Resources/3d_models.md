# Build a 3D Interactive Model Card System in SwiftUI (SceneKit + USDZ)

Build a full 3D interactive card/badge system in SwiftUI using SceneKit and USDZ assets. The system has four layers: a reusable 3D scene renderer, a grid cell, a full-screen detail overlay with entry/exit animations, and shimmer placeholders for loading states.

---

## Architecture overview

```
ModelSceneView          — UIViewRepresentable wrapping SCNView, renders .usdz assets with three-point lighting
ModelSceneHandle        — Reference object bridging SwiftUI state to SceneKit animations
FilterItemCell          — Grid cell: auto-rotating 3D preview or flat colour swatch fallback
FilterModelView         — Full-screen detail overlay: gestured 3D model on black background
```

---

## 1. `ModelSceneView` — `UIViewRepresentable`

- Use a regular `SCNView` directly — no subclass needed.
- In `makeUIView`:
  - Load USDZ via `Bundle.main.url(forResource: assetName, withExtension: "usdz")` and open with `SCNScene(url:options:)`.
  - Compute the bounding box; `maxDim = max(x, y, z extents)`. Guard that `maxDim > 0`.
  - Scale `model` node to `modelScale / maxDim` and translate so the geometric centre sits at the local origin.
  - Wrap `model` in a `tiltNode` rotated −90° on X — this corrects USDZ's Z-up convention to SceneKit's Y-up so the model stands upright.
  - Wrap `tiltNode` in a `spinNode` at world origin with no initial rotation. All Y-axis animations target `spinNode`.
  - Add **three directional lights**: key (intensity 1400, −45°X/+30°Y), fill (500, −30°X/−60°Y), rim (300, +30°X/+180°Y).
  - Add a soft **ambient light** (white, intensity 400).
  - Camera node at `(0, 0, 2.2)`, `fieldOfView = 45`; set as `pointOfView`.
  - Set `autoenablesDefaultLighting = false`, `allowsCameraControl = false`, `antialiasingMode = .multisampling4X`, `backgroundColor = .clear`.
  - If `autoRotate`, call `coordinator.startAutoRotate()` to start a continuous `SCNAction.rotateBy(y: 2π, duration: 4).repeatForever`.
  - If `spinOnAppear`, fire `coordinator.triggerEntrySpin()` after a 100 ms `DispatchQueue.main.asyncAfter`.
  - If `gestureEnabled`, attach a `UIPanGestureRecognizer` to the coordinator's `handlePan`.
- `updateUIView` is empty — all state is committed once in `makeUIView`.
- `Coordinator`:
  - `startAutoRotate()` — runs `SCNAction.repeatForever(SCNAction.rotateBy(x:0, y:2π, z:0, duration:4))` on `spinNode`.
  - `triggerEntrySpin()` — `CABasicAnimation` on `eulerAngles.y` from current → current + 2π, duration 0.8 s, `easeInEaseOut`, `isRemovedOnCompletion = true`.
  - `handlePan(_:)`:
    - `.began`: remove auto-rotate action; freeze `eulerAngles.y` from the presentation layer.
    - `.changed`: freeze presentation angle, accumulate `delta.x * 0.01` radians, reset translation.
    - `.ended/.cancelled`: if `|velocity.x| > 80`, add a coast `CABasicAnimation` (easeOut, `duration = min(|velocity| / 1800, 0.7)`) then commit the final angle — no snap to π. If `autoRotate`, re-call `startAutoRotate()` after 1.2 s (or 0.4 s for slow pans).

### Full implementation

```swift
import SceneKit
import SwiftUI

struct ModelSceneView: UIViewRepresentable {
    let assetName: String
    var gestureEnabled: Bool = true
    var autoRotate: Bool = false
    var spinOnAppear: Bool = false
    var modelScale: CGFloat = 1.0
    var handle: ModelSceneHandle? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = false
        sceneView.antialiasingMode = .multisampling4X

        guard let url = Bundle.main.url(forResource: assetName, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else {
            return sceneView
        }

        // Collect all geometry under a single model node
        let model = SCNNode()
        for child in scene.rootNode.childNodes {
            model.addChildNode(child)
        }

        // Validate bounds
        let (minB, maxB) = model.boundingBox
        let maxDim = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        guard maxDim > 0 else { return sceneView }

        // Center model at local origin so the tiltNode rotates around the true geometric center
        let center = SCNVector3(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
        let s = Float(modelScale) / maxDim
        model.scale = SCNVector3(s, s, s)
        model.position = SCNVector3(-s * center.x, -s * center.y, -s * center.z)

        // tiltNode corrects USDZ Z-up orientation to SceneKit Y-up so the model stands upright.
        let tiltNode = SCNNode()
        tiltNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        tiltNode.addChildNode(model)

        // spinNode sits at world origin — all Y-axis spin animations apply here.
        let spinNode = SCNNode()
        spinNode.addChildNode(tiltNode)
        scene.rootNode.addChildNode(spinNode)

        // Three-point + ambient lighting
        func addLight(type: SCNLight.LightType, intensity: CGFloat, euler: SCNVector3) {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = type
            node.light?.intensity = intensity
            node.light?.castsShadow = false
            node.eulerAngles = euler
            scene.rootNode.addChildNode(node)
        }
        addLight(type: .directional, intensity: 1400,
                 euler: SCNVector3(-Float.pi / 4,  Float.pi / 6, 0))
        addLight(type: .directional, intensity: 500,
                 euler: SCNVector3(-Float.pi / 6, -Float.pi / 3, 0))
        addLight(type: .directional, intensity: 300,
                 euler: SCNVector3( Float.pi / 6,  Float.pi,     0))
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor.white
        ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)

        // Camera: model fills ~55% of viewport at default scale 1.0
        let camera = SCNCamera()
        camera.fieldOfView = 45
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2.2)
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        sceneView.scene = scene
        context.coordinator.modelNode = spinNode
        context.coordinator.autoRotate = autoRotate
        handle?.coordinator = context.coordinator
        handle?.sceneView = sceneView

        if autoRotate {
            context.coordinator.startAutoRotate()
        }

        if spinOnAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                context.coordinator.triggerEntrySpin()
            }
        }

        if gestureEnabled {
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            sceneView.addGestureRecognizer(pan)
        }

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var modelNode: SCNNode?
        var autoRotate: Bool = false

        func startAutoRotate() {
            guard let node = modelNode else { return }
            let spin = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 4)
            node.runAction(SCNAction.repeatForever(spin), forKey: "autoRotate")
        }

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
            case .began:
                node.removeAction(forKey: "autoRotate")
                node.removeAllAnimations()
                node.eulerAngles = node.presentation.eulerAngles

            case .changed:
                node.removeAllAnimations()
                node.eulerAngles = node.presentation.eulerAngles
                let delta = gesture.translation(in: gesture.view)
                node.eulerAngles.y += Float(delta.x) * 0.01
                gesture.setTranslation(.zero, in: gesture.view)

            case .ended, .cancelled:
                let current = node.presentation.eulerAngles.y
                node.eulerAngles.y = current

                // Coast to stop based on finger velocity — no snap points
                let velocity = gesture.velocity(in: gesture.view)
                if abs(velocity.x) > 80 {
                    let coast = Float(velocity.x) * 0.0018
                    let duration = min(Double(abs(velocity.x)) / 1800.0, 0.7)
                    let momentum = CABasicAnimation(keyPath: "eulerAngles.y")
                    momentum.fromValue = current
                    momentum.toValue = current + coast
                    momentum.duration = duration
                    momentum.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    momentum.isRemovedOnCompletion = true
                    node.addAnimation(momentum, forKey: "momentum")
                    node.eulerAngles.y = current + coast
                }

                if autoRotate {
                    let delay = abs(velocity.x) > 80 ? 1.2 : 0.4
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.startAutoRotate()
                    }
                }

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
// MARK: - ModelSceneHandle

final class ModelSceneHandle: NSObject {
    weak var coordinator: ModelSceneView.Coordinator?
    var sceneView: SCNView?

    func triggerSpin() {
        coordinator?.triggerEntrySpin()
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

    @discardableResult
    func flipToFrontIfNeeded() -> TimeInterval {
        guard let node = coordinator?.modelNode else { return 0 }
        node.removeAllAnimations()
        let current = node.presentation.eulerAngles.y
        node.eulerAngles.y = current
        let n = (current / Float.pi).rounded()
        guard abs(Int(n)) % 2 == 1 else { return 0 }
        let sign: Float = n > 0 ? -1 : 1
        let target = (n + sign) * Float.pi
        let flip = CABasicAnimation(keyPath: "eulerAngles.y")
        flip.fromValue = current
        flip.toValue = target
        flip.duration = 0.4
        flip.timingFunction = CAMediaTimingFunction(name: .linear)
        node.addAnimation(flip, forKey: "flipToFront")
        node.eulerAngles.y = target
        return 0.4
    }
}
```

---

## 3. `FilterItemCell` — Grid cell view

Used inside `FiltersView` to display each film filter as an auto-rotating 3D model (or a flat colour swatch if no USDZ is available). Tapping selects the filter and dismisses the sheet.

```swift
struct FilterItemCell: View {
    let filter: FilmFilter
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let usdzName = filter.usdzName {
                    ModelSceneView(assetName: usdzName, gestureEnabled: false, autoRotate: true)
                } else {
                    Circle()
                        .fill(filter.color)
                        .frame(width: 40, height: 40)
                }
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(filter.color)
                                .background(.white, in: .circle)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? filter.color : .clear, lineWidth: 3)
            )

            HStack(spacing: 4) {
                Circle()
                    .fill(filter.color)
                    .frame(width: 7, height: 7)

                Text(filter.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}
```

---

## 4. `FilterModelView` — Full-screen detail overlay

A full-screen black view presenting the filter's 3D model with gesture-driven rotation and a spin-on-appear animation. Presented as a sheet or `.fullScreenCover` from `FiltersView`.

```swift
struct FilterModelView: View {
    let filter: FilmFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let usdzName = filter.usdzName {
                ModelSceneView(
                    assetName: usdzName,
                    gestureEnabled: true,
                    spinOnAppear: true,
                    modelScale: 0.65
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            overlayUI
        }
    }

    private var overlayUI: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.15), in: .circle)
                }
                .padding(.leading, 20)
                .padding(.top, 16)
                Spacer()
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(filter.color)
                    .frame(width: 10, height: 10)
                Text(filter.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 50)
        }
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

            Text("poly.")
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

Store each USDZ file as a **regular file reference** inside the Xcode project so it is bundled into the app. `ModelSceneView` loads it at runtime with:

```swift
Bundle.main.url(forResource: assetName, withExtension: "usdz")
```

Steps:
1. Drag the `.usdz` file into the Xcode project navigator (tick **Copy items if needed**).
2. Ensure the file is listed under **Build Phases → Copy Bundle Resources**.
3. Pass the filename without extension as `assetName` to `ModelSceneView` (e.g. `"FLARN_film35"`).
4. At runtime, `Bundle.main.url` resolves the path and `SCNScene(url:options:)` opens it directly — no temporary file needed.

---

## Key animation timing reference

| Animation | Duration | Curve |
|---|---|---|
| Entry spin (on appear) | 0.8 s | easeInEaseOut (CABasicAnimation) |
| Entry full flip (360°) | 0.6 s | easeInEaseOut (CABasicAnimation) |
| Auto-rotate cycle | 4 s | linear, repeatForever (SCNAction) |
| Auto-rotate resume delay | 0.4–1.2 s | based on pan velocity |
| Pan coast (momentum) | velocity / 1800, max 0.7 s | easeOut (CABasicAnimation) |
| Flip to front | 0.4 s | linear (CABasicAnimation) |
| Overlay entry (scale+offset) | 0.5 s | spring(response: 0.5, dampingFraction: 0.82) |
| Overlay content fade-in | 0.25 s, delay 0.25 s | easeIn |
| Overlay dismiss content | 0.25 s | easeOut |
| Overlay dismiss scale | 0.3 s | spring(response: 0.3, dampingFraction: 0.85) |
| Total dismiss wait | 0.6 s | — |
| Shimmer sweep | 1.2 s | linear, repeatForever |

