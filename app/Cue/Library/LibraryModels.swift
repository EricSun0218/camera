import Foundation

public struct GradeVariant: Codable, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let imageFilename: String   // rendered graded JPEG, in library dir
    public let scene: String
    public let lighting: String
    public let rationale: String
}

public struct LibraryItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let originalFilename: String
    public var variants: [GradeVariant]

    public var latestVariant: GradeVariant? { variants.last }

    /// Filename to show as the item's thumbnail / default image: the latest
    /// graded variant if any, otherwise the un-graded original.
    public var displayFilename: String { latestVariant?.imageFilename ?? originalFilename }
}
