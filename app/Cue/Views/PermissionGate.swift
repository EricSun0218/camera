// app/Cue/Views/PermissionGate.swift
import SwiftUI
import AVFoundation
import Photos

public struct PermissionGate<Content: View>: View {
    @State private var cameraGranted = false
    @State private var photosGranted = false
    @State private var checked = false
    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group {
            if !checked {
                ProgressView().task { await check() }
            } else if cameraGranted {
                content()
            } else {
                deniedView
            }
        }
    }

    private func check() async {
        cameraGranted = await CameraSession.requestAuthorization()
        let phStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if phStatus == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            photosGranted = granted == .authorized || granted == .limited
        } else {
            photosGranted = phStatus == .authorized || phStatus == .limited
        }
        checked = true
    }

    private var deniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("Camera Access Needed")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Cue needs the camera to shoot and auto-grade your photos.\nEnable camera access in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glassProminent)
            .tint(.cyan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
