//
//  ProjectLibraryPanel.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import SwiftUI

struct ProjectLibraryPanel: View {
    @Bindable var library: ProjectLibraryModel
    let selectedObjectName: String
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Projekt", systemImage: "folder.fill")
                    .font(.headline)
                Text("→ \(selectedObjectName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Ordner", systemImage: "folder.badge.plus") {
                    isCreatingFolder = true
                }
                Button("Material", systemImage: "plus") {
                    library.createMaterial()
                }
            }
            .labelStyle(.iconOnly)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(library.folders) { folder in
                        Button {
                            library.selectedFolderID = folder.id
                        } label: {
                            Label(folder.name, systemImage: folder.symbol)
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            library.selectedFolderID == folder.id
                                ? Color.accentColor : .secondary
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(library.visibleMaterials) { material in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(material.color.gradient)
                                .frame(width: 64, height: 52)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "hand.draw")
                                        .font(.caption2)
                                        .padding(5)
                                }
                            Text(material.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 76)
                        }
                        .draggable(material) {
                            Label(material.name, systemImage: "paintbrush.fill")
                                .padding(10)
                                .background(.regularMaterial)
                        }
                    }

                    if library.visibleMaterials.isEmpty {
                        ContentUnavailableView(
                            "Leerer Ordner",
                            systemImage: "folder"
                        )
                        .frame(width: 180, height: 75)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .alert("Neuer Ordner", isPresented: $isCreatingFolder) {
            TextField("Ordnername", text: $newFolderName)
            Button("Erstellen") {
                library.createFolder(named: newFolderName)
                newFolderName = ""
            }
            Button("Abbrechen", role: .cancel) {
                newFolderName = ""
            }
        }
    }
}
