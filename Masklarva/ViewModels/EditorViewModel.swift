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
    var projectStorageError: String?
    var lastSavedAt: Date?
    var isSavingProject = false
    @ObservationIgnored private var history = EditorHistory()
    @ObservationIgnored private let projectStore: ProjectStore
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var didLoadAutosave = false

    init(
        document: ModelDocument? = nil,
        projectLibrary: ProjectLibraryModel? = nil,
        projectStore: ProjectStore = ProjectStore()
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
        self.projectStore = projectStore
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
    var selectedObjectIsGroup: Bool {
        guard let index = document.selectedIndex else { return false }
        return document.objects[index].isGroup
    }
    var selectedObjectHasParent: Bool {
        guard let index = document.selectedIndex else { return false }
        return document.objects[index].parentID != nil
    }
    var parentCandidates: [SceneObject] {
        document.objects.filter { document.canParentSelected(to: $0.id) }
    }
    var groupCandidates: [SceneObject] {
        guard let selectedIndex = document.selectedIndex else { return [] }
        let selectedObject = document.objects[selectedIndex]
        return document.objects.filter {
            $0.id != selectedObject.id
                && $0.parentID == selectedObject.parentID
                && !document.isEffectivelyLocked($0.id)
        }
    }

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
        scheduleAutosave()
    }

    func redo() {
        guard let next = history.redo(currentProject: project) else { return }
        project = next
        scheduleAutosave()
    }

    func beginChange() {
        history.begin(project: project)
    }

    func endChange() {
        if history.commit(project: project) {
            scheduleAutosave()
        }
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
    func parentSelection(to parentID: UUID) {
        performChange { $0.activeDocument.parentSelected(to: parentID) }
    }
    func unparentSelection() {
        performChange { $0.activeDocument.unparentSelected() }
    }
    func groupSelection(with objectID: UUID) {
        performChange { $0.activeDocument.groupSelected(with: objectID) }
    }
    func ungroupSelection() {
        performChange { $0.activeDocument.ungroupSelected() }
    }
    func selectScene(_ id: UUID) {
        guard project.activeSceneID != id else { return }
        project.selectScene(id)
        scheduleAutosave()
    }
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
            !document.isEffectivelyLocked(document.objects[selected].id),
            !document.objects[selected].isGroup
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

    func loadAutosavedProject() async {
        guard !didLoadAutosave else { return }
        didLoadAutosave = true
        do {
            if let result = try await projectStore.loadAutosave() {
                project = result.project
                history = EditorHistory()
                if result.recoveredFromBackup {
                    projectStorageError = String(
                        localized: "Das letzte Projekt war beschädigt. Die vorherige Sicherung wurde wiederhergestellt."
                    )
                    return
                }
            }
            projectStorageError = nil
        } catch {
            projectStorageError = error.localizedDescription
        }
    }

    func saveProject() {
        autosaveTask?.cancel()
        let snapshot = project
        autosaveTask = Task { [weak self] in
            await self?.persist(snapshot)
        }
    }

    private func performChange(
        _ mutation: (inout MasklarvaProject) -> Void
    ) {
        beginChange()
        mutation(&project)
        endChange()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = project
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await self?.persist(snapshot)
            } catch {
                // Cancellation is expected when another edit restarts the debounce.
            }
        }
    }

    private func persist(_ snapshot: MasklarvaProject) async {
        isSavingProject = true
        defer { isSavingProject = false }
        do {
            try await projectStore.saveAutosave(snapshot)
            lastSavedAt = .now
            projectStorageError = nil
        } catch {
            projectStorageError = error.localizedDescription
        }
    }
}
