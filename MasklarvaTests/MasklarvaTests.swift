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

    @Test("Editable cube owns explicit topology and multi-selection")
    func editableMeshTopologyAndSelection() {
        var geometry = EditableGeometry.cube

        #expect(geometry.points.count == 8)
        #expect(geometry.edges.count == 12)
        #expect(geometry.faces.count == 6)

        geometry.selectAll()
        #expect(geometry.selection.vertexIDs.count == 8)
        geometry.invertSelection()
        #expect(geometry.selection.vertexIDs.isEmpty)

        geometry.setSelectionMode(.edge)
        geometry.selectAll()
        #expect(geometry.selection.edgeIDs.count == 12)

        geometry.setSelectionMode(.face)
        geometry.selectAll()
        #expect(geometry.selection.faceIDs.count == 6)
        geometry.deselectAll()
        #expect(geometry.selection.faceIDs.isEmpty)
    }

    @Test("Legacy geometry derives missing topology and vertex attributes")
    func legacyGeometryMigration() throws {
        let source = EditableGeometry.cube
        let selectedID = try #require(source.points.first?.id)
        let encoded = try JSONEncoder().encode(source)
        var json = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "edges")
        json.removeValue(forKey: "faces")
        json.removeValue(forKey: "selection")
        json["selectedPointID"] = selectedID.uuidString
        if var points = json["points"] as? [[String: Any]] {
            for index in points.indices {
                points[index].removeValue(forKey: "normal")
                points[index].removeValue(forKey: "uv")
                points[index].removeValue(forKey: "tangent")
            }
            json["points"] = points
        }

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(EditableGeometry.self, from: legacyData)

        #expect(decoded.edges.count == 18)
        #expect(decoded.faces.count == 12)
        #expect(decoded.selection.vertexIDs == [selectedID])
        #expect(decoded.points.allSatisfy { $0.normal == [0, 1, 0] })
    }

    @Test("Face deletion rebuilds triangles and participates in undo")
    func faceDeletionUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let faceID = try #require(
            viewModel.document.objects.first?.editableGeometry.faces.first?.id
        )
        viewModel.setMeshSelectionMode(.face)
        let selectedIndex = try #require(viewModel.document.selectedIndex)
        viewModel.document.objects[selectedIndex].editableGeometry
            .selection.faceIDs = [faceID]

        viewModel.deleteSelectedMeshGeometry()

        #expect(viewModel.document.objects[selectedIndex].editableGeometry.faces.count == 5)
        #expect(
            viewModel.document.objects[selectedIndex].editableGeometry.triangleIndices.count
                == 30
        )
        #expect(viewModel.canUndo)

        viewModel.undo()
        #expect(viewModel.document.objects[selectedIndex].editableGeometry.faces.count == 6)
        #expect(
            viewModel.document.objects[selectedIndex].editableGeometry.triangleIndices.count
                == 36
        )
    }

    @Test("Vertex deletion removes incident topology and honors object locking")
    func vertexDeletionAndLocking() throws {
        var document = ModelDocument.sample
        let selectedIndex = try #require(document.selectedIndex)
        let vertexID = try #require(
            document.objects[selectedIndex].editableGeometry.points.first?.id
        )
        document.objects[selectedIndex].editableGeometry.selection.vertexIDs = [vertexID]
        document.toggleSelectedLock()
        document.deleteSelectedGeometry()
        #expect(document.objects[selectedIndex].editableGeometry.points.count == 8)

        document.toggleSelectedLock()
        document.deleteSelectedGeometry()
        let geometry = document.objects[selectedIndex].editableGeometry
        #expect(geometry.points.count == 7)
        #expect(geometry.faces.count == 3)
        #expect(geometry.edges.count == 9)
        #expect(geometry.triangleIndices.count == 18)
        #expect(geometry.selection.vertexIDs.isEmpty)
    }

    @Test("Separating faces creates an independent object and supports undo")
    func separateFacesUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let sourceIndex = try #require(viewModel.document.selectedIndex)
        let source = viewModel.document.objects[sourceIndex]
        let faceID = try #require(source.editableGeometry.faces.first?.id)
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[sourceIndex].editableGeometry.selection.faceIDs = [faceID]

        viewModel.separateSelectedMeshFaces()

        #expect(viewModel.document.objects.count == 2)
        let separatedID = try #require(viewModel.document.selectedID)
        let separated = try #require(
            viewModel.document.objects.first { $0.id == separatedID }
        )
        let remaining = try #require(
            viewModel.document.objects.first { $0.id == source.id }
        )
        #expect(separated.editableGeometry.faces.count == 1)
        #expect(separated.editableGeometry.points.count == 4)
        #expect(separated.editableGeometry.edges.count == 4)
        #expect(separated.editableGeometry.triangleIndices.count == 6)
        #expect(remaining.editableGeometry.faces.count == 5)
        #expect(separated.position == source.position)
        #expect(separated.rotation == source.rotation)
        #expect(separated.scale == source.scale)
        #expect(separated.material == source.material)
        #expect(
            Set(separated.editableGeometry.points.map(\.id)).isDisjoint(
                with: Set(remaining.editableGeometry.points.map(\.id))
            )
        )

        viewModel.undo()
        #expect(viewModel.document.objects.count == 1)
        #expect(viewModel.document.objects.first?.editableGeometry.faces.count == 6)
    }

    @Test("Extruding adjacent faces creates only boundary side walls")
    func extrudeAdjacentFacesUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let faces = viewModel.document.objects[objectIndex].editableGeometry.faces
        let firstFaceID = try #require(faces.first?.id)
        let adjacentFaceID = faces[2].id
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[objectIndex].editableGeometry.selection.faceIDs = [
            firstFaceID,
            adjacentFaceID,
        ]

        viewModel.extrudeSelectedMeshFaces(distance: 0.15)

        let extruded = viewModel.document.objects[objectIndex].editableGeometry
        #expect(extruded.points.count == 14)
        #expect(extruded.faces.count == 12)
        #expect(extruded.edges.count == 24)
        #expect(extruded.triangleIndices.count == 72)
        #expect(extruded.selection.faceIDs == [firstFaceID, adjacentFaceID])
        #expect((extruded.points.map(\.position.y).max() ?? 0) > 0.59)

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.faces.count == 6)
        #expect(restored.edges.count == 12)
    }

    @Test("Extrusion distance supports inward face extrusion")
    func inwardExtrusionDistance() throws {
        var geometry = EditableGeometry.cube
        let faceID = try #require(geometry.faces.first?.id)
        geometry.setSelectionMode(.face)
        geometry.selection.faceIDs = [faceID]

        let didExtrude = geometry.extrudeSelectedFaces(distance: -0.2)
        #expect(didExtrude)

        let cap = try #require(geometry.faces.first { $0.id == faceID })
        let capVertexIDs = Set(cap.vertexIDs)
        let capPoints = geometry.points.filter { capVertexIDs.contains($0.id) }
        #expect(capPoints.count == 4)
        #expect(capPoints.allSatisfy { abs($0.position.y - 0.25) < 0.000_1 })
    }

    @Test("Face inset creates an inner cap and border ring with undo")
    func faceInsetUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let faceID = try #require(
            viewModel.document.objects[objectIndex].editableGeometry.faces.first?.id
        )
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[objectIndex].editableGeometry.selection.faceIDs = [
            faceID
        ]

        viewModel.insetSelectedMeshFaces(amount: 0.25)

        let inset = viewModel.document.objects[objectIndex].editableGeometry
        let cap = try #require(inset.faces.first { $0.id == faceID })
        let capVertexIDs = Set(cap.vertexIDs)
        let capPoints = inset.points.filter { capVertexIDs.contains($0.id) }
        #expect(inset.points.count == 12)
        #expect(inset.faces.count == 10)
        #expect(inset.edges.count == 20)
        #expect(inset.triangleIndices.count == 60)
        #expect(inset.selection.faceIDs == [faceID])
        #expect(capPoints.count == 4)
        #expect(capPoints.allSatisfy { abs(abs($0.position.x) - 0.3375) < 0.000_1 })
        #expect(capPoints.allSatisfy { abs(abs($0.position.z) - 0.3375) < 0.000_1 })

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.faces.count == 6)
        #expect(restored.edges.count == 12)
    }

    @Test("Single-edge bevel creates a chamfer face and supports undo")
    func singleEdgeBevelUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let edgeID = try #require(
            viewModel.document.objects[objectIndex].editableGeometry.edges.first?.id
        )
        viewModel.setMeshSelectionMode(.edge)
        viewModel.document.objects[objectIndex].editableGeometry.selection.edgeIDs = [
            edgeID
        ]

        viewModel.bevelSelectedMeshEdge(width: 0.1)

        let beveled = viewModel.document.objects[objectIndex].editableGeometry
        #expect(beveled.points.count == 12)
        #expect(beveled.faces.count == 7)
        #expect(beveled.edges.count == 19)
        #expect(beveled.triangleIndices.count == 42)
        #expect(beveled.selection.edgeIDs.isEmpty)

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.faces.count == 6)
        #expect(restored.edges.count == 12)
    }

    @Test("Boundary edges reject manifold bevel")
    func boundaryEdgeBevelRejection() throws {
        let first = MeshControlPoint(position: [0, 0, 0])
        let second = MeshControlPoint(position: [1, 0, 0])
        let third = MeshControlPoint(position: [0, 1, 0])
        var geometry = EditableGeometry(
            points: [first, second, third],
            triangleIndices: [0, 1, 2]
        )
        geometry.setSelectionMode(.edge)
        let edgeID = try #require(geometry.edges.first?.id)
        geometry.selection.edgeIDs = [edgeID]

        let didBevel = geometry.bevelSelectedEdge(width: 0.1)

        #expect(!didBevel)
        #expect(geometry.points.count == 3)
        #expect(geometry.faces.count == 1)
    }

    @Test("Welding vertices preserves a stable survivor and supports undo")
    func weldVerticesUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let originalPoints = viewModel.document.objects[objectIndex]
            .editableGeometry.points
        let survivorID = originalPoints[0].id
        let mergedID = originalPoints[1].id
        let firstJointID = UUID()
        let secondJointID = UUID()
        viewModel.document.objects[objectIndex].editableGeometry.weights = [
            VertexWeight(pointID: survivorID, jointID: firstJointID, weight: 1),
            VertexWeight(pointID: mergedID, jointID: secondJointID, weight: 1),
        ]
        viewModel.document.objects[objectIndex].editableGeometry.selection.vertexIDs = [
            survivorID,
            mergedID,
        ]

        viewModel.weldSelectedMeshVertices()

        let welded = viewModel.document.objects[objectIndex].editableGeometry
        let survivor = try #require(welded.points.first { $0.id == survivorID })
        #expect(welded.points.count == 7)
        #expect(welded.faces.count == 6)
        #expect(welded.edges.count == 11)
        #expect(welded.triangleIndices.count == 30)
        #expect(survivor.position == [0, 0.45, -0.45])
        #expect(welded.selection.vertexIDs == [survivorID])
        #expect(welded.weights.count == 2)
        #expect(abs(welded.weights.reduce(0) { $0 + $1.weight } - 1) < 0.000_1)

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.edges.count == 12)
        #expect(restored.selection.vertexIDs == [survivorID, mergedID])
    }

    @Test("Duplicate in place supports vertex and edge selections")
    func duplicateVertexAndEdgeGeometry() throws {
        var vertexGeometry = EditableGeometry.cube
        let vertexID = try #require(vertexGeometry.points.first?.id)
        let jointID = UUID()
        vertexGeometry.weights = [
            VertexWeight(pointID: vertexID, jointID: jointID, weight: 1)
        ]
        vertexGeometry.selection.vertexIDs = [vertexID]
        let didDuplicateVertex = vertexGeometry.duplicateSelectedGeometry()
        let duplicatedVertexID = try #require(
            vertexGeometry.selection.vertexIDs.first
        )
        #expect(didDuplicateVertex)
        #expect(vertexGeometry.points.count == 9)
        #expect(duplicatedVertexID != vertexID)
        #expect(
            vertexGeometry.points.first { $0.id == duplicatedVertexID }?.position
                == vertexGeometry.points.first { $0.id == vertexID }?.position
        )
        #expect(vertexGeometry.weights.contains { $0.pointID == duplicatedVertexID })

        var edgeGeometry = EditableGeometry.cube
        edgeGeometry.setSelectionMode(.edge)
        let edgeID = try #require(edgeGeometry.edges.first?.id)
        edgeGeometry.selection.edgeIDs = [edgeID]
        let didDuplicateEdge = edgeGeometry.duplicateSelectedGeometry()
        #expect(didDuplicateEdge)
        #expect(edgeGeometry.points.count == 10)
        #expect(edgeGeometry.edges.count == 13)
        #expect(edgeGeometry.faces.count == 6)
        #expect(edgeGeometry.triangleIndices.count == 36)
        #expect(edgeGeometry.selection.edgeIDs.count == 1)
        #expect(!edgeGeometry.selection.edgeIDs.contains(edgeID))
    }

    @Test("Face duplication remaps topology and supports undo")
    func duplicateFaceGeometryUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let faceID = try #require(
            viewModel.document.objects[objectIndex].editableGeometry.faces.first?.id
        )
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[objectIndex].editableGeometry.selection.faceIDs = [
            faceID
        ]

        viewModel.duplicateSelectedMeshGeometry()

        let duplicated = viewModel.document.objects[objectIndex].editableGeometry
        #expect(duplicated.points.count == 12)
        #expect(duplicated.edges.count == 16)
        #expect(duplicated.faces.count == 7)
        #expect(duplicated.triangleIndices.count == 42)
        #expect(duplicated.selection.faceIDs.count == 1)
        #expect(!duplicated.selection.faceIDs.contains(faceID))

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.edges.count == 12)
        #expect(restored.faces.count == 6)
    }

    @Test("Duplicate and move offsets only the duplicated selection")
    func duplicateAndMoveFaceUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let sourceGeometry = viewModel.document.objects[objectIndex].editableGeometry
        let sourceFace = try #require(sourceGeometry.faces.first)
        let sourceVertexIDs = Set(sourceFace.vertexIDs)
        let sourcePositions = sourceGeometry.points
            .filter { sourceVertexIDs.contains($0.id) }
            .map(\.position)
        let offset = SIMD3<Float>(0.5, -0.25, 1)
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[objectIndex].editableGeometry.selection.faceIDs = [
            sourceFace.id
        ]

        viewModel.duplicateSelectedMeshGeometry(offset: offset)

        let movedGeometry = viewModel.document.objects[objectIndex].editableGeometry
        let movedFaceID = try #require(movedGeometry.selection.faceIDs.first)
        let movedFace = try #require(
            movedGeometry.faces.first { $0.id == movedFaceID }
        )
        let movedVertexIDs = Set(movedFace.vertexIDs)
        let movedPositions = movedGeometry.points
            .filter { movedVertexIDs.contains($0.id) }
            .map(\.position)
        #expect(sourcePositions.allSatisfy { sourcePosition in
            movedPositions.contains { movedPosition in
                let delta = movedPosition - sourcePosition - offset
                return abs(delta.x) < 0.000_1
                    && abs(delta.y) < 0.000_1
                    && abs(delta.z) < 0.000_1
            }
        })
        #expect(
            sourcePositions.allSatisfy {
                movedGeometry.points.map(\.position).contains($0)
            }
        )

        viewModel.undo()
        #expect(viewModel.document.objects[objectIndex].editableGeometry.points.count == 8)
        #expect(viewModel.document.objects[objectIndex].editableGeometry.faces.count == 6)
    }

    @Test("Flipping one face splits shared normals and supports undo")
    func flipSingleFaceNormalsUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let faceID = try #require(
            viewModel.document.objects[objectIndex].editableGeometry.faces.first?.id
        )
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[objectIndex].editableGeometry.selection.faceIDs = [
            faceID
        ]

        viewModel.flipSelectedMeshFaceNormals()

        let flipped = viewModel.document.objects[objectIndex].editableGeometry
        let flippedFace = try #require(flipped.faces.first { $0.id == faceID })
        let flippedVertexIDs = Set(flippedFace.vertexIDs)
        let otherVertexIDs = Set(
            flipped.faces
                .filter { $0.id != faceID }
                .flatMap(\.vertexIDs)
        )
        #expect(flipped.points.count == 12)
        #expect(flipped.edges.count == 16)
        #expect(flipped.faces.count == 6)
        #expect(flipped.triangleIndices.count == 36)
        #expect(flipped.selection.faceIDs == [faceID])
        #expect(flippedVertexIDs.isDisjoint(with: otherVertexIDs))
        #expect(
            flipped.points
                .filter { flippedVertexIDs.contains($0.id) }
                .allSatisfy { $0.tangent.w == -1 }
        )

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.edges.count == 12)
    }

    @Test("Flipping the complete mesh reverses calculated normals")
    func flipCompleteMeshNormals() throws {
        var geometry = EditableGeometry.cube
        let originalPoints = Dictionary(
            uniqueKeysWithValues: geometry.points.map { ($0.id, $0.position) }
        )
        let originalNormals = Dictionary(
            uniqueKeysWithValues: geometry.faces.map { face in
                (face.id, faceNormal(face, points: originalPoints))
            }
        )
        geometry.setSelectionMode(.face)
        geometry.selectAll()

        let didFlip = geometry.flipSelectedFaceNormals()

        #expect(didFlip)
        #expect(geometry.points.count == 8)
        #expect(geometry.edges.count == 12)
        let flippedPoints = Dictionary(
            uniqueKeysWithValues: geometry.points.map { ($0.id, $0.position) }
        )
        for face in geometry.faces {
            let original = try #require(originalNormals[face.id])
            let flipped = faceNormal(face, points: flippedPoints)
            let dot = original.x * flipped.x
                + original.y * flipped.y
                + original.z * flipped.z
            #expect(dot < -0.99)
        }
    }

    private func faceNormal(
        _ face: MeshFace,
        points: [UUID: SIMD3<Float>]
    ) -> SIMD3<Float> {
        guard face.vertexIDs.count >= 3,
            let first = points[face.vertexIDs[0]],
            let second = points[face.vertexIDs[1]],
            let third = points[face.vertexIDs[2]]
        else { return .zero }
        let a = second - first
        let b = third - first
        let cross = SIMD3<Float>(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
        let length = sqrt(
            cross.x * cross.x + cross.y * cross.y + cross.z * cross.z
        )
        return length > 0.000_001 ? cross / length : .zero
    }

    @Test("Linear subdivision shares edge midpoints and supports undo")
    func linearSubdivisionUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let source = viewModel.document.objects[objectIndex].editableGeometry
        let selectedFaceID = try #require(source.faces.first?.id)
        let sourcePointIDs = Set(source.points.map(\.id))
        let sourceFaceIDs = Set(source.faces.map(\.id))
        viewModel.setMeshSelectionMode(.face)
        viewModel.document.objects[objectIndex].editableGeometry.selection.faceIDs = [
            selectedFaceID
        ]

        viewModel.linearSubdivideSelectedMesh()

        let subdivided = viewModel.document.objects[objectIndex].editableGeometry
        #expect(subdivided.points.count == 26)
        #expect(subdivided.edges.count == 48)
        #expect(subdivided.faces.count == 24)
        #expect(subdivided.triangleIndices.count == 144)
        #expect(sourcePointIDs.isSubset(of: Set(subdivided.points.map(\.id))))
        #expect(sourceFaceIDs.isSubset(of: Set(subdivided.faces.map(\.id))))
        #expect(subdivided.selection.faceIDs.count == 4)
        #expect(subdivided.selection.faceIDs.contains(selectedFaceID))

        viewModel.undo()
        let restored = viewModel.document.objects[objectIndex].editableGeometry
        #expect(restored.points.count == 8)
        #expect(restored.edges.count == 12)
        #expect(restored.faces.count == 6)
        #expect(restored.selection.faceIDs == [selectedFaceID])
    }

    @Test("Catmull-Clark subdivision blends smoothing strength and supports undo")
    func catmullClarkSubdivisionUndo() throws {
        let viewModel = EditorViewModel(document: .sample)
        let objectIndex = try #require(viewModel.document.selectedIndex)
        let cornerID = try #require(
            viewModel.document.objects[objectIndex].editableGeometry.points.first?.id
        )

        viewModel.catmullClarkSubdivideSelectedMesh(strength: 0.5)

        let subdivided = viewModel.document.objects[objectIndex].editableGeometry
        let corner = try #require(subdivided.points.first { $0.id == cornerID })
        #expect(subdivided.points.count == 26)
        #expect(subdivided.edges.count == 48)
        #expect(subdivided.faces.count == 24)
        #expect(abs(corner.position.x - 0.35) < 0.000_1)
        #expect(abs(corner.position.y - 0.35) < 0.000_1)
        #expect(abs(corner.position.z + 0.35) < 0.000_1)

        viewModel.undo()
        let restoredCorner = try #require(
            viewModel.document.objects[objectIndex].editableGeometry.points.first {
                $0.id == cornerID
            }
        )
        #expect(restoredCorner.position == [0.45, 0.45, -0.45])
    }

    @Test("Mesh validation accepts the canonical cube")
    func validCubeReport() {
        let report = EditableGeometry.cube.validationReport()

        #expect(report.isValid)
        #expect(report.errorCount == 0)
        #expect(report.warningCount == 0)
        #expect(report.vertexCount == 8)
        #expect(report.edgeCount == 12)
        #expect(report.faceCount == 6)
        #expect(report.triangleCount == 12)
    }

    @Test("Mesh validation reports structural topology failures")
    func invalidTopologyReport() {
        let first = MeshControlPoint(position: [0, 0, 0])
        let second = MeshControlPoint(position: [1, 0, 0])
        let third = MeshControlPoint(position: [0, 1, 0])
        let fourth = MeshControlPoint(position: [0, -1, 0])
        let fifth = MeshControlPoint(position: [0, 0, 1])
        let orphan = MeshControlPoint(position: [4, 4, 4])
        let sharedEdge = MeshEdge(vertexIDs: [first.id, second.id])
        let geometry = EditableGeometry(
            points: [first, second, third, fourth, fifth, orphan],
            triangleIndices: [0, 1, 99, 0],
            edges: [
                sharedEdge,
                MeshEdge(vertexIDs: [first.id, second.id]),
            ],
            faces: [
                MeshFace(vertexIDs: [first.id, second.id, third.id]),
                MeshFace(vertexIDs: [second.id, first.id, fourth.id]),
                MeshFace(vertexIDs: [first.id, second.id, fifth.id]),
            ]
        )

        let report = geometry.validationReport()
        let kinds = Set(report.issues.map(\.kind))

        #expect(!report.isValid)
        #expect(kinds.contains(.incompleteTriangleIndices))
        #expect(kinds.contains(.invalidTriangleIndex))
        #expect(kinds.contains(.triangleCountMismatch))
        #expect(kinds.contains(.duplicateEdge))
        #expect(kinds.contains(.missingTopologyEdge))
        #expect(kinds.contains(.nonManifoldEdge))
        #expect(kinds.contains(.orphanVertex))
    }
}
