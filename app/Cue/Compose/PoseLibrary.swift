// app/Cue/Compose/PoseLibrary.swift
import Foundation

/// Built-in pose templates. All SF Symbols `figure.*` glyphs, so they
/// render at any size with no asset bundle cost.
public enum PoseLibrary {

    public static let templates: [PoseTemplate] = [
        .init(id: "stand",      label: "站立",  symbolName: "figure.stand",        aspect: 2.6),
        .init(id: "arms_open",  label: "张开",  symbolName: "figure.arms.open",    aspect: 1.4),
        .init(id: "walk",       label: "行走",  symbolName: "figure.walk",         aspect: 2.4),
        .init(id: "wave",       label: "招手",  symbolName: "figure.wave",         aspect: 2.4),
        .init(id: "yoga",       label: "瑜伽",  symbolName: "figure.yoga",         aspect: 1.8),
        .init(id: "mind_body",  label: "冥想",  symbolName: "figure.mind.and.body", aspect: 2.6),
        .init(id: "dance",      label: "舞蹈",  symbolName: "figure.dance",        aspect: 2.4),
        .init(id: "child_lift", label: "抱起",  symbolName: "figure.and.child.holdinghands", aspect: 1.6),
    ]
}
