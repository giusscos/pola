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
                context.coordinator.normDim = max(size.x, size.y, size.z)
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
                cameraNode.position = SCNVector3(0, 0, 10)
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
        modelNode.position = SCNVector3(-center.x, -center.y, -center.z)

        // Scale the model so its largest dimension fills the padded view area.
        // Camera sits at z=4.5 with a 60° vertical FOV, so the visible scene height
        // at the model plane (z=0) is 2 * 4.5 * tan(30°) ≈ 5.196 scene units.
        let cameraZ: Float = 4.5
        let fovRad: Float = Float(60.0 * Double.pi / 180.0)
        let sceneHeight = 2.0 * cameraZ * tan(fovRad / 2.0)
        let fillFraction = (Float(bounds.height) - Float(padding * 2)) / Float(bounds.height)
        let scale = (sceneHeight * fillFraction) / coordinator.normDim
        modelNode.scale = SCNVector3(scale, scale, scale)
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
}
