//
//  MeshControlPoint.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation

struct MeshControlPoint: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var position: SIMD3<Float>

    init(id: UUID = UUID(), position: SIMD3<Float>) {
        self.id = id
        self.position = position
    }
}

struct SkeletonJoint: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var position: SIMD3<Float>

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        position: SIMD3<Float>
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.position = position
    }
}

struct VertexWeight: Codable, Equatable, Sendable {
    var pointID: UUID
    var jointID: UUID
    var weight: Float

    init(pointID: UUID, jointID: UUID, weight: Float) {
        self.pointID = pointID
        self.jointID = jointID
        self.weight = min(max(weight, 0), 1)
    }
}

/// Editierbare Geometrie und Rig-Daten bleiben unabhängig von RealityKit.
/// Dadurch können Werkzeuge, Undo/Redo und später USD-Import/Export dieselbe
/// Datenquelle nutzen.
struct EditableGeometry: Codable, Equatable, Sendable {
    var points: [MeshControlPoint] = []
    var triangleIndices: [UInt32] = []
    var joints: [SkeletonJoint] = []
    var weights: [VertexWeight] = []
    var selectedPointID: UUID?

    static var cube: EditableGeometry {
        EditableGeometry(
            points: [
                .init(position: [0.45, 0.45, -0.45]),
                .init(position: [-0.45, 0.45, -0.45]),
                .init(position: [-0.45, 0.45, 0.45]),
                .init(position: [0.45, 0.45, 0.45]),
                .init(position: [0.45, -0.45, -0.45]),
                .init(position: [-0.45, -0.45, -0.45]),
                .init(position: [-0.45, -0.45, 0.45]),
                .init(position: [0.45, -0.45, 0.45]),
            ],
            triangleIndices: [
                0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
                0, 3, 7, 7, 4, 0, 0, 4, 1, 4, 5, 1,
                2, 1, 5, 5, 6, 2, 3, 2, 6, 6, 7, 3,
            ]
        )
    }
}
