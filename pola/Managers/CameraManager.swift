import AVFoundation
import CoreLocation
import Observation
import UIKit

struct ZoomOption: Equatable, Identifiable {
    let factor: CGFloat
    let displayMultiplier: CGFloat
    let name: String
    var id: CGFloat { factor }
}

@Observable
final class CameraManager: NSObject {
    private(set) var isAuthorized = false
    private(set) var isTorchOn = false
    private(set) var currentPosition: AVCaptureDevice.Position = .back
    private(set) var lastCoordinate: CLLocationCoordinate2D? = nil
    private(set) var isRecording = false
    private(set) var isTimelapsing = false
    private(set) var isAudioEnabled: Bool = UserDefaults.standard.object(forKey: "videoAudioEnabled") as? Bool ?? true
    private(set) var availableZoomOptions: [ZoomOption] = [ZoomOption(factor: 1.0, displayMultiplier: 1.0, name: "normal")]
    private(set) var currentZoomFactor: CGFloat = 1.0
    private(set) var timelapsePhaseStart: Date = .distantPast
    private(set) var timelapsePhotoCount = 0
    private(set) var timelapseMaxPhotos = 0

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pola.cameraSession", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let locationManager = CLLocationManager()

    var capturedImage: UIImage? = nil
    var capturedVideoURL: URL? = nil
    var timelapseVideoFrames: [UIImage]? = nil

    private var timelapseTimer: Timer?
    private var timeLapseSaveAsVideo = false
    private var timelapseFrames: [UIImage] = []
    private var pendingTimelapsePhotos = 0
    private var timelapseStopped = false

    func configure() async {
        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            isAuthorized = videoGranted
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
        guard videoGranted else { return }
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.setupSession(position: .back)
                self?.session.startRunning()
                continuation.resume()
            }
        }
    }

    // Returns the best available virtual device for the position, falling back to wide angle.
    // Virtual devices (triple/dual) let us switch lenses via videoZoomFactor with no session lag.
    private func bestVideoDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            for type in [AVCaptureDevice.DeviceType.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera] {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return device
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func select4to3Format(for device: AVCaptureDevice) {
        let target = 4.0 / 3.0
        let maxPixels = 4032 * 3024  // ~12 MP cap — avoids 48 MP modes on Pro sensors
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.height > 0 else { return false }
            return abs(Double(dims.width) / Double(dims.height) - target) < 0.05
        }
        let best = candidates
            .filter { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return Int(dims.width) * Int(dims.height) <= maxPixels
            }
            .max { a, b in
                let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
            }
            ?? candidates.max { a, b in
                let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
            }
        guard let format = best else { return }
        try? device.lockForConfiguration()
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    private func setupSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        guard
            let device = bestVideoDevice(for: position),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)
        select4to3Format(for: device)
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        let zoomOpts = buildZoomOptions(for: device)
        let initialFactor = startingZoomFactor(for: device)
        try? device.lockForConfiguration()
        device.videoZoomFactor = min(max(initialFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.unlockForConfiguration()
        DispatchQueue.main.async { [weak self] in
            self?.availableZoomOptions = zoomOpts
            self?.currentZoomFactor = initialFactor
        }
    }

    // Snap points: lens-switch factors + secondary native resolution factors (e.g. 2x crop on 14 Pro+).
    // Labels are formatted display multipliers: "0.5x", "1x", "2x", "3x".
    private func buildZoomOptions(for device: AVCaptureDevice) -> [ZoomOption] {
        let multiplier = device.displayVideoZoomFactorMultiplier
        let minFactor = device.minAvailableVideoZoomFactor
        let switchFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }

        var allFactors = Set<CGFloat>([minFactor] + switchFactors)
        // iOS 16+: 48 MP main sensor exposes a 2x native-resolution crop (and possibly others)
        if #available(iOS 16.0, *) {
            for f in device.activeFormat.secondaryNativeResolutionZoomFactors {
                allFactors.insert(f)
            }
        }

        return allFactors.sorted().map { factor in
            let display = factor * multiplier
            return ZoomOption(factor: factor, displayMultiplier: multiplier, name: formatDisplayZoom(display))
        }
    }

    private func formatDisplayZoom(_ value: CGFloat) -> String {
        let tenth = (value * 10).rounded() / 10
        if abs(tenth - tenth.rounded()) < 0.05 {
            return "\(Int(tenth.rounded()))x"
        }
        return String(format: "%.1fx", tenth)
    }

    // Wide-angle is at the first switchOver factor when an ultra-wide is present;
    // otherwise the device itself starts at 1.0.
    private func startingZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        if hasUltraWide, let firstSwitch = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            return CGFloat(firstSwitch.doubleValue)
        }
        return 1.0
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func resume() {
        sessionQueue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func toggleTorch() {
        guard let device = session.inputs
            .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
            .first(where: { $0.hasMediaType(.video) }),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        isTorchOn.toggle()
        device.torchMode = isTorchOn ? .on : .off
        device.unlockForConfiguration()
    }

    func toggleAudio() {
        isAudioEnabled.toggle()
        UserDefaults.standard.set(isAudioEnabled, forKey: "videoAudioEnabled")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let connection = movieOutput.connection(with: .audio) {
                connection.isEnabled = isAudioEnabled
            }
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            for input in session.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.hasMediaType(.video) {
                    session.removeInput(input)
                }
            }

            guard
                let device = bestVideoDevice(for: newPosition),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { return }

            session.addInput(input)
            select4to3Format(for: device)
            let newZoomOpts = buildZoomOptions(for: device)
            let initialFactor = startingZoomFactor(for: device)
            try? device.lockForConfiguration()
            device.videoZoomFactor = min(max(initialFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.currentPosition = newPosition
                self?.availableZoomOptions = newZoomOpts
                self?.currentZoomFactor = initialFactor
            }
        }
    }

    // Ramps videoZoomFactor on the active virtual device — animates the preview during lens transition.
    func switchZoom(to option: ZoomOption) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first(where: { $0.hasMediaType(.video) }) else { return }
            let clamped = min(max(option.factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            try? device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: clamped, withRate: 10)
            device.unlockForConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.currentZoomFactor = option.factor
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

    func startVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !movieOutput.isRecording else { return }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }

    func stopVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self, movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    func startTimelapse(interval: Double, duration: Double, saveAsVideo: Bool) {
        guard !isTimelapsing else { return }
        isTimelapsing = true
        UIApplication.shared.isIdleTimerDisabled = true
        timeLapseSaveAsVideo = saveAsVideo
        timelapseFrames = []
        timelapseMaxPhotos = max(1, Int(duration / interval))
        timelapsePhotoCount = 0
        timelapsePhaseStart = Date()
        pendingTimelapsePhotos = 0
        timelapseStopped = false
        pendingTimelapsePhotos += 1
        capturePhoto()
        timelapsePhotoCount += 1
        guard timelapsePhotoCount < timelapseMaxPhotos else {
            stopTimelapse()
            return
        }
        timelapseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            pendingTimelapsePhotos += 1
            capturePhoto()
            timelapsePhotoCount += 1
            if timelapsePhotoCount >= timelapseMaxPhotos {
                stopTimelapse()
            }
        }
    }

    func stopTimelapse() {
        timelapseTimer?.invalidate()
        timelapseTimer = nil
        timelapseStopped = true
        if pendingTimelapsePhotos == 0 {
            finalizeTimelapse()
        }
    }

    private func finalizeTimelapse() {
        isTimelapsing = false
        UIApplication.shared.isIdleTimerDisabled = false
        if timeLapseSaveAsVideo && !timelapseFrames.isEmpty {
            timelapseVideoFrames = timelapseFrames
        }
        timelapseFrames = []
        timelapseStopped = false
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
            guard let self else { return }
            if pendingTimelapsePhotos > 0 {
                pendingTimelapsePhotos -= 1
                if timeLapseSaveAsVideo {
                    timelapseFrames.append(image)
                } else {
                    capturedImage = image
                }
                timelapsePhaseStart = Date()
                if timelapseStopped && pendingTimelapsePhotos == 0 {
                    finalizeTimelapse()
                }
            } else {
                capturedImage = image
            }
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let finished = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRecording = false
            UIApplication.shared.isIdleTimerDisabled = false
            if finished {
                capturedVideoURL = outputFileURL
            }
        }
    }
}
