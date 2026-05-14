// app/Cue/App/CueApp.swift
import SwiftUI

@main
struct CueApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
        }
    }
}
