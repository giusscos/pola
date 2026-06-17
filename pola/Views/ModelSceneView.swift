import SceneKit
import SwiftUI

// MARK: - ModelSceneView

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

        // tiltNode corrects USDZ Z-up orientation to SceneKit Y-up so the canister stands upright.
        // It is a static node — all spin animation happens on spinNode above it.
        let tiltNode = SCNNode()
        tiltNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        tiltNode.addChildNode(model)

        // spinNode sits at world origin with no initial rotation, so Y-axis animations
        // correctly spin around the world Y axis (turntable effect).
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
