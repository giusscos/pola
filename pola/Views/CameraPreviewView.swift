import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var mirrorFrontCamera: Bool
    var isFrontCamera: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
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
    }
}
