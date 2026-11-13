import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var mirrorFrontCamera: Bool
    var isFrontCamera: Bool
    /// Pinch to zoom is off while recording, shooting a time lapse or holding a first exposure.
    var isZoomEnabled = true
    /// A tap, in capture-device coordinates (0...1).
    var onFocus: ((CGPoint) -> Void)? = nil
    /// Pinch scale relative to where the pinch began; `nil` when it began.
    var onPinch: ((CGFloat?) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocus = onFocus
        view.onPinch = onPinch
        view.isZoomEnabled = isZoomEnabled
        #if targetEnvironment(simulator)
        view.showSimulatorFeed()
        #endif
        attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onFocus = onFocus
        uiView.onPinch = onPinch
        uiView.isZoomEnabled = isZoomEnabled
        attach(to: uiView)
    }

    /// Attaching a session to a preview layer makes AVFoundation rebuild its capture graph and
    /// spin a nested run loop until it's done. Doing that inside SwiftUI's update re-enters the
    /// view graph ("Cycle detected through attribute") and breaks sheet presentation, so attach
    /// only when the session changes and after the current update has finished.
    private func attach(to view: PreviewView) {
        guard view.previewLayer.session !== session else {
            applyMirroring(to: view.previewLayer)
            return
        }
        let session = session
        let mirroring = self
        DispatchQueue.main.async {
            if view.previewLayer.session !== session {
                view.previewLayer.session = session
            }
            mirroring.applyMirroring(to: view.previewLayer)
        }
    }

    private func applyMirroring(to previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isFrontCamera && mirrorFrontCamera
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var onFocus: ((CGPoint) -> Void)?
        var onPinch: ((CGFloat?) -> Void)?
        var isZoomEnabled = true {
            didSet { pinchRecognizer.isEnabled = isZoomEnabled }
        }
        private lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        private let focusSquare = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
            addGestureRecognizer(pinchRecognizer)
            focusSquare.layer.borderColor = UIColor.systemYellow.cgColor
            focusSquare.layer.borderWidth = 1.5
            focusSquare.alpha = 0
            focusSquare.isUserInteractionEnabled = false
            focusSquare.isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            let point = recognizer.location(in: self)
            onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: point))
            showFocusSquare(at: point)
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began: onPinch?(nil)
            case .changed: onPinch?(recognizer.scale)
            default: break
            }
        }

        private func showFocusSquare(at point: CGPoint) {
            if focusSquare.superview == nil { addSubview(focusSquare) }
            bringSubviewToFront(focusSquare)
            focusSquare.layer.removeAllAnimations()
            focusSquare.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
            focusSquare.center = point
            focusSquare.alpha = 1
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            focusSquare.transform = reduceMotion ? .identity : CGAffineTransform(scaleX: 1.4, y: 1.4)
            UIView.animate(withDuration: reduceMotion ? 0 : 0.25) {
                self.focusSquare.transform = .identity
            }
            UIView.animate(withDuration: 0.3, delay: 1.0, options: [.beginFromCurrentState]) {
                self.focusSquare.alpha = 0
            }
        }

        #if targetEnvironment(simulator)
        private let feedView = UIImageView()

        func showSimulatorFeed() {
            feedView.contentMode = .scaleAspectFill
            feedView.clipsToBounds = true
            feedView.image = SimulatorFeed.shared.current
            feedView.frame = bounds
            feedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(feedView)
            NotificationCenter.default.addObserver(forName: SimulatorFeed.didAdvance, object: nil, queue: .main) { [weak self] _ in
                self?.feedView.image = SimulatorFeed.shared.current
            }
        }
        #endif
    }
}
