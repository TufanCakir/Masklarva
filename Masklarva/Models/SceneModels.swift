//
//  SceneModels.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation
import SwiftUI

struct ModelDocument: Codable, Equatable, Sendable {
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
    private var objectClipboard: [SceneObject] = []
    private var clipboardRootID: UUID?

    init(
        objects: [SceneObject],
        selectedID: UUID?,
        light: SceneLight = SceneLight(),
        gridVisible: Bool = true,
        snapEnabled: Bool = false,
        moveSnap: Float = 0.25,
        rotationSnapDegrees: Float = 15,
        scaleSnap: Float = 0.1
    ) {
        self.objects = objects
        self.selectedID = selectedID
        self.light = light
        self.gridVisible = gridVisible
        self.snapEnabled = snapEnabled
        self.moveSnap = moveSnap
        self.rotationSnapDegrees = rotationSnapDegrees
        self.scaleSnap = scaleSnap
    }

    private enum CodingKeys: String, CodingKey {
        case objects
        case selectedID
        case light
        case gridVisible
        case snapEnabled
        case moveSnap
        case rotationSnapDegrees
        case scaleSnap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objects = try container.decode([SceneObject].self, forKey: .objects)
        selectedID = try container.decodeIfPresent(UUID.self, forKey: .selectedID)
        light = try container.decode(SceneLight.self, forKey: .light)
        gridVisible = try container.decode(Bool.self, forKey: .gridVisible)
        snapEnabled = try container.decode(Bool.self, forKey: .snapEnabled)
        moveSnap = try container.decode(Float.self, forKey: .moveSnap)
        rotationSnapDegrees = try container.decode(
            Float.self,
            forKey: .rotationSnapDegrees
        )
        scaleSnap = try container.decode(Float.self, forKey: .scaleSnap)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objects, forKey: .objects)
        try container.encodeIfPresent(selectedID, forKey: .selectedID)
        try container.encode(light, forKey: .light)
        try container.encode(gridVisible, forKey: .gridVisible)
        try container.encode(snapEnabled, forKey: .snapEnabled)
        try container.encode(moveSnap, forKey: .moveSnap)
        try container.encode(rotationSnapDegrees, forKey: .rotationSnapDegrees)
        try container.encode(scaleSnap, forKey: .scaleSnap)
    }

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

    var canPaste: Bool { !objectClipboard.isEmpty && clipboardRootID != nil }
    var selectedObjectIsLocked: Bool {
        guard let selectedID else { return false }
        return isEffectivelyLocked(selectedID)
    }

    var renderableObjects: [SceneObject] {
        objects.filter { !$0.isGroup && isEffectivelyVisible($0.id) }
    }

    var hierarchyItems: [SceneHierarchyItem] {
        var result: [SceneHierarchyItem] = []
        appendHierarchyItems(parentID: nil, depth: 0, to: &result)
        return result
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
        let source = objects[selectedIndex]
        let subtreeIDs = descendantIDs(of: source.id).union([source.id])
        let sourceObjects = objects.filter { subtreeIDs.contains($0.id) }
        let idMap = Dictionary(
            uniqueKeysWithValues: sourceObjects.map { ($0.id, UUID()) }
        )
        let duplicates = sourceObjects.map { object in
            var copy = object
            copy.id = idMap[object.id] ?? UUID()
            copy.parentID = object.parentID.flatMap { idMap[$0] } ?? object.parentID
            if object.id == source.id {
                copy.name += " Copy"
                copy.position.x += 0.25
            }
            return copy
        }
        objects.append(contentsOf: duplicates)
        selectedID = idMap[source.id]
        endChange()
    }

    mutating func copySelected() {
        guard let selectedIndex else { return }
        let rootID = objects[selectedIndex].id
        let copiedIDs = descendantIDs(of: rootID).union([rootID])
        objectClipboard = objects.filter { copiedIDs.contains($0.id) }
        clipboardRootID = rootID
    }

    mutating func cutSelected() {
        guard let selectedIndex,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        copySelected()
        deleteSelected()
    }

    mutating func paste() {
        guard let clipboardRootID,
            objectClipboard.contains(where: { $0.id == clipboardRootID })
        else { return }
        beginChange()
        let idMap = Dictionary(
            uniqueKeysWithValues: objectClipboard.map { ($0.id, UUID()) }
        )
        let copies = objectClipboard.map { object in
            var copy = object
            copy.id = idMap[object.id] ?? UUID()
            copy.parentID = object.parentID.flatMap { idMap[$0] }
            if object.id == clipboardRootID {
                copy.name += " Copy"
                copy.position.x += 0.25
                copy.parentID = nil
            }
            return copy
        }
        objects.append(contentsOf: copies)
        selectedID = idMap[clipboardRootID]
        endChange()
    }

    mutating func deleteSelected() {
        guard let selectedIndex,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        let selectedObjectID = objects[selectedIndex].id
        let removedIDs = descendantIDs(of: selectedObjectID).union([selectedObjectID])
        objects.removeAll { removedIDs.contains($0.id) }
        ensureSelection()
        endChange()
    }

    mutating func sculptSelected(amount: Float) {
        guard let selectedIndex,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        objects[selectedIndex].scale.y += amount
        objects[selectedIndex].scale.x = max(
            0.15,
            objects[selectedIndex].scale.x - amount * 0.25
        )
        endChange()
    }

    mutating func deleteSelectedGeometry() {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.deleteSelectedGeometry() else {
            return
        }
        endChange()
    }

    mutating func recalculateSelectedGeometryNormals() {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.recalculateNormals() else {
            return
        }
        endChange()
    }

    mutating func separateSelectedFaces() {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        let source = objects[selectedIndex]
        var sourceGeometry = source.editableGeometry
        guard let extractedGeometry = sourceGeometry.extractSelectedFaces() else {
            return
        }

        beginChange()
        objects[selectedIndex].editableGeometry = sourceGeometry
        var separatedObject = source
        separatedObject.id = UUID()
        separatedObject.name = uniqueObjectName(base: "\(source.name) Auswahl")
        separatedObject.editableGeometry = extractedGeometry
        separatedObject.isLocked = false
        objects.append(separatedObject)
        selectedID = separatedObject.id
        endChange()
    }

    mutating func extrudeSelectedFaces(distance: Float) {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.extrudeSelectedFaces(
            distance: distance
        ) else { return }
        endChange()
    }

    mutating func insetSelectedFaces(amount: Float) {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.insetSelectedFaces(
            amount: amount
        ) else { return }
        endChange()
    }

    mutating func bevelSelectedEdge(width: Float) {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.bevelSelectedEdge(
            width: width
        ) else { return }
        endChange()
    }

    mutating func weldSelectedVerticesToCenter() {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry
            .weldSelectedVerticesToCenter()
        else { return }
        endChange()
    }

    mutating func duplicateSelectedGeometry(offset: SIMD3<Float> = .zero) {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.duplicateSelectedGeometry(
            offset: offset
        )
        else { return }
        endChange()
    }

    mutating func flipSelectedFaceNormals() {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.flipSelectedFaceNormals()
        else { return }
        endChange()
    }

    mutating func linearSubdivideSelectedObject() {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.linearSubdivide()
        else { return }
        endChange()
    }

    mutating func catmullClarkSubdivideSelectedObject(strength: Float) {
        guard let selectedIndex,
            !objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        guard objects[selectedIndex].editableGeometry.catmullClarkSubdivide(
            strength: strength
        ) else { return }
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

    mutating func parentSelected(to parentID: UUID) {
        guard let selectedIndex,
            canParentSelected(to: parentID),
            !isEffectivelyLocked(objects[selectedIndex].id),
            !isEffectivelyLocked(parentID)
        else { return }
        beginChange()
        objects[selectedIndex].parentID = parentID
        endChange()
    }

    mutating func unparentSelected() {
        guard let selectedIndex,
            objects[selectedIndex].parentID != nil,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        objects[selectedIndex].parentID = nil
        endChange()
    }

    mutating func groupSelected(with otherID: UUID) {
        guard let selectedIndex,
            objects.indices.contains(selectedIndex),
            let otherObject = objects.first(where: { $0.id == otherID }),
            otherObject.parentID == objects[selectedIndex].parentID,
            canParentSelected(to: otherID),
            !isEffectivelyLocked(objects[selectedIndex].id),
            !isEffectivelyLocked(otherID)
        else { return }
        beginChange()
        let selectedObjectID = objects[selectedIndex].id
        let sharedParentID = objects[selectedIndex].parentID
        let group = SceneObject.group(
            name: uniqueObjectName(base: "Group"),
            parentID: sharedParentID
        )
        objects.append(group)
        if let firstIndex = objects.firstIndex(where: { $0.id == selectedObjectID }) {
            objects[firstIndex].parentID = group.id
        }
        if let secondIndex = objects.firstIndex(where: { $0.id == otherID }) {
            objects[secondIndex].parentID = group.id
        }
        selectedID = group.id
        endChange()
    }

    mutating func ungroupSelected() {
        guard let selectedIndex,
            objects[selectedIndex].isGroup,
            !isEffectivelyLocked(objects[selectedIndex].id)
        else { return }
        beginChange()
        let group = objects[selectedIndex]
        for index in objects.indices where objects[index].parentID == group.id {
            objects[index].parentID = group.parentID
        }
        objects.remove(at: selectedIndex)
        ensureSelection()
        endChange()
    }

    func canParentSelected(to parentID: UUID) -> Bool {
        guard let selectedID,
            selectedID != parentID,
            objects.contains(where: { $0.id == parentID })
        else { return false }
        return !descendantIDs(of: selectedID).contains(parentID)
    }

    func isEffectivelyLocked(_ objectID: UUID) -> Bool {
        var currentID: UUID? = objectID
        var visited: Set<UUID> = []
        while let id = currentID,
            let object = objects.first(where: { $0.id == id }),
            visited.insert(id).inserted
        {
            if object.isLocked { return true }
            currentID = object.parentID
        }
        return false
    }

    func isEffectivelyVisible(_ objectID: UUID) -> Bool {
        var currentID: UUID? = objectID
        var visited: Set<UUID> = []
        while let id = currentID,
            let object = objects.first(where: { $0.id == id }),
            visited.insert(id).inserted
        {
            if !object.isVisible { return false }
            currentID = object.parentID
        }
        return true
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
        copy.objectClipboard = []
        copy.clipboardRootID = nil
        return copy
    }

    private func descendantIDs(of objectID: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var pending = [objectID]
        while let parentID = pending.popLast() {
            let childIDs = objects.compactMap { object in
                object.parentID == parentID ? object.id : nil
            }
            for childID in childIDs where result.insert(childID).inserted {
                pending.append(childID)
            }
        }
        return result
    }

    private func uniqueObjectName(base: String) -> String {
        let names = Set(objects.map(\.name))
        guard names.contains(base) else { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private func appendHierarchyItems(
        parentID: UUID?,
        depth: Int,
        to result: inout [SceneHierarchyItem]
    ) {
        for object in objects where object.parentID == parentID {
            result.append(SceneHierarchyItem(object: object, depth: depth))
            appendHierarchyItems(parentID: object.id, depth: depth + 1, to: &result)
        }
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

struct SceneObject: Identifiable, Codable, Equatable, Sendable {
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

    static func group(name: String, parentID: UUID?) -> SceneObject {
        SceneObject(
            name: name,
            kind: .cube,
            material: .clay,
            parentID: parentID,
            isGroup: true
        )
    }

    var isGroup = false
}

struct SceneHierarchyItem: Identifiable, Equatable {
    var object: SceneObject
    var depth: Int

    var id: UUID { object.id }
}

struct EditorMaterial: Codable, Equatable, Sendable {
    var color: LinearColor
    var metallic: Float
    var roughness: Float
    var textureIndex = 0

    static let clay = EditorMaterial(
        color: LinearColor(red: 0.91, green: 0.43, blue: 0.25),
        metallic: 0.05,
        roughness: 0.68
    )
    static let metal = EditorMaterial(
        color: LinearColor(red: 0.2, green: 0.55, blue: 0.92),
        metallic: 0.82,
        roughness: 0.24
    )
}

struct SceneLight: Codable, Equatable, Sendable {
    var color = LinearColor(red: 1, green: 1, blue: 1)
    var intensity: Float = 1
    var castsShadow = false
}

enum PrimitiveKind: String, CaseIterable, Codable, Identifiable, Sendable {
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
