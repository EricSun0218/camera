// app/Auteur/Models/CoachTip.swift
import Foundation

public enum CoachPriority: String, Codable, Sendable { case low, med, high }

public struct CoachTip: Codable, Equatable, Sendable {
    public var tip: String?
    public var priority: CoachPriority

    public static let silent = CoachTip(tip: nil, priority: .low)

    public var isWorthShowing: Bool {
        guard let tip, !tip.isEmpty else { return false }
        return priority == .med || priority == .high
    }
}
