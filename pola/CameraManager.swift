import AVFoundation
import Observation
import UIKit

@Observable
final class CameraManager: NSObject {
    private(set) var isAuthorized = false
    private(set) var isTorchOn = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pola.cameraSession", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()

    var capturedImage: UIImage?

    func configure() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run { isAuthorized = granted }
        guard granted else { return }
        sessionQueue.async { [weak self] in
            self?.setupSession()
            self?.session.startRunning()
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        isTorchOn.toggle()
        device.torchMode = isTorchOn ? .on : .off
        device.unlockForConfiguration()
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
        }
    }
}
