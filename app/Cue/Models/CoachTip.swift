// app/Cue/Models/CoachTip.swift
import Foundation

public enum CoachPriority: String, Codable, Sendable { case low, med, high }

public struct CoachTip: Codable, Equatable, Sendable {
    public var tip: String?
    public var priority: CoachPriority
    /// AI-picked pose template id from PoseLibrary, or nil if no pose should be shown.
    public var poseID: String?
    /// Horizontal screen position of silhouette CENTER, 0..1. nil if no pose.
    public var poseX: Double?
    /// Vertical screen position of silhouette CENTER, 0..1. nil if no pose.
    public var poseY: Double?
    /// Silhouette height as fraction of viewfinder height, 0.3..0.95. nil if no pose.
    public var poseHeight: Double?

    public static let silent = CoachTip(
        tip: nil, priority: .low,
        poseID: nil, poseX: nil, poseY: nil, poseHeight: nil
    )

    public var isWorthShowing: Bool {
        guard let tip, !tip.isEmpty else { return false }
        return priority == .med || priority == .high
    }

    /// Convenience: full placement if and only if all three placement fields and the id are present.
    public var posePlacement: (id: String, x: Double, y: Double, height: Double)? {
        guard let id = poseID, let x = poseX, let y = poseY, let h = poseHeight else { return nil }
        return (id, x, y, h)
    }

    private enum CodingKeys: String, CodingKey {
        case tip
        case priority
        case poseID     = "pose_id"
        case poseX      = "pose_x"
        case poseY      = "pose_y"
        case poseHeight = "pose_height"
    }
}
