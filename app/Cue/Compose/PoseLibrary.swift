// app/Cue/Compose/PoseLibrary.swift
import Foundation

/// Built-in pose templates. All SF Symbols `figure.*` glyphs, so they
/// render at any size with no asset bundle cost.
public enum PoseLibrary {

    public static let templates: [PoseTemplate] = [
        .init(id: "stand",      label: "Stand",      symbolName: "figure.stand",        aspect: 2.6),
        .init(id: "arms_open",  label: "Arms Open",  symbolName: "figure.arms.open",    aspect: 1.4),
        .init(id: "walk",       label: "Walk",       symbolName: "figure.walk",         aspect: 2.4),
        .init(id: "wave",       label: "Wave",       symbolName: "figure.wave",         aspect: 2.4),
        .init(id: "yoga",       label: "Yoga",       symbolName: "figure.yoga",         aspect: 1.8),
        .init(id: "mind_body",  label: "Sit",        symbolName: "figure.mind.and.body", aspect: 2.6),
        .init(id: "dance",      label: "Dance",      symbolName: "figure.dance",        aspect: 2.4),
        .init(id: "child_lift", label: "With Child", symbolName: "figure.and.child.holdinghands", aspect: 1.6),
    ]
}
