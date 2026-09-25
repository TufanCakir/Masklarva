//
//  EditorViewModel.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorViewModel {
    var project: MasklarvaProject
    let projectLibrary: ProjectLibraryModel
    var selectedTool: EditorTool = .move
    var orbit = CGSize.zero
    var zoom: Float = 1
    var cameraPan = SIMD2<Float>.zero
    var cameraMode: CameraNavigationMode = .pan
    var exportArtifact: ExportArtifact?
    var exportError: String?
    @ObservationIgnored private var history = EditorHistory()

    init(
        document: ModelDocument? = nil,
        projectLibrary: ProjectLibraryModel? = nil
    ) {
        if let document {
            let scene = MasklarvaScene(name: "Main Scene", document: document)
            project = MasklarvaProject(
                name: "Untitled Project",
                scenes: [scene],
                activeSceneID: scene.id
            )
        } else {
            project = .sample
        }
        self.projectLibrary = projectLibrary ?? ProjectLibraryModel()
    }

    var document: ModelDocument {
        get { project.activeDocument }
        set { project.activeDocument = newValue }
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var selectedObjectName: String { document.selectedObjectName }
    var objectCount: Int { document.objects.count }
    var canPaste: Bool { document.canPaste }
    var selectedObjectIsLocked: Bool { document.selectedObjectIsLocked }

    func addPrimitive(_ kind: PrimitiveKind) {
        performChange { $0.activeDocument.add(kind) }
    }
    func selectObject(_ id: UUID) { document.selectedID = id }
    func sculptSelection() {
        performChange { $0.activeDocument.sculptSelected(amount: 0.08) }
    }

    func undo() {
        guard let previous = history.undo(currentProject: project) else { return }
        project = previous
    }

    func redo() {
        guard let next = history.redo(currentProject: project) else { return }
        project = next
    }

    func beginChange() {
        history.begin(project: project)
    }

    func endChange() {
        history.commit(project: project)
    }

    func toggleGrid() {
        performChange { $0.activeDocument.gridVisible.toggle() }
    }
    func duplicateSelection() {
        performChange { $0.activeDocument.duplicateSelected() }
    }
    func copySelection() { document.copySelected() }
    func cutSelection() { performChange { $0.activeDocument.cutSelected() } }
    func paste() { performChange { $0.activeDocument.paste() } }
    func deleteSelection() {
        performChange { $0.activeDocument.deleteSelected() }
    }
    func renameSelection(to name: String) {
        performChange { $0.activeDocument.renameSelected(to: name) }
    }
    func toggleSelectionVisibility() {
        performChange { $0.activeDocument.toggleSelectedVisibility() }
    }
    func toggleSelectionLock() {
        performChange { $0.activeDocument.toggleSelectedLock() }
    }
    func selectScene(_ id: UUID) { project.selectScene(id) }
    func createScene() { performChange { $0.createScene() } }
    func duplicateScene() { performChange { $0.duplicateActiveScene() } }
    func renameScene(to name: String) {
        performChange { $0.renameActiveScene(to: name) }
    }
    func deleteScene() { performChange { $0.deleteActiveScene() } }

    func resetCamera() {
        orbit = .zero
        cameraPan = .zero
        zoom = 1
    }

    func resetOrbitAndZoom() {
        orbit = .zero
        zoom = 1
    }

    func focusSelectedObject() {
        guard let selected = document.selectedIndex else { return }
        let position = document.objects[selected].position
        cameraPan = [position.x, position.y]
        zoom = 2.2
    }

    func zoomIn() { zoom = min(5, zoom * 1.25) }
    func zoomOut() { zoom = max(0.2, zoom / 1.25) }

    func selectTool(_ tool: EditorTool) {
        selectedTool = tool
        if tool == .sculpt {
            sculptSelection()
        }
    }

    func apply(_ material: ProjectMaterial) -> Bool {
        guard let selected = document.selectedIndex,
            !document.objects[selected].isLocked
        else { return false }
        beginChange()
        document.objects[selected].material = material.editorMaterial
        document.commitChange()
        endChange()
        return true
    }

    func setMaterialDropTargeted(_ isTargeted: Bool) {
        projectLibrary.isDroppingMaterial = isTargeted
    }

    func export(_ format: SceneExportFormat) {
        let document = document
        Task {
            do {
                exportArtifact = try await USDSceneExporter.export(
                    document: document,
                    format: format
                )
                exportError = nil
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func performChange(
        _ mutation: (inout MasklarvaProject) -> Void
    ) {
        beginChange()
        mutation(&project)
        endChange()
    }
}
