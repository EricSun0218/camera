// app/Cue/App/RootView.swift
import SwiftUI
import CoreImage
import AVFoundation

@MainActor
final class RootViewModel: ObservableObject, CameraSessionDelegate {
    @Published var compose = ComposeState.initial
    @Published var coachTip: CoachTip = .silent
    @Published var beforeAfter: (before: CGImage, after: CGImage)?
    @Published var statusBanner: String?
    @Published var isProcessing = false

    let camera = CameraSession()
    let cv = OnDeviceCV()
    let client = BackendClient()
    lazy var throttler = CoachThrottler(client: client)
    let renderer = PhotoRenderer()

    init() {
        camera.delegate = self
        camera.configure()
    }

    func start() { camera.start() }
    func stop()  { camera.stop() }
    func capture() { camera.capture() }

    // MARK: CameraSessionDelegate

    nonisolated func cameraDidEmitPreview(_ pixelBuffer: CVPixelBuffer) {
        let buffer = pixelBuffer
        Task { @MainActor in
            self.cv.ingest(pixelBuffer: buffer)
            self.compose = self.cv.state
            self.throttler.tick(pixelBuffer: buffer)
            self.coachTip = self.throttler.currentTip
        }
    }

    nonisolated func cameraDidCapturePhoto(_ ciImage: CIImage) {
        Task { @MainActor in
            await self.process(captured: ciImage)
        }
    }

    nonisolated func cameraDidFail(_ error: Error) {
        Task { @MainActor in self.statusBanner = "相机错误: \(error.localizedDescription)" }
    }

    private func process(captured: CIImage) async {
        isProcessing = true
        defer { isProcessing = false }

        // 1. Compute base64 thumbnail for analysis (off the main actor).
        let b64 = await Task.detached(priority: .userInitiated) {
            ImageEncoder.downsampledBase64(from: captured, maxSide: 1024, quality: 0.85)
        }.value

        // 2. Call grader (with fallback on any failure).
        let analysis: SceneAnalysis
        if let b64 {
            do {
                analysis = try await client.grade(imageB64: b64)
            } catch {
                statusBanner = "调色服务离线,已使用默认参数。"
                analysis = NeutralPreset.sceneAnalysis
            }
        } else {
            statusBanner = "图像编码失败,已使用默认参数。"
            analysis = NeutralPreset.sceneAnalysis
        }

        // 3. Apply grade via Core Image (off main).
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

        // Auto-dismiss before/after after 3s.
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); beforeAfter = nil }
    }
}

public struct RootView: View {
    @StateObject private var vm = RootViewModel()

    public init() {}

    /// Resolve the LLM's pose placement into (template, x, y, height).
    /// AI-driven only — no user picker, no fixed position. The Coach LLM places the
    /// silhouette using composition rules (rule of thirds, headroom, negative space)
    /// so the user moves the phone to align the real subject into the outline.
    private var aiPose: (template: PoseTemplate, x: Double, y: Double, h: Double)? {
        guard let p = vm.coachTip.posePlacement,
              let t = PoseLibrary.templates.first(where: { $0.id == p.id })
        else { return nil }
        return (t, p.x, p.y, p.height)
    }

    public var body: some View {
        PermissionGate {
            ZStack {
                CameraPreviewView(session: vm.camera.session)
                    .ignoresSafeArea()

                CompositionOverlay(state: vm.compose, coachTip: vm.coachTip)
                    .ignoresSafeArea()

                // Pose silhouette: AI picks template AND composition-aware screen placement.
                // Position smoothly tweens between Coach updates (~2 s cadence).
                if let p = aiPose {
                    PoseOverlay(template: p.template,
                                positionX: p.x,
                                positionY: p.y,
                                heightFraction: p.h)
                        .ignoresSafeArea()
                        .id(p.template.id)
                }

                if let (before, after) = vm.beforeAfter {
                    BeforeAfterReveal(before: before, after: after)
                        .ignoresSafeArea()
                }

                VStack {
                    if let s = vm.statusBanner {
                        Text(s).font(.footnote).padding(8)
                            .background(.black.opacity(0.6)).clipShape(Capsule())
                            .foregroundStyle(.white).padding(.top, 60)
                    }
                    Spacer()
                    shutterButton
                        .padding(.bottom, 32)
                }
                .ignoresSafeArea(edges: .top)
            }
            .onAppear { vm.start() }
            .onDisappear { vm.stop() }
        }
    }

    private var shutterButton: some View {
        Button(action: { vm.capture() }) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(Color.white).frame(width: 64, height: 64)
                if vm.isProcessing {
                    ProgressView().tint(.black)
                }
            }
        }
        .disabled(vm.isProcessing)
    }
}

private extension PhotoRenderer {
    func toCGImage(_ image: CIImage) -> CGImage? {
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(image, from: image.extent)
    }
}
