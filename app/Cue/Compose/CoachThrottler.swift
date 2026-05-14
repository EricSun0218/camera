// app/Cue/Compose/CoachThrottler.swift
import Foundation
import CoreImage

@MainActor
public final class CoachThrottler: ObservableObject {
    @Published public private(set) var currentTip: CoachTip = .silent
    @Published public private(set) var lastShownAt: Date?

    private let client: BackendClient
    private let intervalSeconds: TimeInterval = 2.0
    private let bannerHoldSeconds: TimeInterval = 4.0
    private var inFlight = false
    private var lastCallAt: Date = .distantPast
    private var lastTipText: String?
    private var coachDisabled = false  // set true on rate-limit

    public init(client: BackendClient) {
        self.client = client
    }

    /// Try to send a coach call; no-op if too recent / in-flight / disabled.
    public func tick(pixelBuffer: CVPixelBuffer) {
        guard !coachDisabled, !inFlight else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCallAt) >= intervalSeconds else { return }
        guard let b64 = ImageEncoder.downsampledBase64(from: pixelBuffer, maxSide: 1024, quality: 0.6) else { return }
        inFlight = true
        lastCallAt = now
        Task { @MainActor [weak self] in
            defer { self?.inFlight = false }
            guard let self else { return }
            do {
                let tip = try await self.client.coach(imageB64: b64)
                self.publish(tip)
            } catch BackendError.rateLimited {
                self.coachDisabled = true
            } catch {
                // network blip — ignore, try next tick
            }
        }
    }

    private func publish(_ tip: CoachTip) {
        guard tip.isWorthShowing else {
            // Auto-fade if last shown is older than hold window
            if let shown = lastShownAt, Date().timeIntervalSince(shown) > bannerHoldSeconds {
                currentTip = .silent
            }
            return
        }
        if tip.tip == lastTipText { return }   // dedup
        lastTipText = tip.tip
        currentTip = tip
        lastShownAt = Date()
    }
}
