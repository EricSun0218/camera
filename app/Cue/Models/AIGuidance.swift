// app/Cue/Models/AIGuidance.swift
import Foundation
import CoreGraphics

public enum SubjectType: String, Codable, Sendable {
    case person, scene, empty
}

public struct AIGuidance: Codable, Equatable, Sendable {
    public var subjectType: SubjectType
    // Person mode
    public var poseID: String?
    public var poseX: Double?
    public var poseY: Double?
    public var poseHeight: Double?
    // Scene mode
    public var targetX: Double?
    public var targetY: Double?
    public var targetW: Double?
    public var targetH: Double?
    // Always
    public var suggestedZoom: Double

    public static let empty = AIGuidance(
        subjectType: .empty,
        poseID: nil, poseX: nil, poseY: nil, poseHeight: nil,
        targetX: nil, targetY: nil, targetW: nil, targetH: nil,
        suggestedZoom: 1.0
    )

    public var posePlacement: (id: String, x: Double, y: Double, height: Double)? {
        guard subjectType == .person, let id = poseID,
              let x = poseX, let y = poseY, let h = poseHeight else { return nil }
        return (id, x, y, h)
    }

    public var sceneTarget: CGRect? {
        guard subjectType == .scene,
              let x = targetX, let y = targetY, let w = targetW, let h = targetH else { return nil }
        // Convert center+size to top-left rect.
        return CGRect(x: x - w/2, y: y - h/2, width: w, height: h)
    }

    private enum CodingKeys: String, CodingKey {
        case subjectType   = "subject_type"
        case poseID        = "pose_id"
        case poseX         = "pose_x"
        case poseY         = "pose_y"
        case poseHeight    = "pose_height"
        case targetX       = "target_x"
        case targetY       = "target_y"
        case targetW       = "target_w"
        case targetH       = "target_h"
        case suggestedZoom = "suggested_zoom"
    }
}
