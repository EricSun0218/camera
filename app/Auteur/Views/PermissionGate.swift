// app/Auteur/Views/PermissionGate.swift
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
                .font(.system(size: 64))
            Text("需要相机权限")
                .font(.title2.weight(.semibold))
            Text("Auteur 需要相机来拍摄并自动调色。\n请在系统设置中开启相机权限。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
