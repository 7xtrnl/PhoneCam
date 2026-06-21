import AVFoundation
import UIKit
import Combine

/// Verwaltet die Kamera-Session, Zoom, Front/Back-Switch und liefert
/// JPEG-encodierte Frames an alle Abonnenten (z.B. den Netzwerk-Server).
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published state für die UI

    @Published var isRunning = false
    @Published var currentPosition: AVCaptureDevice.Position = .back
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 5.0
    @Published var targetFPS: Int = 30 {
        didSet { applyFrameRate() }
    }
    @Published var jpegQuality: CGFloat = 0.6 // 0.1 (klein/schnell) ... 1.0 (groß/scharf)
    @Published var resolutionPreset: ResolutionPreset = .hd720 {
        didSet { configureSession() }
    }
    @Published var lastPreviewImage: UIImage?

    /// Wenn gesetzt, wird dieses Standbild statt des Live-Kamerabilds gesendet
    /// (z.B. Foto aus der Galerie als "virtuelle Kamera-Quelle").
    @Published var stillImageOverride: UIImage? {
        didSet { stillFrameCounter = 0 }
    }

    enum ResolutionPreset: String, CaseIterable, Identifiable {
        case sd480 = "480p"
        case hd720 = "720p"
        case hd1080 = "1080p"
        var id: String { rawValue }

        var sessionPreset: AVCaptureSession.Preset {
            switch self {
            case .sd480: return .vga640x480
            case .hd720: return .hd1280x720
            case .hd1080: return .hd1920x1080
            }
        }
    }

    // MARK: - Frame-Callback

    /// Wird für jeden neuen JPEG-Frame aufgerufen (Bytes, Breite, Höhe).
    var onJPEGFrame: ((Data) -> Void)?

    // MARK: - Private

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "phonecam.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentDevice: AVCaptureDevice?
    private let ciContext = CIContext()
    private var stillFrameCounter = 0

    override init() {
        super.init()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    // MARK: - Public Controls

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func switchCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        configureSession()
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let clamped = max(minZoom, min(factor, maxZoom))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoomFactor = clamped }
        } catch {
            print("Zoom-Fehler: \(error)")
        }
    }

    // MARK: - Session Setup

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            // Alte Inputs entfernen
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }

            if self.session.canSetSessionPreset(self.resolutionPreset.sessionPreset) {
                self.session.sessionPreset = self.resolutionPreset.sessionPreset
            }

            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: self.currentPosition
            ) else {
                print("Keine Kamera für Position \(self.currentPosition) gefunden")
                self.session.commitConfiguration()
                return
            }
            self.currentDevice = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                print("Kamera-Input-Fehler: \(error)")
                self.session.commitConfiguration()
                return
            }

            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            if let connection = self.videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    connection.videoRotationAngle = 90 // Hochformat
                } else if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = (self.currentPosition == .front)
                }
            }

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.minZoom = device.minAvailableVideoZoomFactor
                self.maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
                self.zoomFactor = device.videoZoomFactor
            }

            self.applyFrameRate()
        }
    }

    private func applyFrameRate() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            do {
                try device.lockForConfiguration()
                let fps = Double(self.targetFPS)
                let duration = CMTimeMake(value: 1, timescale: Int32(fps))
                let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                    fps >= $0.minFrameRate && fps <= $0.maxFrameRate
                }
                if supported {
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                }
                device.unlockForConfiguration()
            } catch {
                print("FPS-Fehler: \(error)")
            }
        }
    }

    // MARK: - Standbild-Modus (Foto aus Galerie)

    private func emitStillImageIfNeeded() -> Bool {
        guard let stillImage = stillImageOverride else { return false }
        // Standbild nur mit der eingestellten Ziel-FPS erneut senden,
        // damit der PC-Client die Verbindung als "aktiv" erkennt.
        stillFrameCounter += 1
        if let cgImage = stillImage.cgImage,
           let data = jpegData(from: cgImage) {
            onJPEGFrame?(data)
            DispatchQueue.main.async { self.lastPreviewImage = stillImage }
        }
        return true
    }

    private func jpegData(from cgImage: CGImage) -> Data? {
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: jpegQuality)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Wenn ein Standbild aktiv ist, ignorieren wir Live-Frames und
        // senden stattdessen periodisch das Standbild.
        if stillImageOverride != nil {
            _ = emitStillImageIfNeeded()
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        if let data = uiImage.jpegData(compressionQuality: jpegQuality) {
            onJPEGFrame?(data)
            // Throttle Preview-Updates auf ~10/s, um die Haupt-UI nicht zu fluten
            if stillFrameCounter % 3 == 0 {
                DispatchQueue.main.async { self.lastPreviewImage = uiImage }
            }
            stillFrameCounter += 1
        }
    }
}
