import AVFoundation
import CoreLocation
import Observation
import UIKit

@Observable
final class CameraManager: NSObject {
    private(set) var isAuthorized = false
    private(set) var isTorchOn = false
    private(set) var currentPosition: AVCaptureDevice.Position = .back
    private(set) var lastCoordinate: CLLocationCoordinate2D? = nil

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pola.cameraSession", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let locationManager = CLLocationManager()

    var capturedImage: UIImage?

    func configure() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            isAuthorized = granted
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
        guard granted else { return }
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.setupSession(position: .back)
                self?.session.startRunning()
                continuation.resume()
            }
        }
    }

    private func setupSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
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

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Remove current video input
            for input in session.inputs {
                session.removeInput(input)
            }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { return }

            session.addInput(input)
            DispatchQueue.main.async { [weak self] in
                self?.currentPosition = newPosition
            }
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastCoordinate = locations.last?.coordinate
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
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
