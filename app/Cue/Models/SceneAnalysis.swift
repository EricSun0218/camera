// app/Cue/Models/SceneAnalysis.swift
import Foundation

/// Renamed from `Scene` to `SceneCategory` to avoid collision with `SwiftUI.Scene`
/// (the App protocol's body returns `some Scene`, and SwiftUI's Scene is a protocol;
/// if the module also has an `enum Scene`, name lookup picks the enum and breaks
/// the `App` conformance with a confusing error).
public enum SceneCategory: String, Codable, Sendable {
    case portrait, group, food, landscape, urban, night, interior, product, pet, document, other
}

public enum Lighting: String, Codable, Sendable {
    case harsh_sun, golden_hour, overcast, shade, indoor_warm, indoor_cool, mixed, low_light, flash
}

public struct SceneAnalysis: Codable, Equatable, Sendable {
    public var scene: SceneCategory
    public var lighting: Lighting
    public var rationale: String
    public var grade: GradeParams

    public static let neutralFallback = SceneAnalysis(
        scene: .other, lighting: .mixed,
        rationale: "默认参数(网络/分析失败)",
        grade: .neutral
    )
}
