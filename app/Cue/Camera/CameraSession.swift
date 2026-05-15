// app/Cue/Camera/CameraSession.swift
import AVFoundation
import CoreImage
import Combine
import UIKit

public protocol CameraSessionDelegate: AnyObject {
    func cameraDidEmitPreview(_ pixelBuffer: CVPixelBuffer)
    func cameraDidCapturePhoto(_ ciImage: CIImage)
    func cameraDidFail(_ error: Error)
}

public enum CameraError: Error {
    case permissionDenied
    case noBackCamera
    case configureFailed
}

public final class CameraSession: NSObject {
    public let session = AVCaptureSession()
    public weak var delegate: CameraSessionDelegate?

    private let sessionQueue = DispatchQueue(label: "cue.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?

    public override init() {
        super.init()
    }

    public func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw CameraError.noBackCamera
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.configureFailed }
                self.session.addInput(input)
                self.videoDeviceInput = input

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cue.camera.video"))
                guard self.session.canAddOutput(self.videoOutput) else { throw CameraError.configureFailed }
                self.session.addOutput(self.videoOutput)
                if let conn = self.videoOutput.connection(with: .video) {
                    // iOS 17+: 90° = portrait. Replaces deprecated videoOrientation.
                    if conn.isVideoRotationAngleSupported(90) {
                        conn.videoRotationAngle = 90
                    }
                }

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.configureFailed }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                self.session.commitConfiguration()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.delegate?.cameraDidFail(error) }
            }
        }
    }

    public func start() {
        sessionQueue.async { [weak self] in
            if let s = self?.session, !s.isRunning { s.startRunning() }
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            if let s = self?.session, s.isRunning { s.stopRunning() }
        }
    }

    public func capture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Ramp the active device's videoZoomFactor. Clamped to [1.0, min(activeFormat.max, 3.0)].
    public func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            let clamped = max(1.0, min(factor, min(device.activeFormat.videoMaxZoomFactor, 3.0)))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: clamped, withRate: 4.0)
                device.unlockForConfiguration()
            } catch {
                // best-effort; ignore
            }
        }
    }

    public static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraDidEmitPreview(pb)
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            DispatchQueue.main.async { self.delegate?.cameraDidFail(error) }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let ci = CIImage(data: data) else {
            DispatchQueue.main.async { self.delegate?.cameraDidFail(CameraError.configureFailed) }
            return
        }
        DispatchQueue.main.async { self.delegate?.cameraDidCapturePhoto(ci) }
    }
}
