//
//  SceneModels.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation
import SwiftUI

struct SceneSnapshot: Equatable {
    var objects: [SceneObject]
    var selectedID: UUID?
}

struct ModelDocument: Equatable {
    var objects: [SceneObject]
    var selectedID: UUID?
    var light = SceneLight()
    var gridVisible = true
    var revision = 0
    var showExportNotice = false
    var snapEnabled = false
    var moveSnap: Float = 0.25
    var rotationSnapDegrees: Float = 15
    var scaleSnap: Float = 0.1
    private var undoStack: [SceneSnapshot] = []
    private var redoStack: [SceneSnapshot] = []
    private var pendingSnapshot: SceneSnapshot?

    static let sample: ModelDocument = {
        let cube = SceneObject(
            name: "Cube",
            kind: .cube,
            position: .zero,
            scale: [0.7, 0.7, 0.7],
            material: .clay,
            editableGeometry: .cube
        )
        return ModelDocument(
            objects: [cube],
            selectedID: cube.id
        )
    }()

    var selectedIndex: Int? {
        objects.firstIndex { $0.id == selectedID }
    }

    var selectedObjectName: String {
        guard let selectedIndex else { return "Kein Objekt ausgewählt" }
        return objects[selectedIndex].name
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func add(_ kind: PrimitiveKind) {
        beginChange()
        let count = objects.filter { $0.kind == kind }.count + 1
        let column = Float(objects.count % 3) - 1
        let row = Float(objects.count / 3)
        let object = SceneObject(
            name: "\(kind.title) \(count)",
            kind: kind,
            position: [column * 0.42, row * 0.18, row * -0.2],
            material: .clay,
            editableGeometry: kind == .cube ? .cube : EditableGeometry()
        )
        objects.append(object)
        selectedID = object.id
        endChange()
    }

    mutating func duplicateSelected() {
        guard let selectedIndex else { return }
        beginChange()
        var copy = objects[selectedIndex]
        copy.id = UUID()
        copy.name += " Copy"
        copy.position.x += 0.25
        objects.append(copy)
        selectedID = copy.id
        endChange()
    }

    mutating func deleteSelected() {
        guard let selectedIndex else { return }
        beginChange()
        objects.remove(at: selectedIndex)
        ensureSelection()
        endChange()
    }

    mutating func sculptSelected(amount: Float) {
        guard let selectedIndex else { return }
        beginChange()
        objects[selectedIndex].scale.y += amount
        objects[selectedIndex].scale.x = max(
            0.15,
            objects[selectedIndex].scale.x - amount * 0.25
        )
        endChange()
    }

    mutating func ensureSelection() {
        if !objects.contains(where: { $0.id == selectedID }) {
            selectedID = objects.first?.id
        }
    }

    mutating func commitChange() {
        revision += 1
    }

    mutating func beginChange() {
        guard pendingSnapshot == nil else { return }
        pendingSnapshot = snapshot
    }

    mutating func endChange() {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard pendingSnapshot != snapshot else { return }
        undoStack.append(pendingSnapshot)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        redoStack.removeAll()
        revision += 1
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private var snapshot: SceneSnapshot {
        SceneSnapshot(objects: objects, selectedID: selectedID)
    }

    private mutating func restore(_ snapshot: SceneSnapshot) {
        objects = snapshot.objects
        selectedID = snapshot.selectedID
        ensureSelection()
        pendingSnapshot = nil
        revision += 1
    }
}

struct SceneObject: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: PrimitiveKind
    var position: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = .one
    var material: EditorMaterial
    var editableGeometry = EditableGeometry()
}

struct EditorMaterial: Equatable {
    var color: Color
    var metallic: Float
    var roughness: Float
    var textureIndex = 0

    static let clay = EditorMaterial(
        color: Color(red: 0.91, green: 0.43, blue: 0.25),
        metallic: 0.05,
        roughness: 0.68
    )
    static let metal = EditorMaterial(
        color: Color(red: 0.2, green: 0.55, blue: 0.92),
        metallic: 0.82,
        roughness: 0.24
    )
}

struct SceneLight: Equatable {
    var color: Color = .white
    var intensity: Float = 1
    var castsShadow = false
}

enum PrimitiveKind: String, CaseIterable, Identifiable {
    case sphere, cube, cylinder, cone, capsule, plane
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .sphere: "circle.fill"
        case .cube: "cube.fill"
        case .cylinder: "cylinder.fill"
        case .cone: "triangle.fill"
        case .capsule: "capsule.fill"
        case .plane: "square.fill"
        }
    }
}
