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
    /// Device raw zoom lower bound — clamped to ≥ 1.0 (`videoZoomFactor` is never below 1.0).
    public let minRaw: CGFloat
    /// Device raw zoom upper bound — clamped to ≥ `minRaw`.
    public let maxRaw: CGFloat

    public init(oneXRawFactor: CGFloat, minRaw: CGFloat, maxRaw: CGFloat) {
        self.oneXRawFactor = max(oneXRawFactor, 1.0)
        self.minRaw = max(minRaw, 1.0)
        self.maxRaw = max(maxRaw, self.minRaw)
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

    /// Optical-zoom state. Written on `sessionQueue`, read (approximately) from
    /// any thread under `zoomStateLock`.
    private let zoomStateLock = NSLock()
    private var _zoomMap = ZoomMapping(oneXRawFactor: 1.0, minRaw: 1.0, maxRaw: 1.0)
    private var _currentOptical: CGFloat = 1.0

    /// Current optical zoom factor (last value passed to `setZoom`, clamped).
    public var currentOpticalZoom: CGFloat { zoomStateLock.withLock { _currentOptical } }
    /// Lowest optical factor the active device supports (0.5 on multi-cam).
    public var minOpticalZoom: CGFloat { zoomStateLock.withLock { _zoomMap.minOptical } }
    /// Highest optical factor exposed (3.0).
    public var maxOpticalZoom: CGFloat { zoomStateLock.withLock { _zoomMap.maxOptical } }

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
                self.updateZoomState(for: input.device)

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
        guard let device = Self.bestDevice(position: position) else {
            throw CameraError.noBackCamera
        }
        return try AVCaptureDeviceInput(device: device)
    }

    /// Pick the widest-range camera for `position`. Back: prefer a virtual
    /// multi-camera device (ultra-wide … tele as one continuous zoom range) so
    /// optical zoom can reach 0.5x; fall back to the plain wide-angle camera on
    /// devices without one. Front: the plain wide-angle camera.
    private static func bestDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            for type in [AVCaptureDevice.DeviceType.builtInTripleCamera,
                         .builtInDualWideCamera,
                         .builtInDualCamera] {
                if let d = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return d
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Build the optical↔raw zoom mapping for `device`. On a virtual multi-cam
    /// device the first lens-switchover factor is the raw zoom of the main "1x"
    /// lens; a single-cam device has none, so 1x == raw 1.0.
    private static func zoomMapping(for device: AVCaptureDevice) -> ZoomMapping {
        let oneX = device.virtualDeviceSwitchOverVideoZoomFactors.first
            .map { CGFloat(truncating: $0) } ?? 1.0
        return ZoomMapping(oneXRawFactor: oneX,
                           minRaw: device.minAvailableVideoZoomFactor,
                           maxRaw: device.maxAvailableVideoZoomFactor)
    }

    /// Refresh the zoom mapping for `device` and pin it to the main "1x" lens.
    /// Called on `sessionQueue` whenever the active device changes — otherwise a
    /// virtual device would start at raw 1.0 (the ultra-wide / 0.5x).
    /// Safe to call inside a `session.beginConfiguration()` block — device-configuration
    /// locks are independent of session configuration.
    private func updateZoomState(for device: AVCaptureDevice) {
        let map = Self.zoomMapping(for: device)
        zoomStateLock.withLock {
            self._zoomMap = map
            self._currentOptical = 1.0
        }
        do {
            try device.lockForConfiguration()
            let oneX = min(max(map.oneXRawFactor, device.minAvailableVideoZoomFactor),
                           device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = oneX
            device.unlockForConfiguration()
        } catch {
            // best-effort
        }
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
            if let dev = self.videoDeviceInput?.device {
                self.updateZoomState(for: dev)
            }
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

    /// Ramp the active device to an *optical* zoom factor (0.5–3.0 scale).
    /// The optical value is clamped to what the device supports and converted
    /// to a raw `videoZoomFactor` via the active `ZoomMapping`.
    public func setZoom(_ optical: CGFloat) {
        // Update the optical-zoom state synchronously so callers (e.g. the
        // framing monitor) read the *intended* zoom immediately, without
        // waiting for the async ramp on `sessionQueue` to settle.
        let raw: CGFloat = zoomStateLock.withLock {
            let clampedOptical = _zoomMap.clampOptical(optical)
            _currentOptical = clampedOptical
            return _zoomMap.rawFor(optical: clampedOptical)
        }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: raw, withRate: 4.0)
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
