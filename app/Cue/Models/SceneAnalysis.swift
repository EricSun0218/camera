// app/Cue/Models/SceneAnalysis.swift
import Foundation

public enum Scene: String, Codable, Sendable {
    case portrait, group, food, landscape, urban, night, interior, product, pet, document, other
}

public enum Lighting: String, Codable, Sendable {
    case harsh_sun, golden_hour, overcast, shade, indoor_warm, indoor_cool, mixed, low_light, flash
}

public struct SceneAnalysis: Codable, Equatable, Sendable {
    public var scene: Scene
    public var lighting: Lighting
    public var rationale: String
    public var grade: GradeParams

    public static let neutralFallback = SceneAnalysis(
        scene: .other, lighting: .mixed,
        rationale: "默认参数(网络/分析失败)",
        grade: .neutral
    )
}
