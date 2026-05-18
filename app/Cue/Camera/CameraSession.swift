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

    /// Guards against double captures (two taps, or capture() + captureWithAutofocus()
    /// both firing). Mutated only on `sessionQueue`.
    private var isCapturing = false

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
                // The still-photo connection needs the same portrait rotation as
                // the preview, otherwise captured photos come out landscape.
                if let pconn = self.photoOutput.connection(with: .video),
                   pconn.isVideoRotationAngleSupported(90) {
                    pconn.videoRotationAngle = 90
                }

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
            guard !self.isCapturing else { return }
            self.isCapturing = true
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Lock autofocus + auto-exposure at the screen center, wait briefly for the
    /// focus to settle, then fire the shutter. Used by the auto-align flow so the
    /// captured frame is sharp even right after a zoom ramp.
    public func captureWithAutofocus() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            guard !self.isCapturing else { return }
            self.isCapturing = true
            let center = CGPoint(x: 0.5, y: 0.5)
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = center
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = center
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                }
                device.unlockForConfiguration()
            } catch {
                // best-effort; fall through to capture without locked focus
            }
            // Give AF/AE ~400ms to settle (covers zoom-ramp + AF convergence on iPhone 14+).
            self.sessionQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                settings.flashMode = .auto
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
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
        // AVFoundation recycles `pb`'s memory after this callback returns; the
        // delegate stashes the buffer and reads it later, so hand it a deep copy.
        guard let copy = CameraSession.deepCopyPixelBuffer(pb) else { return }
        delegate?.cameraDidEmitPreview(copy)
    }

    /// Allocate a fresh CVPixelBuffer with the same width/height/format and
    /// memcpy the source's pixel data into it. Returns nil on allocation failure.
    static func deepCopyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(src)
        let height = CVPixelBufferGetHeight(src)
        let format = CVPixelBufferGetPixelFormatType(src)

        var dst: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
                                         attrs as CFDictionary, &dst)
        guard status == kCVReturnSuccess, let dst else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }

        let planeCount = CVPixelBufferGetPlaneCount(src)
        if planeCount == 0 {
            // Non-planar (e.g. 32BGRA).
            guard let srcBase = CVPixelBufferGetBaseAddress(src),
                  let dstBase = CVPixelBufferGetBaseAddress(dst) else { return nil }
            let srcStride = CVPixelBufferGetBytesPerRow(src)
            let dstStride = CVPixelBufferGetBytesPerRow(dst)
            if srcStride == dstStride {
                memcpy(dstBase, srcBase, srcStride * height)
            } else {
                let rowBytes = min(srcStride, dstStride)
                for row in 0..<height {
                    memcpy(dstBase.advanced(by: row * dstStride),
                           srcBase.advanced(by: row * srcStride),
                           rowBytes)
                }
            }
        } else {
            for plane in 0..<planeCount {
                guard let srcBase = CVPixelBufferGetBaseAddressOfPlane(src, plane),
                      let dstBase = CVPixelBufferGetBaseAddressOfPlane(dst, plane) else { return nil }
                let srcStride = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
                let dstStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
                let planeHeight = CVPixelBufferGetHeightOfPlane(src, plane)
                if srcStride == dstStride {
                    memcpy(dstBase, srcBase, srcStride * planeHeight)
                } else {
                    let rowBytes = min(srcStride, dstStride)
                    for row in 0..<planeHeight {
                        memcpy(dstBase.advanced(by: row * dstStride),
                               srcBase.advanced(by: row * srcStride),
                               rowBytes)
                    }
                }
            }
        }
        return dst
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Reset the capture guard on `sessionQueue` regardless of success/failure.
        sessionQueue.async { [weak self] in self?.isCapturing = false }
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
