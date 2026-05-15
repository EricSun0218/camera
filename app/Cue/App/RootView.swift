// app/Cue/App/RootView.swift
import SwiftUI
import CoreImage
import CoreGraphics
import AVFoundation
import UIKit

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

    let camera = CameraSession()
    let cv = OnDeviceCV()
    let client = BackendClient()
    let renderer = PhotoRenderer()

    // Latest preview pixel buffer kept on MainActor for capture-frame use.
    private var latestPreview: CVPixelBuffer?
    private var alignedFrames: Int = 0
    private var alignmentTimeoutTask: Task<Void, Never>?
    private let alignedFramesNeeded = 30      // ~1 second at 30 fps
    private let alignmentTimeoutSeconds: TimeInterval = 30

    init() {
        camera.delegate = self
        camera.configure()
    }

    func start() { camera.start() }
    func stop()  { camera.stop() }

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
        alignmentTimeoutTask?.cancel()
        alignmentTimeoutTask = nil
        guidance = .empty
        alignmentScore = 0
        state = .idle
        camera.setZoom(1.0)
    }

    private func requestGuidance() {
        guard let buf = latestPreview else { return }
        state = .analyzing
        let pixelBuffer = buf
        Task { @MainActor in
            let b64Opt: String? = await Task.detached(priority: .userInitiated) {
                ImageEncoder.downsampledBase64(from: pixelBuffer, maxSide: 1024, quality: 0.7)
            }.value
            guard let b64 = b64Opt else {
                statusBanner = "图像编码失败"
                state = .idle
                return
            }
            do {
                let g = try await client.guidance(imageB64: b64)
                guard case .analyzing = state else { return }  // user cancelled
                self.guidance = g
                applyZoom(g.suggestedZoom)
                if g.subjectType == .empty {
                    statusBanner = "暂无主体可识别"
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if statusBanner == "暂无主体可识别" { statusBanner = nil }
                    }
                    state = .idle
                    return
                }
                self.state = .aligning(since: Date())
                self.alignedFrames = 0
                self.startAlignmentTimeout()
            } catch {
                statusBanner = "AI 指导服务暂时不可达"
                state = .idle
            }
        }
    }

    private func applyZoom(_ factor: Double) {
        camera.setZoom(CGFloat(max(1.0, min(factor, 3.0))))
    }

    private func startAlignmentTimeout() {
        alignmentTimeoutTask?.cancel()
        alignmentTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.alignmentTimeoutSeconds * 1_000_000_000))
            guard case .aligning = self.state else { return }
            self.statusBanner = "对齐超时,可重试"
            self.cancelGuidance()
        }
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
        if score >= 0.85 {
            alignedFrames += 1
            if alignedFrames >= alignedFramesNeeded {
                triggerCapture()
            }
        } else {
            alignedFrames = max(0, alignedFrames - 1)
        }
    }

    private func triggerCapture() {
        guard case .aligning = state else { return }
        alignmentTimeoutTask?.cancel()
        state = .capturing
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        camera.capture()
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
            self.statusBanner = "相机错误: \(error.localizedDescription)"
            self.state = .idle
        }
    }

    // MARK: Manual shutter (idle path)

    func shutterTap() {
        switch state {
        case .idle, .done:
            state = .capturing
            camera.capture()
        default:
            break
        }
    }

    // MARK: Capture pipeline

    private func process(captured: CIImage) async {
        state = .grading
        let b64 = await Task.detached(priority: .userInitiated) {
            ImageEncoder.downsampledBase64(from: captured, maxSide: 1024, quality: 0.85)
        }.value
        let analysis: SceneAnalysis
        if let b64 {
            do {
                analysis = try await client.grade(imageB64: b64)
            } catch {
                statusBanner = "调色服务离线,已使用默认参数。"
                analysis = NeutralPreset.sceneAnalysis
            }
        } else {
            analysis = NeutralPreset.sceneAnalysis
        }
        let result = await Task.detached(priority: .userInitiated) { [renderer] in
            let graded = CIPipeline.apply(analysis.grade, to: captured)
            let originalCG = renderer.toCGImage(captured)
            let gradedCG   = renderer.toCGImage(graded)
            let jpegData   = try? renderer.renderToJPEG(graded)
            return (originalCG, gradedCG, jpegData)
        }.value
        if let before = result.0, let after = result.1 {
            beforeAfter = (before, after)
        }
        if let jpeg = result.2 {
            do { try await renderer.saveToPhotoLibrary(jpeg) }
            catch { statusBanner = "保存到相册失败。" }
        }
        state = .done
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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

    public init() {}

    public var body: some View {
        PermissionGate {
            ZStack {
                CameraPreviewView(session: vm.camera.session)
                    .ignoresSafeArea()

                CompositionOverlay(state: vm.compose)
                    .ignoresSafeArea()

                // AI guidance overlay (only while aligning)
                Group {
                    if case .aligning = vm.state {
                        if let p = vm.guidance.posePlacement,
                           let t = PoseLibrary.templates.first(where: { $0.id == p.id }) {
                            PoseOverlay(template: t, positionX: p.x, positionY: p.y,
                                        heightFraction: p.height, alignment: vm.alignmentScore)
                                .ignoresSafeArea()
                                .id(p.id)
                        } else if let rect = vm.guidance.sceneTarget {
                            TargetFrame(target: rect, alignment: vm.alignmentScore)
                                .ignoresSafeArea()
                        }
                    }
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
                    HStack {
                        Spacer().frame(maxWidth: .infinity)
                        shutterButton
                        Spacer().frame(maxWidth: .infinity)
                        aiButton
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .ignoresSafeArea(edges: .top)
            }
            .onAppear { vm.start() }
            .onDisappear { vm.stop() }
        }
    }

    private var isBusy: Bool {
        switch vm.state {
        case .capturing, .grading: return true
        default: return false
        }
    }

    private var shutterButton: some View {
        Button(action: {
            if case .aligning = vm.state { return }
            if case .idle = vm.state { vm.shutterTap() }
        }) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(Color.white).frame(width: 64, height: 64)
                if isBusy { ProgressView().tint(.black) }
            }
        }
        .disabled(isBusy)
    }

    private var aiButton: some View {
        Button(action: { vm.toggleAIGuidance() }) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.cyan, .blue],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .shadow(color: .cyan.opacity(0.6), radius: 10)
                Image(systemName: aiIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
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
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(image, from: image.extent)
    }
}
