# Auto-Zoom to Best Composition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before the pan-alignment step, automatically zoom the camera so the subject reaches the AI's target framing size; extend the zoom range to 0.5x–3x.

**Architecture:** Two pure, unit-tested cores — `ZoomMapping` (optical↔raw zoom conversion) and `AlignmentChecker` zoom math. `CameraSession` switches to a virtual multi-camera device and exposes optical zoom. `RootViewModel` computes the precise zoom from the locked subject, applies it before alignment, and adds a `.framing` state that prompts the user to step back/closer when zoom alone can't reach the target size.

**Tech Stack:** Swift, AVFoundation, Vision, SwiftUI, Swift Testing (`import Testing`). Xcode project `app/Cue.xcodeproj`, scheme `Cue`, test target `CueTests`.

**Spec:** `docs/superpowers/specs/2026-05-18-auto-zoom-composition-design.md`

**Conventions:**
- All work commits directly to `main` (no feature branch).
- Every commit message ends with the `Co-Authored-By` footer shown in the commit steps.
- Test/build runs use the iPhone 17 simulator; adjust the device name if unavailable (`xcrun simctl list devices available`).
- xcodebuild runs are slow (~1–3 min each) — this is expected.

---

### Task 1: `ZoomMapping` value type (TDD)

Pure value type converting between *optical* zoom (the 0.5x–3x scale users and the AI think in) and the device's raw `videoZoomFactor`.

**Files:**
- Create: `app/CueTests/ZoomTests.swift`
- Modify: `app/Cue.xcodeproj/project.pbxproj` (register the new test file)
- Modify: `app/Cue/Camera/CameraSession.swift` (add the struct)

- [ ] **Step 1: Write the failing test file**

Create `app/CueTests/ZoomTests.swift`:

```swift
// app/CueTests/ZoomTests.swift
import Testing
import Foundation
import CoreGraphics
import Vision
@testable import Cue

@Suite("ZoomMapping") struct ZoomMappingTests {

    @Test func singleCamMapping() {
        // Single-wide camera: raw 1x == optical 1x, no 0.5x.
        let m = ZoomMapping(oneXRawFactor: 1.0, minRaw: 1.0, maxRaw: 120.0)
        #expect(m.minOptical == 1.0)
        #expect(m.maxOptical == 3.0)
        #expect(m.rawFor(optical: 2.0) == 2.0)
        #expect(m.rawFor(optical: 0.2) == 1.0)   // clamped up to minOptical
        #expect(m.rawFor(optical: 9.0) == 3.0)   // clamped down to maxOptical
    }

    @Test func dualWideMapping() {
        // Virtual dual-wide: raw 2.0 is the main "1x" lens, raw 1.0 is 0.5x.
        let m = ZoomMapping(oneXRawFactor: 2.0, minRaw: 1.0, maxRaw: 12.0)
        #expect(m.minOptical == 0.5)
        #expect(m.maxOptical == 3.0)
        #expect(m.rawFor(optical: 0.5) == 1.0)
        #expect(m.rawFor(optical: 1.0) == 2.0)
        #expect(m.rawFor(optical: 3.0) == 6.0)
        #expect(m.rawFor(optical: 0.1) == 1.0)   // clamp to 0.5x -> raw 1.0
        #expect(m.rawFor(optical: 9.0) == 6.0)   // clamp to 3.0x -> raw 6.0
    }

    @Test func clampOptical() {
        let m = ZoomMapping(oneXRawFactor: 2.0, minRaw: 1.0, maxRaw: 12.0)
        #expect(m.clampOptical(0.1) == 0.5)
        #expect(m.clampOptical(5.0) == 3.0)
        #expect(m.clampOptical(1.5) == 1.5)
    }
}
```

- [ ] **Step 2: Register the test file in the Xcode project**

The project does not use synchronized file groups, so `project.pbxproj` must be edited. Run this script from the repo root:

```bash
python3 - <<'PY'
p = "app/Cue.xcodeproj/project.pbxproj"
s = open(p).read()
BF = "A1A1A1A1A1A1A1A1A1A10001"   # PBXBuildFile UUID for ZoomTests.swift
FR = "A1A1A1A1A1A1A1A1A1A10002"   # PBXFileReference UUID for ZoomTests.swift

a1 = "EECF839D297D6370BBA83BF6 /* GradeParamsTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 45C1BF76790D7ECCD10B062B /* GradeParamsTests.swift */; };"
a2 = '45C1BF76790D7ECCD10B062B /* GradeParamsTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GradeParamsTests.swift; sourceTree = "<group>"; };'
a3 = "45C1BF76790D7ECCD10B062B /* GradeParamsTests.swift */,"
a4 = "EECF839D297D6370BBA83BF6 /* GradeParamsTests.swift in Sources */,"

assert all(x in s for x in (a1, a2, a3, a4)), "anchor not found — inspect project.pbxproj"

s = s.replace(a1, a1 + "\n\t\t" + f"{BF} /* ZoomTests.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FR} /* ZoomTests.swift */; }};")
s = s.replace(a2, a2 + "\n\t\t" + f'{FR} /* ZoomTests.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ZoomTests.swift; sourceTree = "<group>"; }};')
s = s.replace(a3, a3 + "\n\t\t\t\t" + f"{FR} /* ZoomTests.swift */,", 1)
s = s.replace(a4, a4 + "\n\t\t\t\t" + f"{BF} /* ZoomTests.swift in Sources */,", 1)
open(p, "w").write(s)
print("registered ZoomTests.swift")
PY
```

Expected output: `registered ZoomTests.swift`

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
cd app && xcodebuild test -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CueTests/ZoomMappingTests 2>&1 | tail -25
```
Expected: BUILD FAILURE — `cannot find 'ZoomMapping' in scope` (the type does not exist yet).

- [ ] **Step 4: Implement `ZoomMapping`**

In `app/Cue/Camera/CameraSession.swift`, insert this struct immediately after the `CameraError` enum (before `public final class CameraSession`):

```swift
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
cd app && xcodebuild test -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CueTests/ZoomMappingTests 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **` — all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/CueTests/ZoomTests.swift app/Cue.xcodeproj/project.pbxproj app/Cue/Camera/CameraSession.swift
git commit -m "$(cat <<'EOF'
feat(camera): ZoomMapping — optical<->raw zoom conversion

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `AlignmentChecker` zoom math (TDD)

Pure functions that measure the live subject's size and compute the optical zoom needed to reach the AI target size.

**Files:**
- Modify: `app/CueTests/ZoomTests.swift` (add two suites)
- Modify: `app/Cue/Compose/AlignmentChecker.swift`

- [ ] **Step 1: Write the failing tests**

Append to `app/CueTests/ZoomTests.swift` (after the `ZoomMappingTests` suite):

```swift
@Suite("NeededOpticalZoom") struct NeededOpticalZoomTests {

    @Test func personHeightMatch() {
        // detected height 0.3, target height 0.6 -> needs 2x.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0.15, height: 0.3),
            currentOptical: 1.0, calibration: 1.0)
        #expect(abs(z - 2.0) < 1e-9)
    }

    @Test func personRespectsCurrentOptical() {
        // Same ratio but already at 1.5x -> 3.0x.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0.15, height: 0.3),
            currentOptical: 1.5, calibration: 1.0)
        #expect(abs(z - 3.0) < 1e-9)
    }

    @Test func personCalibration() {
        // calibration 0.85: 1.0 * 0.6 * 0.85 / 0.3 = 1.7.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0.15, height: 0.3),
            currentOptical: 1.0, calibration: 0.85)
        #expect(abs(z - 1.7) < 1e-9)
    }

    @Test func sceneAreaMatch() {
        // target area 0.24, detected area 0.06 -> sqrt(4) = 2x.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .scene,
            targetSize: CGSize(width: 0.4, height: 0.6),
            detectedSize: CGSize(width: 0.2, height: 0.3),
            currentOptical: 1.0)
        #expect(abs(z - 2.0) < 1e-9)
    }

    @Test func degenerateDetectedReturnsCurrent() {
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0, height: 0),
            currentOptical: 1.3)
        #expect(z == 1.3)
    }
}

@Suite("MeasuredSubject") struct MeasuredSubjectTests {

    @Test func personFromBodyPose() {
        // Joints span x 0.4..0.5 (w 0.1), y 0.1..0.9 (h 0.8).
        let joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [
            .nose: CGPoint(x: 0.5, y: 0.9),
            .leftAnkle: CGPoint(x: 0.4, y: 0.1),
        ]
        let state = ComposeState(subjectBox: nil, faceBoxes: [],
                                 horizonDegrees: 0,
                                 bodyPose: BodyPose(joints: joints, confidence: 0.9),
                                 trackedBox: nil)
        let m = AlignmentChecker.measuredSubject(kind: .person, state: state)
        #expect(m?.comparable == true)
        #expect(abs((m?.size.width ?? -1) - 0.1) < 1e-6)
        #expect(abs((m?.size.height ?? -1) - 0.8) < 1e-6)
    }

    @Test func personFaceFallbackNotComparable() {
        let state = ComposeState(subjectBox: nil,
                                 faceBoxes: [CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.25)],
                                 horizonDegrees: 0, bodyPose: .none, trackedBox: nil)
        let m = AlignmentChecker.measuredSubject(kind: .person, state: state)
        #expect(m?.comparable == false)
        #expect(abs((m?.size.height ?? -1) - 0.25) < 1e-6)
    }

    @Test func personNothingDetected() {
        let m = AlignmentChecker.measuredSubject(kind: .person, state: .initial)
        #expect(m == nil)
    }

    @Test func sceneFromSubjectBox() {
        let state = ComposeState(subjectBox: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4),
                                 faceBoxes: [], horizonDegrees: 0,
                                 bodyPose: .none, trackedBox: nil)
        let m = AlignmentChecker.measuredSubject(kind: .scene, state: state)
        #expect(m?.comparable == true)
        #expect(abs((m?.size.width ?? -1) - 0.3) < 1e-6)
    }

    @Test func sceneNothingDetected() {
        let m = AlignmentChecker.measuredSubject(kind: .scene, state: .initial)
        #expect(m == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd app && xcodebuild test -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CueTests/NeededOpticalZoom -only-testing:CueTests/MeasuredSubject 2>&1 | tail -25
```
Expected: BUILD FAILURE — `neededOpticalZoom` / `measuredSubject` not found.

- [ ] **Step 3: Implement the functions**

In `app/Cue/Compose/AlignmentChecker.swift`, add these members inside the `enum AlignmentChecker` (after the `maxAlignDistance` declaration, before `score`):

```swift
    /// Joint-bounding-box height as a fraction of the true pose silhouette
    /// height. Vision's body-pose joints span roughly nose-to-ankle, shorter
    /// than the SF Symbol silhouette the pose target is sized against.
    /// 1.0 = no correction; tune on a real device.
    public static let poseHeightCalibration: Double = 1.0

    /// The live subject's size in normalized [0..1] viewfinder space, for zoom
    /// sizing. `comparable` is false when the measurement can't be matched
    /// against the AI target size (a face box vs a full-body pose height) —
    /// callers should fall back to the backend's suggested zoom in that case.
    /// Does NOT use `trackedBox`: zoom sizing happens before an alignment session.
    public static func measuredSubject(kind: SubjectKind,
                                       state: ComposeState) -> (size: CGSize, comparable: Bool)? {
        switch kind {
        case .person:
            if let pose = boundingBox(of: state.bodyPose.joints) {
                return (pose.size, true)
            } else if let face = state.faceBoxes.first {
                return (face.size, false)
            } else {
                return nil
            }
        case .scene:
            if let s = state.subjectBox {
                return (s.size, true)
            }
            return nil
        }
    }

    /// Optical zoom needed so the detected subject reaches the AI target size.
    /// Person: matched by height (with `poseHeightCalibration`). Scene: matched
    /// by area. Returns `currentOptical` unchanged when `detected` is degenerate.
    public static func neededOpticalZoom(kind: SubjectKind,
                                         targetSize: CGSize,
                                         detectedSize: CGSize,
                                         currentOptical: Double,
                                         calibration: Double = poseHeightCalibration) -> Double {
        switch kind {
        case .person:
            guard detectedSize.height > 0 else { return currentOptical }
            return currentOptical * Double(targetSize.height) * calibration
                 / Double(detectedSize.height)
        case .scene:
            let targetArea = Double(targetSize.width * targetSize.height)
            let detectedArea = Double(detectedSize.width * detectedSize.height)
            guard detectedArea > 0, targetArea > 0 else { return currentOptical }
            return currentOptical * (targetArea / detectedArea).squareRoot()
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd app && xcodebuild test -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CueTests/NeededOpticalZoom -only-testing:CueTests/MeasuredSubject 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **` — all 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/CueTests/ZoomTests.swift app/Cue/Compose/AlignmentChecker.swift
git commit -m "$(cat <<'EOF'
feat(compose): measuredSubject + neededOpticalZoom for auto-zoom sizing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `CameraSession` — virtual multi-camera device + optical zoom

Switch the back camera to a virtual multi-camera device (ultra-wide … tele as one continuous range) and make `setZoom` work in optical terms. AVFoundation/hardware code — verified by compilation here, by device testing in Task 5.

**Files:**
- Modify: `app/Cue/Camera/CameraSession.swift`

- [ ] **Step 1: Add zoom-state storage**

In `app/Cue/Camera/CameraSession.swift`, find:

```swift
    /// Which camera is active. Mutated only on `sessionQueue`.
    private var currentPosition: AVCaptureDevice.Position = .back
```

Replace with:

```swift
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
```

- [ ] **Step 2: Replace `makeInput` with multi-camera device selection**

Find:

```swift
    /// Build a camera input for the given position.
    private func makeInput(position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noBackCamera
        }
        return try AVCaptureDeviceInput(device: device)
    }
```

Replace with:

```swift
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
```

- [ ] **Step 3: Initialize zoom state in `configure()`**

Find (inside `configure()`):

```swift
                self.session.addInput(input)
                self.videoDeviceInput = input
                self.currentPosition = .back
```

Replace with:

```swift
                self.session.addInput(input)
                self.videoDeviceInput = input
                self.currentPosition = .back
                self.updateZoomState(for: input.device)
```

- [ ] **Step 4: Refresh zoom state in `flipCamera()`**

Find (inside `flipCamera()`):

```swift
            self.applyPortraitRotation()
            self.session.commitConfiguration()
        }
    }
```

Replace with:

```swift
            self.applyPortraitRotation()
            if let dev = self.videoDeviceInput?.device {
                self.updateZoomState(for: dev)
            }
            self.session.commitConfiguration()
        }
    }
```

- [ ] **Step 5: Rewrite `setZoom` to take an optical factor**

Find:

```swift
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
```

Replace with:

```swift
    /// Ramp the active device to an *optical* zoom factor (0.5–3.0 scale).
    /// The optical value is clamped to what the device supports and converted
    /// to a raw `videoZoomFactor` via the active `ZoomMapping`.
    public func setZoom(_ optical: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            let map = self.zoomStateLock.withLock { self._zoomMap }
            let clampedOptical = map.clampOptical(optical)
            let raw = clampedOptical * map.oneXRawFactor
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: raw, withRate: 4.0)
                device.unlockForConfiguration()
                self.zoomStateLock.withLock { self._currentOptical = clampedOptical }
            } catch {
                // best-effort; ignore
            }
        }
    }
```

- [ ] **Step 6: Verify the project compiles**

Run:
```bash
cd app && xcodebuild build -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add app/Cue/Camera/CameraSession.swift
git commit -m "$(cat <<'EOF'
feat(camera): virtual multi-camera device + optical-scale setZoom

Use builtInTripleCamera/DualWideCamera for the back camera so zoom
reaches 0.5x; setZoom now takes an optical factor and converts via
ZoomMapping. Pins virtual devices to the 1x lens so idle preview is
not ultra-wide.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `RootView.swift` — `.framing` state, precise zoom, step-back/closer

Compute the precise zoom from the locked subject, apply it before alignment, and add the `.framing` state. AVFoundation/UIKit-coupled — verified by compilation here, by device testing in Task 5.

**Files:**
- Modify: `app/Cue/App/RootView.swift`

- [ ] **Step 1: Add the `.framing` flow state**

Find:

```swift
public enum FlowState: Equatable {
    case idle
    case analyzing
    case aligning(since: Date)
    case capturing
    case grading
    case done
}
```

Replace with:

```swift
public enum FlowState: Equatable {
    case idle
    case analyzing
    /// Zoom alone can't reach the AI target size — the user is being guided to
    /// step back / closer. Transient: skipped entirely when zoom is in range.
    case framing(since: Date)
    case aligning(since: Date)
    case capturing
    case grading
    case done
}
```

- [ ] **Step 2: Add `.framing` bookkeeping fields**

Find:

```swift
    private var alignedFrames: Int = 0
    private let alignedFramesNeeded = 9       // ~0.3 second at 30 fps
```

Replace with:

```swift
    private var alignedFrames: Int = 0
    private let alignedFramesNeeded = 9       // ~0.3 second at 30 fps

    /// `.framing` bookkeeping: consecutive in-range frames seen, the resolve
    /// guard (prevents double `proceedToAlignment`), and the step-back timeout.
    private var framingStableFrames = 0
    private let framingStableNeeded = 3
    private var framingResolving = false
    private var framingTimeout: Task<Void, Never>?
    /// Small tolerance so a value exactly on the optical bound counts in-range.
    private let zoomRangeEpsilon = 0.001
```

- [ ] **Step 3: Replace `requestGuidance`'s zoom + alignment tail**

Find this block inside `requestGuidance` (from `self.guidance = g` through the end of the `do` body):

```swift
                self.guidance = g
                applyZoom(g.suggestedZoom)
                if g.subjectType == .empty {
                    statusBanner = "No subject detected"
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if statusBanner == "No subject detected" { statusBanner = nil }
                    }
                    state = .idle
                    return
                }
                // The zoom ramp (camera.setZoom -> device.ramp) takes ~0.5s; wait
                // for it to settle before scoring alignment IoU against a moving subject.
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard case .analyzing = state else {
                    flowLog.info("requestGuidance: cancelled during zoom-ramp settle, dropping result")
                    return
                }
                // Composition already good? Skip the aligning step and shoot now.
                if let t = currentTarget(),
                   AlignmentChecker.score(target: t, state: compose) >= alignThreshold {
                    flowLog.info("requestGuidance: already well-composed — capturing immediately")
                    self.state = .capturing
                    startCaptureWatchdog()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    camera.captureWithAutofocus()
                    return
                }
                // Otherwise, lock onto the subject so the alignment ball tracks
                // it smoothly (saliency re-detection jitters; tracking follows).
                let kind: SubjectKind = g.subjectType == .person ? .person : .scene
                self.cv.beginTracking(seed: AlignmentChecker.trackingSeed(kind: kind, state: self.compose))
                self.state = .aligning(since: Date())
                self.alignedFrames = 0
```

Replace with:

```swift
                self.guidance = g
                if g.subjectType == .empty {
                    statusBanner = "No subject detected"
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if statusBanner == "No subject detected" { statusBanner = nil }
                    }
                    state = .idle
                    return
                }
                let kind: SubjectKind = g.subjectType == .person ? .person : .scene
                // Precisely zoom so the subject reaches the AI target size.
                let needed = neededZoom(kind: kind)
                let minO = Double(camera.minOpticalZoom)
                let maxO = Double(camera.maxOpticalZoom)
                camera.setZoom(CGFloat(needed))  // setZoom clamps internally
                if needed < minO - zoomRangeEpsilon || needed > maxO + zoomRangeEpsilon {
                    // Zoom alone can't reach the target size — guide the user.
                    flowLog.info("requestGuidance: zoom out of range (\(needed)) — entering .framing")
                    self.framingStableFrames = 0
                    self.framingResolving = false
                    self.state = .framing(since: Date())
                    updateFramingBanner(needed: needed, minO: minO, maxO: maxO)
                    startFramingTimeout()
                    return
                }
                await proceedToAlignment(kind: kind)
```

- [ ] **Step 4: Delete the now-unused `applyZoom` helper**

Find and delete:

```swift
    private func applyZoom(_ factor: Double) {
        camera.setZoom(CGFloat(max(1.0, min(factor, 3.0))))
    }

```

- [ ] **Step 5: Add `neededZoom` and `proceedToAlignment`**

Insert these two methods immediately after `currentTarget()` (after its closing brace, before `updateAlignment`):

```swift
    /// The optical zoom that would bring the live subject to the AI target
    /// size. Falls back to the backend's suggested zoom when the on-device
    /// measurement isn't comparable to the target (e.g. only a face detected).
    private func neededZoom(kind: SubjectKind) -> Double {
        guard let target = currentTarget(),
              let measured = AlignmentChecker.measuredSubject(kind: kind, state: compose),
              measured.comparable else {
            return guidance.suggestedZoom
        }
        return AlignmentChecker.neededOpticalZoom(
            kind: kind,
            targetSize: target.box.size,
            detectedSize: measured.size,
            currentOptical: Double(camera.currentOpticalZoom))
    }

    /// Shared tail used by both the in-range zoom path and a resolved `.framing`
    /// step: wait for the zoom ramp to settle, then either capture (already
    /// composed) or begin the pan-alignment session.
    private func proceedToAlignment(kind: SubjectKind) async {
        // The zoom ramp (camera.setZoom -> device.ramp) takes ~0.5s; wait for it
        // to settle before scoring alignment against a moving subject.
        try? await Task.sleep(nanoseconds: 600_000_000)
        switch state {
        case .analyzing, .framing: break
        default:
            flowLog.info("proceedToAlignment: state changed — dropping")
            return
        }
        // Composition already good? Skip the aligning step and shoot now.
        if let t = currentTarget(),
           AlignmentChecker.score(target: t, state: compose) >= alignThreshold {
            flowLog.info("proceedToAlignment: already well-composed — capturing immediately")
            state = .capturing
            startCaptureWatchdog()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            camera.captureWithAutofocus()
            return
        }
        // Otherwise, lock onto the subject so the alignment ball tracks it
        // smoothly (saliency re-detection jitters; tracking follows).
        cv.beginTracking(seed: AlignmentChecker.trackingSeed(kind: kind, state: compose))
        state = .aligning(since: Date())
        alignedFrames = 0
    }
```

- [ ] **Step 6: Add the `.framing` monitor**

Insert these three methods immediately after `updateAlignment()` (after its closing brace, before `triggerCapture`):

```swift
    // MARK: Framing monitor (called from preview frame ingest)

    /// While `.framing`, re-measure each frame: once the needed zoom comes back
    /// into range (the user has stepped the right distance), apply it and move
    /// on to alignment.
    private func updateFraming() {
        guard case .framing = state, !framingResolving else { return }
        let kind: SubjectKind = guidance.subjectType == .person ? .person : .scene
        let needed = neededZoom(kind: kind)
        let minO = Double(camera.minOpticalZoom)
        let maxO = Double(camera.maxOpticalZoom)
        if needed >= minO - zoomRangeEpsilon && needed <= maxO + zoomRangeEpsilon {
            framingStableFrames += 1
            if framingStableFrames >= framingStableNeeded {
                framingResolving = true
                framingTimeout?.cancel()
                statusBanner = nil
                camera.setZoom(CGFloat(needed))
                Task { @MainActor in await proceedToAlignment(kind: kind) }
            }
        } else {
            framingStableFrames = 0
            updateFramingBanner(needed: needed, minO: minO, maxO: maxO)
        }
    }

    /// Show the step-back / step-closer hint for an out-of-range zoom.
    private func updateFramingBanner(needed: Double, minO: Double, maxO: Double) {
        if needed < minO {
            statusBanner = "后退一点"
        } else if needed > maxO {
            statusBanner = "靠近一点"
        }
    }

    /// If `.framing` lasts too long (user never moves), proceed best-effort with
    /// the clamped zoom rather than stalling forever.
    private func startFramingTimeout() {
        framingTimeout?.cancel()
        framingTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard case .framing = self.state, !self.framingResolving else { return }
            flowLog.info("framing: timed out — proceeding best-effort")
            self.framingResolving = true
            self.statusBanner = nil
            let kind: SubjectKind = self.guidance.subjectType == .person ? .person : .scene
            await self.proceedToAlignment(kind: kind)
        }
    }
```

- [ ] **Step 7: Drive `updateFraming` from preview frames**

Find:

```swift
            self.latestPreview = buf
            self.cv.ingest(pixelBuffer: buf)
            self.compose = self.cv.state
            self.updateAlignment()
```

Replace with:

```swift
            self.latestPreview = buf
            self.cv.ingest(pixelBuffer: buf)
            self.compose = self.cv.state
            self.updateAlignment()
            self.updateFraming()
```

- [ ] **Step 8: Handle `.framing` in cancel + manual shutter**

Find:

```swift
        case .analyzing, .aligning:
            cancelGuidance()
```

Replace with:

```swift
        case .analyzing, .aligning, .framing:
            cancelGuidance()
```

Find:

```swift
    private func cancelGuidance() {
        cv.endTracking()
        guidance = .empty
        alignmentScore = 0
        state = .idle
        camera.setZoom(1.0)
    }
```

Replace with:

```swift
    private func cancelGuidance() {
        cv.endTracking()
        framingTimeout?.cancel()
        framingResolving = false
        guidance = .empty
        alignmentScore = 0
        statusBanner = nil
        state = .idle
        camera.setZoom(1.0)
    }
```

Find (inside `shutterTap`):

```swift
        default:
            // idle / done / analyzing / aligning — shoot NOW, drop any in-flight guidance.
            flowGeneration += 1
            cv.endTracking()
            guidance = .empty
```

Replace with:

```swift
        default:
            // idle / done / analyzing / aligning / framing — shoot NOW, drop any
            // in-flight guidance.
            flowGeneration += 1
            cv.endTracking()
            framingTimeout?.cancel()
            framingResolving = false
            guidance = .empty
```

- [ ] **Step 9: Show the `xmark` AI icon during `.framing`**

Find:

```swift
        case .analyzing, .aligning: return "xmark"
```

Replace with:

```swift
        case .analyzing, .aligning, .framing: return "xmark"
```

- [ ] **Step 10: Verify the project compiles**

Run:
```bash
cd app && xcodebuild build -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`.

> Note: `FlowState` is `Equatable` and gains `.framing(since: Date())`; the
> compiler synthesizes equality. No other `switch` over `FlowState` needs a new
> case — `isBusy`, `canFlip`, and `isAnalyzing` all use `default`, which
> correctly treats `.framing` as non-busy, non-flippable, non-analyzing.

- [ ] **Step 11: Commit**

```bash
git add app/Cue/App/RootView.swift
git commit -m "$(cat <<'EOF'
feat(flow): auto-zoom to AI target size before alignment

Compute the precise optical zoom from the locked subject and apply it
before the pan-alignment step. Add a .framing state that prompts the
user to step back/closer when zoom alone can't reach the target size.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Full integration verification

**Files:** none modified.

- [ ] **Step 1: Run the full test suite**

Run:
```bash
cd app && xcodebuild test -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` — the 13 new tests plus the pre-existing `CIPipeline` and `GradeParams` tests all pass.

- [ ] **Step 2: Manual device test checklist**

The camera behavior cannot be unit-tested. On a physical iPhone with a multi-camera back camera, verify:

- [ ] Idle preview shows the main 1x lens (not the ultra-wide 0.5x).
- [ ] Subject smaller than target → app zooms in; alignment proceeds normally.
- [ ] Subject larger than target, beyond 0.5x → `.framing` state shows the "后退一点" banner; walking back ends `.framing` and proceeds to alignment.
- [ ] Subject far smaller than target, beyond 3x → "靠近一点" banner; walking closer resolves it.
- [ ] During `.framing`, the AI button shows `xmark` and cancels back to idle (zoom resets, banner clears).
- [ ] `.framing` times out after ~8s of no movement and proceeds anyway.
- [ ] Flip to the front camera and back: front works (1x floor, no 0.5x), back returns to the multi-cam device.
- [ ] On a single-camera device (e.g. iPhone SE) the app still works; zoom floor is 1x.

- [ ] **Step 3: Final commit (if Step 2 surfaced calibration tuning)**

If on-device testing shows the person-zoom is consistently off, tune `AlignmentChecker.poseHeightCalibration` and commit:

```bash
git add app/Cue/Compose/AlignmentChecker.swift
git commit -m "$(cat <<'EOF'
fix(compose): tune poseHeightCalibration from on-device testing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- §2 target size already in `AIGuidance` → Task 4 `neededZoom` uses `currentTarget().box.size`. ✓
- §3 zoom geometry (person height / scene area / calibration / current optical) → Task 2 `neededOpticalZoom`. ✓
- §4.1 virtual multi-camera device → Task 3 `bestDevice`. ✓
- §4.2 `ZoomMapping` from switchover factors → Task 1 + Task 3 `zoomMapping`. ✓
- §4.3 `setZoom` optical, `currentOpticalZoom`/`min`/`maxOpticalZoom`, idle = 1x main lens → Task 3. ✓
- §5.1 `FlowState.framing` → Task 4 Step 1. ✓
- §5.2 branch + `proceedToAlignment` extraction → Task 4 Steps 3, 5. ✓
- §5.3 `updateFraming`, debounce, banners, 8s timeout → Task 4 Step 6. ✓
- §5.4 cancel/toggle/shutter/`aiIcon` wiring → Task 4 Steps 8, 9. ✓
- §6 `measuredSubject`, `neededOpticalZoom`, `poseHeightCalibration` → Task 2. ✓
- §8 unit tests (`ZoomMapping`, `neededOpticalZoom`, `measuredSubject`) + manual checklist → Tasks 1, 2, 5. ✓

**Type consistency:** `ZoomMapping(oneXRawFactor:minRaw:maxRaw:)`, `rawFor(optical:)`, `clampOptical(_:)`, `minOptical`, `maxOptical` consistent across Tasks 1 & 3. `measuredSubject(kind:state:) -> (size:comparable:)?` and `neededOpticalZoom(kind:targetSize:detectedSize:currentOptical:calibration:)` consistent across Tasks 2 & 4. `camera.currentOpticalZoom/minOpticalZoom/maxOpticalZoom` defined in Task 3, used in Task 4. `proceedToAlignment(kind:)` / `neededZoom(kind:)` / `updateFraming` / `updateFramingBanner` / `startFramingTimeout` consistent within Task 4.

**Placeholder scan:** No TBD/TODO. Every code step shows complete code; every command shows expected output. `poseHeightCalibration = 1.0` is a real, working default (Task 5 Step 3 covers later tuning).
