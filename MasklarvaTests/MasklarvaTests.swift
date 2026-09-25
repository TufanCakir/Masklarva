import Foundation
import Testing
@testable import Masklarva

@Suite("Phase 1 project architecture")
@MainActor
struct MasklarvaTests {
    @Test("Project format preserves scenes, hierarchy, and geometry")
    func projectRoundTrip() throws {
        var project = MasklarvaProject.sample
        project.activeDocument.add(.sphere)
        let sphereID = try #require(project.activeDocument.selectedID)
        let cubeID = try #require(project.activeDocument.objects.first?.id)
        project.activeDocument.parentSelected(to: cubeID)

        let data = try JSONEncoder().encode(MasklarvaProjectFile(project: project))
        let decoded = try JSONDecoder().decode(MasklarvaProjectFile.self, from: data)

        #expect(decoded.formatVersion == MasklarvaProjectFile.currentVersion)
        #expect(decoded.project.scenes.count == 1)
        #expect(decoded.project.activeDocument.objects.count == 2)
        #expect(
            decoded.project.activeDocument.objects.first { $0.id == sphereID }?.parentID
                == cubeID
        )
        #expect(
            decoded.project.activeDocument.objects.first?.editableGeometry.points.count
                == 8
        )
    }

    @Test("Hierarchy rejects cycles and inherits locking")
    func hierarchyInvariants() throws {
        var document = ModelDocument.sample
        document.add(.sphere)
        let childID = try #require(document.selectedID)
        let parentID = try #require(
            document.objects.first { $0.id != childID }?.id
        )
        document.parentSelected(to: parentID)
        document.selectedID = parentID
        document.parentSelected(to: childID)

        #expect(document.objects.first { $0.id == parentID }?.parentID == nil)
        document.toggleSelectedLock()
        #expect(document.isEffectivelyLocked(childID))
    }

    @Test("Group copy and paste preserve a remapped subtree")
    func groupCopyPaste() throws {
        var document = ModelDocument.sample
        let cubeID = try #require(document.selectedID)
        document.add(.sphere)
        let sphereID = try #require(document.selectedID)
        document.groupSelected(with: cubeID)
        let groupID = try #require(document.selectedID)
        document.copySelected()
        document.paste()
        let pastedGroupID = try #require(document.selectedID)

        #expect(pastedGroupID != groupID)
        #expect(document.objects.first { $0.id == pastedGroupID }?.isGroup == true)
        #expect(document.objects.filter { $0.parentID == pastedGroupID }.count == 2)
        #expect(document.objects.contains { $0.id == sphereID })
    }

    @Test("Undo and redo remain chronological across scene operations")
    func chronologicalHistory() {
        var project = MasklarvaProject.sample
        var history = EditorHistory()

        history.begin(project: project)
        project.activeDocument.add(.sphere)
        history.commit(project: project)

        history.begin(project: project)
        project.createScene()
        history.commit(project: project)

        project = history.undo(currentProject: project) ?? project
        #expect(project.scenes.count == 1)
        project = history.undo(currentProject: project) ?? project
        #expect(project.activeDocument.objects.count == 1)
        project = history.redo(currentProject: project) ?? project
        project = history.redo(currentProject: project) ?? project
        #expect(project.scenes.count == 2)
    }

    @Test("Corrupt autosave recovers the previous atomic backup")
    func backupRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let autosaveURL = directory.appending(path: "Autosave.masklarva")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProjectStore(autosaveURL: autosaveURL)
        let firstProject = MasklarvaProject.sample
        try await store.saveAutosave(firstProject)

        var secondProject = firstProject
        secondProject.createScene()
        try await store.saveAutosave(secondProject)
        try Data("corrupt".utf8).write(to: autosaveURL, options: [.atomic])

        let result = try #require(try await store.loadAutosave())
        #expect(result.recoveredFromBackup)
        #expect(result.project.scenes.count == firstProject.scenes.count)
    }

    @Test("Locked objects reject destructive edits")
    func lockedObjectProtection() throws {
        var document = ModelDocument.sample
        let objectID = try #require(document.selectedID)
        document.toggleSelectedLock()
        let originalObject = try #require(
            document.objects.first { $0.id == objectID }
        )

        document.sculptSelected(amount: 0.5)
        document.deleteSelected()

        #expect(document.objects.first { $0.id == objectID } == originalObject)
    }
}
