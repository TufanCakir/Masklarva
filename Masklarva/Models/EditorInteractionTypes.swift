//
//  EditorInteractionTypes.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation
import SwiftUI

struct SceneTransform {
    let position: SIMD3<Float>
    let rotation: SIMD3<Float>
    let scale: SIMD3<Float>

    init(object: SceneObject) {
        position = object.position
        rotation = object.rotation
        scale = object.scale
    }
}

enum GizmoAxis: String {
    case x, y, z, screen
}

struct CameraDragStart {
    let orbit: CGSize
    let pan: SIMD2<Float>
}

enum CameraNavigationMode: CaseIterable, Identifiable {
    case pan, orbit

    var id: Self { self }
    var title: String {
        switch self {
        case .pan: "Arbeitsfläche bewegen"
        case .orbit: "Ansicht drehen"
        }
    }
    var symbol: String {
        switch self {
        case .pan: "hand.draw"
        case .orbit: "rotate.3d"
        }
    }
}

enum EditorTool: CaseIterable, Identifiable {
    case select, move, rotate, scale, points, sculpt
    var id: Self { self }
    var title: String {
        switch self {
        case .select: "Auswahl"
        case .move: "Bewegen"
        case .rotate: "Drehen"
        case .scale: "Größe"
        case .points: "Punkte"
        case .sculpt: "Kneten"
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .move: "move.3d"
        case .rotate: "rotate.3d"
        case .scale: "arrow.up.left.and.arrow.down.right"
        case .points: "point.3.connected.trianglepath.dotted"
        case .sculpt: "hand.draw.fill"
        }
    }
}
