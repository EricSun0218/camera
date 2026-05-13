// app/AuteurTests/GradeParamsTests.swift
import Testing
import Foundation
@testable import Auteur

@Suite("GradeParams") struct GradeParamsTests {

    @Test func neutralRoundTrip() throws {
        let n = GradeParams.neutral
        let data = try JSONEncoder().encode(n)
        let back = try JSONDecoder().decode(GradeParams.self, from: data)
        #expect(back == n)
    }

    @Test func clampOutOfRange() {
        var g = GradeParams.neutral
        g.exposure_ev = 999
        g.hsl.red.hue = 999
        let c = g.clamped()
        #expect(c.exposure_ev == 2)
        #expect(c.hsl.red.hue == 30)
    }

    @Test func decodesFullSceneAnalysis() throws {
        let json = """
        {
          "scene":"portrait","lighting":"golden_hour","rationale":"warm",
          "grade":{
            "exposure_ev":0.1,"contrast":5,"highlights":-20,"shadows":15,
            "whites":0,"blacks":-5,"saturation":0,"vibrance":10,
            "temperature":5,"tint":0,
            "hsl":{
              "red":{"hue":0,"saturation":-5,"luminance":0},
              "orange":{"hue":0,"saturation":0,"luminance":0},
              "yellow":{"hue":0,"saturation":0,"luminance":0},
              "green":{"hue":0,"saturation":0,"luminance":0},
              "aqua":{"hue":0,"saturation":0,"luminance":0},
              "blue":{"hue":0,"saturation":0,"luminance":0},
              "purple":{"hue":0,"saturation":0,"luminance":0},
              "magenta":{"hue":0,"saturation":0,"luminance":0}
            },
            "vignette_intensity":0,"vignette_radius":1
          }
        }
        """.data(using: .utf8)!
        let sa = try JSONDecoder().decode(SceneAnalysis.self, from: json)
        #expect(sa.scene == .portrait)
        #expect(sa.lighting == .golden_hour)
    }
}
