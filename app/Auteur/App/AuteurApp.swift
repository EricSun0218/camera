// app/Auteur/App/AuteurApp.swift
import SwiftUI

@main
struct AuteurApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
        }
    }
}
