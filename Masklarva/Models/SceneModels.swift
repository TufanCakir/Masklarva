//
//  SceneModels.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation
import SwiftUI

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
    private var objectClipboard: SceneObject?

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

    static let empty = ModelDocument(objects: [], selectedID: nil)

    var selectedIndex: Int? {
        objects.firstIndex { $0.id == selectedID }
    }

    var selectedObjectName: String {
        guard let selectedIndex else { return "Kein Objekt ausgewählt" }
        return objects[selectedIndex].name
    }

    var canPaste: Bool { objectClipboard != nil }
    var selectedObjectIsLocked: Bool {
        guard let selectedIndex else { return false }
        return objects[selectedIndex].isLocked
    }

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

    mutating func copySelected() {
        guard let selectedIndex else { return }
        objectClipboard = objects[selectedIndex]
    }

    mutating func cutSelected() {
        guard let selectedIndex, !objects[selectedIndex].isLocked else { return }
        objectClipboard = objects[selectedIndex]
        deleteSelected()
    }

    mutating func paste() {
        guard var copy = objectClipboard else { return }
        beginChange()
        copy.id = UUID()
        copy.name += " Copy"
        copy.position.x += 0.25
        copy.parentID = nil
        objects.append(copy)
        selectedID = copy.id
        endChange()
    }

    mutating func deleteSelected() {
        guard let selectedIndex, !objects[selectedIndex].isLocked else { return }
        beginChange()
        objects.remove(at: selectedIndex)
        ensureSelection()
        endChange()
    }

    mutating func sculptSelected(amount: Float) {
        guard let selectedIndex, !objects[selectedIndex].isLocked else { return }
        beginChange()
        objects[selectedIndex].scale.y += amount
        objects[selectedIndex].scale.x = max(
            0.15,
            objects[selectedIndex].scale.x - amount * 0.25
        )
        endChange()
    }

    mutating func renameSelected(to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selectedIndex, !name.isEmpty else { return }
        beginChange()
        objects[selectedIndex].name = name
        endChange()
    }

    mutating func toggleSelectedVisibility() {
        guard let selectedIndex else { return }
        beginChange()
        objects[selectedIndex].isVisible.toggle()
        endChange()
    }

    mutating func toggleSelectedLock() {
        guard let selectedIndex else { return }
        beginChange()
        objects[selectedIndex].isLocked.toggle()
        endChange()
    }

    func duplicateForNewScene() -> ModelDocument {
        var copy = self
        let idMap = Dictionary(
            uniqueKeysWithValues: objects.map { ($0.id, UUID()) }
        )
        copy.objects = objects.map { object in
            var duplicate = object
            duplicate.id = idMap[object.id] ?? UUID()
            duplicate.parentID = object.parentID.flatMap { idMap[$0] }
            return duplicate
        }
        copy.selectedID = selectedID.flatMap { idMap[$0] }
        copy.objectClipboard = nil
        return copy
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
        // Project-wide history is coordinated by EditorViewModel.
    }

    mutating func endChange() {
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
    var isVisible = true
    var isLocked = false
    var parentID: UUID?
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
