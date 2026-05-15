// app/Cue/Color/SharedCI.swift
import CoreImage

/// One process-wide Core Image context. CIContext creation is expensive —
/// never create one per render call.
public enum SharedCI {
    public static let context = CIContext(options: [.useSoftwareRenderer: false])
}
