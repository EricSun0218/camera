// app/CueTests/CIPipelineTests.swift
import Testing
import CoreImage
@testable import Cue

@Suite("CIPipeline") struct CIPipelineTests {

    @Test func neutralIsIdentityShape() {
        let input = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let out = CIPipeline.apply(.neutral, to: input)
        #expect(out.extent.width == 100)
        #expect(out.extent.height == 100)
    }

    @Test func extremeExposureCompiles() {
        var g = GradeParams.neutral
        g.exposure_ev = 1.5
        let input = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let out = CIPipeline.apply(g, to: input)
        #expect(out.extent.width == 32)
    }

    @Test func vignetteAppliesAtNonZero() {
        var g = GradeParams.neutral
        g.vignette_intensity = 0.5
        let input = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let out = CIPipeline.apply(g, to: input)
        // Just verify the chain doesn't crash and produces an image.
        #expect(out.extent.width == 64)
    }
}
