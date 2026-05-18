// app/CueTests/ZoomTests.swift
import Testing
import Foundation
import CoreGraphics
import Vision
@testable import Cue

@Suite("ZoomMapping") struct ZoomMappingTests {

    @Test func singleCamMapping() {
        // Single-wide camera: raw 1x == optical 1x, no 0.5x.
        let m = ZoomMapping(oneXRawFactor: 1.0, minRaw: 1.0, maxRaw: 120.0)
        #expect(m.minOptical == 1.0)
        #expect(m.maxOptical == 3.0)
        #expect(m.rawFor(optical: 2.0) == 2.0)
        #expect(m.rawFor(optical: 0.2) == 1.0)   // clamped up to minOptical
        #expect(m.rawFor(optical: 9.0) == 3.0)   // clamped down to maxOptical
    }

    @Test func dualWideMapping() {
        // Virtual dual-wide: raw 2.0 is the main "1x" lens, raw 1.0 is 0.5x.
        let m = ZoomMapping(oneXRawFactor: 2.0, minRaw: 1.0, maxRaw: 12.0)
        #expect(m.minOptical == 0.5)
        #expect(m.maxOptical == 3.0)
        #expect(m.rawFor(optical: 0.5) == 1.0)
        #expect(m.rawFor(optical: 1.0) == 2.0)
        #expect(m.rawFor(optical: 3.0) == 6.0)
        #expect(m.rawFor(optical: 0.1) == 1.0)   // clamp to 0.5x -> raw 1.0
        #expect(m.rawFor(optical: 9.0) == 6.0)   // clamp to 3.0x -> raw 6.0
    }

    @Test func clampOptical() {
        let m = ZoomMapping(oneXRawFactor: 2.0, minRaw: 1.0, maxRaw: 12.0)
        #expect(m.clampOptical(0.1) == 0.5)
        #expect(m.clampOptical(5.0) == 3.0)
        #expect(m.clampOptical(1.5) == 1.5)
    }

    @Test func initClampsInvalidInputs() {
        // oneXRawFactor below 1.0 is clamped up to 1.0.
        #expect(ZoomMapping(oneXRawFactor: 0.5, minRaw: 1.0, maxRaw: 10.0).oneXRawFactor == 1.0)
        // minRaw below 1.0 is clamped up to 1.0.
        #expect(ZoomMapping(oneXRawFactor: 1.0, minRaw: 0.0, maxRaw: 10.0).minRaw == 1.0)
        // maxRaw below minRaw is clamped up to minRaw.
        let m = ZoomMapping(oneXRawFactor: 1.0, minRaw: 4.0, maxRaw: 2.0)
        #expect(m.maxRaw == 4.0)
    }
}
