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
    @Published var beforeAfter: (before: CGImage, after: CGImage)?
    @Published var statusBanner: String?
    /// Most recently graded photo, shown as thumbnail on the gallery button.
    @Published var lastThumbnail: CGImage?

    let camera = CameraSession()
    let cv = OnDeviceCV()
    let client = BackendClient()
    let renderer = PhotoRenderer()
    let libraryStore = LibraryStore()

    // Latest preview pixel buffer kept on MainActor for capture-frame use.
    private var latestPreview: CVPixelBuffer?
    private var alignedFrames: Int = 0
    private let alignedFramesNeeded = 9       // ~0.3 second at 30 fps

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

    var isAnalyzing: Bool {
        if case .analyzing = state { return true }
        return false
    }

    // MARK: AI guidance button

    func toggleAIGuidance() {
        switch state {
        case .idle, .done:
            requestGuidance()
        case .analyzing, .aligning:
            cancelGuidance()
        default:
            break  // ignore during capturing/grading
        }
    }

    private func cancelGuidance() {
        guidance = .empty
        alignmentScore = 0
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
                self.state = .aligning(since: Date())
                self.alignedFrames = 0
            } catch {
                flowLog.error("requestGuidance: backend failed — \(error.localizedDescription, privacy: .public)")
                statusBanner = "AI guidance failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }

    private func applyZoom(_ factor: Double) {
        camera.setZoom(CGFloat(max(1.0, min(factor, 3.0))))
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

    private func updateAlignment() {
        guard case .aligning = state else { return }
        let target: AlignmentTarget?
        switch guidance.subjectType {
        case .person:
            if let p = guidance.posePlacement {
                // pose silhouette box: center (x,y), height (h * screen height), width = h / aspect
                // Approximate to a rect for IoU. Aspect lookup from PoseLibrary:
                let aspect = PoseLibrary.templates.first(where: { $0.id == p.id })?.aspect ?? 2.4
                let h = p.height
                let w = h / aspect
                target = AlignmentTarget(kind: .person,
                    box: CGRect(x: p.x - w/2, y: p.y - h/2, width: w, height: h))
            } else { target = nil }
        case .scene:
            if let rect = guidance.sceneTarget {
                target = AlignmentTarget(kind: .scene, box: rect)
            } else { target = nil }
        case .empty:
            target = nil
        }
        guard let t = target else { return }
        let score = AlignmentChecker.score(target: t, state: compose)
        alignmentScore = score
        // 0.65 is realistic for a hand-held box vs an AI-placed box; require
        // CONSECUTIVE aligned frames (reset to 0 on any frame below threshold).
        if score >= 0.65 {
            alignedFrames += 1
            if alignedFrames >= alignedFramesNeeded {
                triggerCapture()
            }
        } else {
            alignedFrames = 0
        }
    }

    private func triggerCapture() {
        guard case .aligning = state else { return }
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
            // idle / done / analyzing / aligning — shoot NOW, drop any in-flight guidance.
            flowGeneration += 1
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
        state = .grading
        let b64 = await Task.detached(priority: .userInitiated) {
            ImageEncoder.downsampledBase64(from: captured, maxSide: 1024, quality: 0.85)
        }.value
        let analysis: SceneAnalysis
        if let b64 {
            do {
                analysis = try await client.grade(imageB64: b64)
            } catch {
                statusBanner = "Color service offline — default preset applied."
                analysis = NeutralPreset.sceneAnalysis
            }
        } else {
            analysis = NeutralPreset.sceneAnalysis
        }
        // Genuine grading-service failure: still save the photo, but tell the
        // truth that it was saved without a grade.
        if analysis.degraded == true {
            statusBanner = "Color grading unavailable — saved without grading"
        }
        let result = await Task.detached(priority: .userInitiated) { [renderer] in
            let graded = CIPipeline.apply(analysis.grade, to: captured)
            let originalCG = renderer.toCGImage(captured)
            let gradedCG   = renderer.toCGImage(graded)
            return (originalCG, gradedCG)
        }.value
        if let before = result.0, let after = result.1 {
            beforeAfter = (before, after)
            lastThumbnail = after
            // Capture lands in the in-app library, not the Camera Roll.
            libraryStore.addCapture(original: before, graded: after, analysis: analysis)
        }
        state = .done
        let generation = flowGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            // If the user started a new flow within 3s, this Task is stale — no-op
            // so it can't yank them out of the new flow.
            guard generation == self.flowGeneration else { return }
            beforeAfter = nil
            guidance = .empty
            alignmentScore = 0
            camera.setZoom(1.0)
            state = .idle
        }
    }
}

public struct RootView: View {
    @StateObject private var vm = RootViewModel()

    // AI button attract-animation state.
    @State private var aiPulse = false       // breathing scale
    @State private var aiRipple = false      // radiating ring
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

                // AI guidance overlay (only while aligning): two-box alignment guide.
                if case .aligning = vm.state, let target = alignmentTargetRect {
                    AlignmentView(target: target,
                                  current: alignmentCurrentRect,
                                  alignment: vm.alignmentScore)
                        .ignoresSafeArea()
                }

                if case .analyzing = vm.state {
                    LoadingOverlay().ignoresSafeArea()
                }

                if let (before, after) = vm.beforeAfter {
                    BeforeAfterReveal(before: before, after: after)
                        .ignoresSafeArea()
                }

                VStack {
                    if let s = vm.statusBanner {
                        Text(s).font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.6)).clipShape(Capsule())
                            .foregroundStyle(.white).padding(.top, 60)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        galleryButton.frame(maxWidth: .infinity)
                        shutterButton
                        aiButton.frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)
                }
                .ignoresSafeArea(edges: .top)
            }
            .onAppear { vm.start() }
            .onDisappear { vm.stop() }
            .fullScreenCover(isPresented: $showLibrary) {
                LibraryView(store: vm.libraryStore) { showLibrary = false }
            }
        }
    }

    private var isBusy: Bool {
        switch vm.state {
        case .capturing, .grading: return true
        default: return false
        }
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
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(Color.white).frame(width: 64, height: 64)
                if isBusy { ProgressView().tint(.black) }
            }
        }
        .disabled(isBusy)
    }

    /// True only when the button should beg for a tap (idle, not busy/analyzing/aligning).
    private var aiIdle: Bool {
        switch vm.state {
        case .idle, .done: return true
        default: return false
        }
    }

    private var aiButton: some View {
        Button(action: { vm.toggleAIGuidance() }) {
            ZStack {
                // Radiating ring — strong "tap me" signal, idle only.
                if aiIdle {
                    Circle()
                        .stroke(Color.cyan, lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .scaleEffect(aiRipple ? 1.9 : 1.0)
                        .opacity(aiRipple ? 0.0 : 0.7)
                }
                // Core button.
                Circle()
                    .fill(LinearGradient(colors: [.cyan, .blue],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .shadow(color: .cyan.opacity(aiIdle ? 0.9 : 0.5),
                            radius: aiIdle && aiPulse ? 18 : 10)
                Image(systemName: aiIcon)
                    .font(.system(size: 22, weight: aiIdle ? .semibold : .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: aiIdle)
            }
            // Gentle breathing scale, idle only.
            .scaleEffect(aiIdle && aiPulse ? 1.10 : 1.0)
        }
        .disabled(isBusy)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                aiPulse = true
            }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                aiRipple = true
            }
        }
    }

    private var galleryButton: some View {
        Button(action: {
            // Open the in-app library — captures land there, not the Camera Roll.
            showLibrary = true
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.6)
                    .frame(width: 48, height: 48)
                if let last = vm.lastThumbnail {
                    Image(decorative: last, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 6)
        }
        .disabled(isBusy)
    }

    private var aiIcon: String {
        switch vm.state {
        case .analyzing, .aligning: return "xmark"
        default: return "sparkles"
        }
    }
}

private extension PhotoRenderer {
    func toCGImage(_ image: CIImage) -> CGImage? {
        SharedCI.context.createCGImage(image, from: image.extent)
    }
}
