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
    var document: ModelDocument
    let projectLibrary: ProjectLibraryModel
    var selectedTool: EditorTool = .move
    var orbit = CGSize.zero
    var zoom: Float = 1
    var cameraPan = SIMD2<Float>.zero
    var cameraMode: CameraNavigationMode = .pan
    var exportArtifact: ExportArtifact?
    var exportError: String?

    init(
        document: ModelDocument? = nil,
        projectLibrary: ProjectLibraryModel? = nil
    ) {
        self.document = document ?? .sample
        self.projectLibrary = projectLibrary ?? ProjectLibraryModel()
    }

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }
    var selectedObjectName: String { document.selectedObjectName }
    var objectCount: Int { document.objects.count }

    func addPrimitive(_ kind: PrimitiveKind) { document.add(kind) }
    func selectObject(_ id: UUID) { document.selectedID = id }
    func sculptSelection() { document.sculptSelected(amount: 0.08) }
    func undo() { document.undo() }
    func redo() { document.redo() }
    func toggleGrid() { document.gridVisible.toggle() }

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
        guard let selected = document.selectedIndex else { return false }
        document.beginChange()
        document.objects[selected].material = material.editorMaterial
        document.endChange()
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
}
