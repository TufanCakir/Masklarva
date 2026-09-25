//
//  ExportModels.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation

enum SceneExportFormat: String, CaseIterable, Identifiable {
    case usdz
    case usda
    case reality
    case scn

    var id: Self { self }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

struct ExportArtifact: Identifiable {
    let id = UUID()
    let url: URL
    let format: SceneExportFormat
}
