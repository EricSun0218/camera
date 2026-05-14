// app/Cue/Camera/CameraPreviewView.swift
import SwiftUI
import AVFoundation

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) { self.session = session }

    public func makeUIView(context: Context) -> PreviewLayerView {
        let v = PreviewLayerView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    public func updateUIView(_ uiView: PreviewLayerView, context: Context) {}

    public final class PreviewLayerView: UIView {
        public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        public var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
