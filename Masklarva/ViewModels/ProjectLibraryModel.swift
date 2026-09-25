//
//  ProjectLibraryModel.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import CoreTransferable
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ProjectLibraryModel {
    var folders: [ProjectFolder]
    var materials: [ProjectMaterial]
    var selectedFolderID: UUID?
    var isDroppingMaterial = false

    init() {
        let modelsFolder = ProjectFolder(name: "Models", symbol: "cube")
        let materialsFolder = ProjectFolder(
            name: "Materials",
            symbol: "paintpalette.fill"
        )
        let starterMaterials: [ProjectMaterial] = [
            ProjectMaterial(
                name: "Clay",
                red: 0.91,
                green: 0.43,
                blue: 0.25,
                metallic: 0.05,
                roughness: 0.68,
                folderID: materialsFolder.id
            ),
            ProjectMaterial(
                name: "Ocean Metal",
                red: 0.12,
                green: 0.43,
                blue: 0.78,
                metallic: 0.85,
                roughness: 0.2,
                folderID: materialsFolder.id
            ),
            ProjectMaterial(
                name: "Lime Plastic",
                red: 0.42,
                green: 0.82,
                blue: 0.25,
                metallic: 0.05,
                roughness: 0.32,
                folderID: materialsFolder.id
            ),
            ProjectMaterial(
                name: "Soft White",
                red: 0.88,
                green: 0.9,
                blue: 0.94,
                metallic: 0,
                roughness: 0.82,
                folderID: materialsFolder.id
            ),
        ]
        folders = [modelsFolder, materialsFolder]
        materials = starterMaterials
        selectedFolderID = materialsFolder.id
    }

    var visibleMaterials: [ProjectMaterial] {
        guard let selectedFolderID else { return materials }
        return materials.filter { $0.folderID == selectedFolderID }
    }

    func createFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = ProjectFolder(name: name, symbol: "folder.fill")
        folders.append(folder)
        selectedFolderID = folder.id
    }

    func createMaterial() {
        let palette: [(Double, Double, Double)] = [
            (0.92, 0.23, 0.28),
            (0.58, 0.32, 0.92),
            (0.12, 0.72, 0.68),
            (0.95, 0.72, 0.18),
        ]
        let color = palette[materials.count % palette.count]
        materials.append(
            ProjectMaterial(
                name: "Material \(materials.count + 1)",
                red: color.0,
                green: color.1,
                blue: color.2,
                metallic: 0.1,
                roughness: 0.5,
                folderID: selectedFolderID
            )
        )
    }
}

struct ProjectFolder: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var symbol: String
}

struct ProjectMaterial: Identifiable, Codable, Hashable, Transferable {
    var id = UUID()
    var name: String
    var red: Double
    var green: Double
    var blue: Double
    var metallic: Float
    var roughness: Float
    var folderID: UUID?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var editorMaterial: EditorMaterial {
        EditorMaterial(
            color: LinearColor(red: red, green: green, blue: blue),
            metallic: metallic,
            roughness: roughness
        )
    }
}
