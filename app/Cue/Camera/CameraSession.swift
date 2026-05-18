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

/// Maps between an *optical* zoom factor (the 0.5x–3x scale the user and AI
/// think in) and the device's raw `videoZoomFactor`. On a virtual multi-camera
/// device raw 1.0 is the ultra-wide; the main "1x" lens sits at a higher raw
/// factor (`oneXRawFactor`). Pure value type — no device dependency, unit-tested.
public struct ZoomMapping: Equatable {
    /// Raw `videoZoomFactor` of the main "1x" lens (1.0 on a single-cam device).
    public let oneXRawFactor: CGFloat
    /// Device raw zoom bounds.
    public let minRaw: CGFloat
    public let maxRaw: CGFloat

    public init(oneXRawFactor: CGFloat, minRaw: CGFloat, maxRaw: CGFloat) {
        self.oneXRawFactor = max(oneXRawFactor, 1.0)
        self.minRaw = minRaw
        self.maxRaw = maxRaw
    }

    /// Lowest optical factor the device can reach (0.5 on multi-cam, 1.0 single-cam).
    public var minOptical: CGFloat { minRaw / oneXRawFactor }
    /// Highest optical factor we expose — capped at 3.0.
    public var maxOptical: CGFloat { min(maxRaw / oneXRawFactor, 3.0) }

    /// Clamp an optical factor into `[minOptical, maxOptical]`.
    public func clampOptical(_ optical: CGFloat) -> CGFloat {
        max(minOptical, min(optical, maxOptical))
    }

    /// Raw `videoZoomFactor` for an optical factor (clamped first).
    public func rawFor(optical: CGFloat) -> CGFloat {
        clampOptical(optical) * oneXRawFactor
    }
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
    /// Which camera is active. Mutated only on `sessionQueue`.
    private var currentPosition: AVCaptureDevice.Position = .back

    public override init() {
        super.init()
    }

    public func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            do {
                let input = try self.makeInput(position: .back)
                guard self.session.canAddInput(input) else { throw CameraError.configureFailed }
                self.session.addInput(input)
                self.videoDeviceInput = input
                self.currentPosition = .back

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cue.camera.video"))
                guard self.session.canAddOutput(self.videoOutput) else { throw CameraError.configureFailed }
                self.session.addOutput(self.videoOutput)

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.configureFailed }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                self.applyPortraitRotation()
                self.session.commitConfiguration()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.delegate?.cameraDidFail(error) }
            }
        }
    }

    /// Build a camera input for the given position.
    private func makeInput(position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noBackCamera
        }
        return try AVCaptureDeviceInput(device: device)
    }

    /// Pin every connection to portrait (90°) — preview and still photo alike,
    /// otherwise frames/photos come out landscape.
    private func applyPortraitRotation() {
        for output in [videoOutput as AVCaptureOutput, photoOutput as AVCaptureOutput] {
            if let conn = output.connection(with: .video),
               conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }
    }

    /// Switch between the back and front camera. Safe to call anytime.
    public func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let oldInput = self.videoDeviceInput else { return }
            let target: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let newInput = try? self.makeInput(position: target) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
                self.currentPosition = target
            } else {
                self.session.addInput(oldInput)  // revert — keep a working camera
            }
            self.applyPortraitRotation()
            self.session.commitConfiguration()
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
              // applyOrientationProperty bakes the EXIF orientation into the
              // pixels — without it CIImage(data:) hands back the sensor's
              // native landscape and the photo comes out sideways.
              let ci = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            DispatchQueue.main.async { self.delegate?.cameraDidFail(CameraError.configureFailed) }
            return
        }
        DispatchQueue.main.async { self.delegate?.cameraDidCapturePhoto(ci) }
    }
}
