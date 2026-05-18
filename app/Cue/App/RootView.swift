// app/Cue/App/RootView.swift
import SwiftUI
import CoreImage
import CoreGraphics
import AVFoundation
import UIKit
import os

private let flowLog = Logger(subsystem: "com.ericsun.cue", category: "flow")

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

@MainActor
final class RootViewModel: ObservableObject, CameraSessionDelegate {
    @Published var compose = ComposeState.initial
    @Published var guidance: AIGuidance = .empty
    @Published var state: FlowState = .idle
    @Published var alignmentScore: Double = 0
    @Published var statusBanner: String?
    /// Most recently graded photo, shown as thumbnail on the gallery button.
    @Published var lastThumbnail: CGImage?

    let camera = CameraSession()
    let cv = OnDeviceCV()
    let client = BackendClient()
    let libraryStore = LibraryStore()

    // Latest preview pixel buffer kept on MainActor for capture-frame use.
    private var latestPreview: CVPixelBuffer?
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

    /// Watchdog that resets a stuck `.capturing` state if the photo callback never arrives.
    private var captureWatchdog: Task<Void, Never>?
    /// Bumped whenever a new flow starts; the 3s post-`.done` reset Task captures
    /// this value and no-ops if it changed (user started a new flow within 3s).
    private var flowGeneration = 0

    init() {
        camera.delegate = self
        camera.configure()
    }

    func start() { camera.start() }
    func stop()  { camera.stop() }
    func flipCamera() { camera.flipCamera() }

    var isAnalyzing: Bool {
        if case .analyzing = state { return true }
        return false
    }

    // MARK: AI guidance button

    func toggleAIGuidance() {
        switch state {
        case .idle, .done:
            requestGuidance()
        case .analyzing, .aligning, .framing:
            cancelGuidance()
        default:
            break  // ignore during capturing/grading
        }
    }

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

    private func requestGuidance() {
        guard let buf = latestPreview else {
            flowLog.error("requestGuidance: no preview frame available")
            statusBanner = "Camera not ready"
            return
        }
        flowLog.info("requestGuidance: start")
        flowGeneration += 1
        state = .analyzing
        let pixelBuffer = buf
        Task { @MainActor in
            let b64Opt: String? = await Task.detached(priority: .userInitiated) {
                ImageEncoder.downsampledBase64(from: pixelBuffer, maxSide: 1024, quality: 0.7)
            }.value
            guard let b64 = b64Opt else {
                flowLog.error("requestGuidance: image encode failed")
                statusBanner = "Image encoding failed"
                state = .idle
                return
            }
            flowLog.info("requestGuidance: encoded \(b64.count) b64 chars, calling backend")
            do {
                let g = try await client.guidance(imageB64: b64)
                flowLog.info("requestGuidance: got guidance subject=\(g.subjectType.rawValue, privacy: .public) zoom=\(g.suggestedZoom)")
                guard case .analyzing = state else {
                    flowLog.info("requestGuidance: state no longer .analyzing — user cancelled, dropping result")
                    return
                }
                // Genuine service failure — tell the truth, don't claim "no subject".
                if g.degraded == true {
                    flowLog.error("requestGuidance: backend returned degraded result")
                    statusBanner = "AI service unavailable, try again"
                    state = .idle
                    return
                }
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
                    startFramingTimeout(generation: flowGeneration)
                    return
                }
                await proceedToAlignment(kind: kind, generation: flowGeneration)
            } catch {
                flowLog.error("requestGuidance: backend failed — \(error.localizedDescription, privacy: .public)")
                statusBanner = "AI guidance failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }

    // MARK: Capture watchdog

    /// Start a watchdog: if a `capturePhoto` callback never arrives (camera
    /// interruption), the UI is stuck at `.capturing` forever. After ~6s, if
    /// state is STILL `.capturing`, recover to `.idle`.
    private func startCaptureWatchdog() {
        captureWatchdog?.cancel()
        captureWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .capturing = self.state {
                flowLog.error("captureWatchdog: photo callback never arrived — recovering to idle")
                self.state = .idle
                self.statusBanner = "Capture failed, try again"
            }
        }
    }

    /// Cancel the capture watchdog (the photo callback arrived).
    private func cancelCaptureWatchdog() {
        captureWatchdog?.cancel()
        captureWatchdog = nil
    }

    // MARK: Alignment monitor (called from preview frame ingest)

    /// Auto-shutter fires when the alignment score reaches this.
    private let alignThreshold = 0.9

    /// The AI target derived from the current guidance, or nil if there is none.
    private func currentTarget() -> AlignmentTarget? {
        switch guidance.subjectType {
        case .person:
            guard let p = guidance.posePlacement else { return nil }
            // pose silhouette box: center (x,y), height fraction, width = h / aspect.
            let aspect = PoseLibrary.templates.first(where: { $0.id == p.id })?.aspect ?? 2.4
            let h = p.height
            let w = h / aspect
            return AlignmentTarget(kind: .person,
                box: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h))
        case .scene:
            guard let rect = guidance.sceneTarget else { return nil }
            return AlignmentTarget(kind: .scene, box: rect)
        case .empty:
            return nil
        }
    }

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
    private func proceedToAlignment(kind: SubjectKind, generation: Int) async {
        // The zoom ramp (camera.setZoom -> device.ramp) takes ~0.5s; wait for it
        // to settle before scoring alignment against a moving subject.
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard generation == flowGeneration else {
            flowLog.info("proceedToAlignment: stale generation — dropping")
            return
        }
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

    private func updateAlignment() {
        guard case .aligning = state else { return }
        guard let t = currentTarget() else { return }
        let score = AlignmentChecker.score(target: t, state: compose)
        alignmentScore = score
        // Require CONSECUTIVE aligned frames (reset to 0 on any frame below).
        if score >= alignThreshold {
            alignedFrames += 1
            if alignedFrames >= alignedFramesNeeded {
                triggerCapture()
            }
        } else {
            alignedFrames = 0
        }
    }

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
                let generation = flowGeneration
                Task { @MainActor [weak self] in
                    await self?.proceedToAlignment(kind: kind, generation: generation)
                }
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
    private func startFramingTimeout(generation: Int) {
        framingTimeout?.cancel()
        framingTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard generation == self.flowGeneration,
                  case .framing = self.state, !self.framingResolving else { return }
            flowLog.info("framing: timed out — proceeding best-effort")
            self.framingResolving = true
            self.statusBanner = nil
            let kind: SubjectKind = self.guidance.subjectType == .person ? .person : .scene
            await self.proceedToAlignment(kind: kind, generation: generation)
        }
    }

    private func triggerCapture() {
        guard case .aligning = state else { return }
        cv.endTracking()
        state = .capturing
        startCaptureWatchdog()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // After alignment: lock focus + expose, settle ~400ms, then shutter.
        camera.captureWithAutofocus()
    }

    // MARK: CameraSessionDelegate

    nonisolated func cameraDidEmitPreview(_ pixelBuffer: CVPixelBuffer) {
        let buf = pixelBuffer
        Task { @MainActor in
            self.latestPreview = buf
            self.cv.ingest(pixelBuffer: buf)
            self.compose = self.cv.state
            self.updateAlignment()
            self.updateFraming()
        }
    }

    nonisolated func cameraDidCapturePhoto(_ ciImage: CIImage) {
        Task { @MainActor in
            await self.process(captured: ciImage)
        }
    }

    nonisolated func cameraDidFail(_ error: Error) {
        Task { @MainActor in
            self.cancelCaptureWatchdog()
            self.statusBanner = "Camera error: \(error.localizedDescription)"
            self.state = .idle
        }
    }

    // MARK: Manual shutter (idle path)

    func shutterTap() {
        switch state {
        case .capturing, .grading:
            return  // genuinely mid-operation
        default:
            // idle / done / analyzing / aligning / framing — shoot NOW, drop any
            // in-flight guidance.
            flowGeneration += 1
            cv.endTracking()
            framingTimeout?.cancel()
            framingResolving = false
            guidance = .empty
            alignmentScore = 0
            state = .capturing
            startCaptureWatchdog()
            camera.capture()
        }
    }

    // MARK: Capture pipeline

    private func process(captured: CIImage) async {
        // The photo callback arrived — the capture watchdog is no longer needed.
        cancelCaptureWatchdog()
        // No auto-grade. The shot is saved to the library as-is; the user
        // triggers AI grading manually in the editor.
        let originalCG = await Task.detached(priority: .userInitiated) {
            SharedCI.cgImage(from: captured)
        }.value
        if let originalCG {
            lastThumbnail = originalCG
            libraryStore.addCapture(original: originalCG)
        } else {
            statusBanner = "Couldn't save the photo"
        }
        state = .done
        let generation = flowGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // If the user started a new flow within the window, this Task is
            // stale — no-op so it can't yank them out of the new flow.
            guard generation == self.flowGeneration else { return }
            guidance = .empty
            alignmentScore = 0
            camera.setZoom(1.0)
            state = .idle
        }
    }
}

public struct RootView: View {
    @StateObject private var vm = RootViewModel()

    @State private var showLibrary = false

    public init() {}

    public var body: some View {
        PermissionGate {
            ZStack {
                CameraPreviewView(session: vm.camera.session)
                    .ignoresSafeArea()

                // Composition aids hide during the loading animation for a clean
                // "AI thinking" screen.
                if !vm.isAnalyzing {
                    CompositionOverlay(state: vm.compose)
                        .ignoresSafeArea()
                }

                // AI guidance overlay (only while aligning): two-ball + arrow guide.
                if case .aligning = vm.state, let target = alignmentTargetRect {
                    AlignmentView(target: target,
                                  current: alignmentCurrentRect,
                                  alignment: vm.alignmentScore)
                        .ignoresSafeArea()
                }

                if case .analyzing = vm.state {
                    LoadingOverlay().ignoresSafeArea()
                }

                // Front/back camera flip — top-right, idle only.
                if canFlip {
                    VStack {
                        HStack {
                            Spacer()
                            flipButton
                        }
                        Spacer()
                    }
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                }

                VStack {
                    if let s = vm.statusBanner {
                        Text(s).font(.footnote)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.top, 60)
                    }
                    Spacer()
                    GlassEffectContainer(spacing: 24) {
                        HStack(spacing: 0) {
                            galleryButton.frame(maxWidth: .infinity)
                            shutterButton
                            aiButton.frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)
                }
                .ignoresSafeArea(edges: .top)
            }
            .onAppear { vm.start() }
            .onDisappear { vm.stop() }
            .fullScreenCover(isPresented: $showLibrary) {
                PhotoBrowser(store: vm.libraryStore) { showLibrary = false }
            }
        }
    }

    private var isBusy: Bool {
        switch vm.state {
        case .capturing, .grading: return true
        default: return false
        }
    }

    /// The flip button only shows when the camera is idle — flipping mid-flow
    /// would invalidate the AI's framing analysis.
    private var canFlip: Bool {
        switch vm.state {
        case .idle, .done: return true
        default: return false
        }
    }

    private var flipButton: some View {
        Button { vm.flipCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    /// Subject kind for the current AI guidance.
    private var alignmentKind: SubjectKind {
        vm.guidance.subjectType == .person ? .person : .scene
    }

    /// AI-placed, screen-fixed target box, normalized 0..1 top-left. nil if no guidance.
    private var alignmentTargetRect: CGRect? {
        let g = vm.guidance
        if let p = g.posePlacement {
            let aspect = PoseLibrary.templates.first(where: { $0.id == p.id })?.aspect ?? 2.4
            let h = p.height
            let w = h / aspect
            return CGRect(x: p.x - w/2, y: p.y - h/2, width: w, height: h)
        }
        return g.sceneTarget
    }

    /// Live-detected subject box, normalized 0..1 top-left. nil if no subject detected.
    private var alignmentCurrentRect: CGRect? {
        AlignmentChecker.detectedBox(kind: alignmentKind, state: vm.compose)
    }

    private var shutterButton: some View {
        Button(action: {
            vm.shutterTap()
        }) {
            ZStack {
                // Classic white camera shutter ring — an established affordance,
                // intentionally NOT glass.
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(Color.white).frame(width: 66, height: 66)
                    .shadow(color: .black.opacity(0.35), radius: 6)
                if isBusy { ProgressView().tint(.black) }
            }
        }
        .disabled(isBusy)
    }


    private var aiButton: some View {
        Button(action: { vm.toggleAIGuidance() }) {
            Image(systemName: aiIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .glassEffect(.regular.tint(.cyan).interactive(), in: .circle)
        }
        .disabled(isBusy)
    }

    private var galleryButton: some View {
        Button(action: {
            // Open the in-app library — captures land there, not the Camera Roll.
            showLibrary = true
        }) {
            ZStack {
                if let last = vm.lastThumbnail {
                    Image(decorative: last, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .frame(width: 54, height: 54)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .disabled(isBusy)
    }

    private var aiIcon: String {
        switch vm.state {
        case .analyzing, .aligning, .framing: return "xmark"
        default: return "viewfinder"  // AI composition framing
        }
    }
}
