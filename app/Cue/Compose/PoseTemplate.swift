// app/Cue/Compose/PoseTemplate.swift
import SwiftUI

/// A pose template shown as a translucent outline on top of the camera viewfinder.
/// v1 uses SF Symbols (`figure.*` family) as the silhouette source — zero asset weight,
/// crisp at any size, ships free with the OS. v2 will support user-imported reference
/// photos with on-device segmentation (`VNGeneratePersonSegmentationRequest`).
public struct PoseTemplate: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let label: String          // shown under the thumbnail in the picker
    public let symbolName: String     // SF Symbols name
    public let aspect: CGFloat        // height / width ratio of the silhouette

    public init(id: String, label: String, symbolName: String, aspect: CGFloat) {
        self.id = id
        self.label = label
        self.symbolName = symbolName
        self.aspect = aspect
    }
}
