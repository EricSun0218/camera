import Foundation

/// One photo in the library. Originals and AI-graded results are both
/// LibraryPhotos — siblings in the grid, not nested.
public struct LibraryPhoto: Codable, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    /// The displayed JPEG filename (in the library dir).
    public let filename: String
    /// The un-graded image to grade FROM. For an original capture this equals
    /// `filename`. For a graded photo it points back at the true original, so
    /// re-grading always grades the original (never grades an already-graded image).
    public let sourceFilename: String
    /// True if this photo is an AI-graded result.
    public let isGraded: Bool
}
