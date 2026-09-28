//
//  HomeView.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import CoreTransferable
import Observation
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = EditorViewModel()
    @State private var isToolShelfVisible = false
    @State private var isInspectorVisible = false
    @State private var isProjectPanelVisible = false
    @State private var projectPanelDetent: PresentationDetent = .height(190)
    @State private var isRenamingObject = false
    @State private var objectNameDraft = ""
    @State private var isRenamingScene = false
    @State private var sceneNameDraft = ""
    @State private var isConfirmingSceneDeletion = false

    var body: some View {
        editorWorkspace
            .preferredColorScheme(.dark)
    }

    private var editorWorkspace: some View {
        NavigationStack {
            ZStack {
                Color.editorBackground.ignoresSafeArea()
                ZStack {
                    viewport
                    toolShelf
                    inspectorShelf
                }
            }
            .toolbar { editorToolbar }
            .sheet(isPresented: $isProjectPanelVisible) {
                ProjectLibraryPanel(
                    library: viewModel.projectLibrary,
                    selectedObjectName: viewModel.selectedObjectName
                )
                .presentationDetents(
                    [.height(190), .medium, .large],
                    selection: $projectPanelDetent
                )
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
            }
            .sheet(item: $viewModel.exportArtifact) { artifact in
                VStack(spacing: 20) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("\(artifact.format.title) ist bereit")
                        .font(.headline)
                    ShareLink(
                        item: artifact.url,
                        preview: SharePreview(
                            artifact.url.lastPathComponent,
                            image: Image(systemName: "cube.transparent")
                        )
                    ) {
                        Label(
                            "Datei teilen oder sichern",
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
            }
            .alert("Objekt umbenennen", isPresented: $isRenamingObject) {
                TextField("Name", text: $objectNameDraft)
                Button("Umbenennen") {
                    viewModel.renameSelection(to: objectNameDraft)
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Szene umbenennen", isPresented: $isRenamingScene) {
                TextField("Name", text: $sceneNameDraft)
                Button("Umbenennen") {
                    viewModel.renameScene(to: sceneNameDraft)
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog(
                "\"\(viewModel.project.activeSceneName)\" löschen?",
                isPresented: $isConfirmingSceneDeletion,
                titleVisibility: .visible
            ) {
                Button("Szene löschen", role: .destructive) {
                    viewModel.deleteScene()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Szene und alle enthaltenen Objekte werden entfernt.")
            }
            .alert(
                "Projektfehler",
                isPresented: Binding(
                    get: { viewModel.projectStorageError != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.projectStorageError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.projectStorageError ?? "Unbekannter Fehler")
            }
            .task {
                await viewModel.loadAutosavedProject()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    viewModel.saveProject()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {

        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu("Form", systemImage: "plus") {
                ForEach(PrimitiveKind.allCases) { kind in
                    Button(kind.title, systemImage: kind.symbol) {
                        viewModel.addPrimitive(kind)
                    }
                }
            }

            Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                viewModel.undo()
            }
            .disabled(!viewModel.canUndo)

            Button("Wiederholen", systemImage: "arrow.uturn.forward") {
                viewModel.redo()
            }
            .disabled(!viewModel.canRedo)

            Menu("Projekt", systemImage: "folder") {
                Button("Projektbibliothek", systemImage: "folder") {
                    isProjectPanelVisible = true
                }
                Button("Jetzt sichern", systemImage: "square.and.arrow.down") {
                    viewModel.saveProject()
                }
                .disabled(viewModel.isSavingProject)
                if let lastSavedAt = viewModel.lastSavedAt {
                    Text("Gesichert: \(lastSavedAt, format: .dateTime.hour().minute().second())")
                }
            }

            Menu("Szene", systemImage: "square.stack.3d.up") {
                Section("Szenen") {
                    ForEach(viewModel.project.scenes) { scene in
                        Button {
                            viewModel.selectScene(scene.id)
                        } label: {
                            if scene.id == viewModel.project.activeSceneID {
                                Label(scene.name, systemImage: "checkmark")
                            } else {
                                Text(scene.name)
                            }
                        }
                    }
                }
                Section {
                    Button("Neue Szene", systemImage: "plus") {
                        viewModel.createScene()
                    }
                    Button("Szene duplizieren", systemImage: "plus.square.on.square") {
                        viewModel.duplicateScene()
                    }
                    Button("Szene umbenennen", systemImage: "pencil") {
                        sceneNameDraft = viewModel.project.activeSceneName
                        isRenamingScene = true
                    }
                    Button("Szene löschen", systemImage: "trash", role: .destructive) {
                        isConfirmingSceneDeletion = true
                    }
                    .disabled(!viewModel.project.canDeleteScene)
                }
            }

            Menu("Objekt", systemImage: "cube") {
                Button("Umbenennen", systemImage: "pencil") {
                    objectNameDraft = viewModel.selectedObjectName
                    isRenamingObject = true
                }
                Button("Duplizieren", systemImage: "plus.square.on.square") {
                    viewModel.duplicateSelection()
                }
                Menu("Überordnen", systemImage: "arrow.turn.down.right") {
                    ForEach(viewModel.parentCandidates) { object in
                        Button(object.name) {
                            viewModel.parentSelection(to: object.id)
                        }
                    }
                    Divider()
                    Button("Überordnung lösen", systemImage: "arrow.uturn.backward") {
                        viewModel.unparentSelection()
                    }
                    .disabled(!viewModel.selectedObjectHasParent)
                }
                Menu("Gruppieren", systemImage: "folder.badge.plus") {
                    if viewModel.selectedObjectIsGroup {
                        Button("Gruppe auflösen", systemImage: "folder.badge.minus") {
                            viewModel.ungroupSelection()
                        }
                    } else {
                        ForEach(viewModel.groupCandidates) { object in
                            Button("Mit \(object.name)") {
                                viewModel.groupSelection(with: object.id)
                            }
                        }
                    }
                }
                Divider()
                Button("Kopieren", systemImage: "doc.on.doc") {
                    viewModel.copySelection()
                }
                Button("Ausschneiden", systemImage: "scissors") {
                    viewModel.cutSelection()
                }
                .disabled(viewModel.selectedObjectIsLocked)
                Button("Einsetzen", systemImage: "doc.on.clipboard") {
                    viewModel.paste()
                }
                .disabled(!viewModel.canPaste)
                Divider()
                Button(
                    viewModel.selectedObjectIsLocked ? "Entsperren" : "Sperren",
                    systemImage: viewModel.selectedObjectIsLocked ? "lock.open" : "lock"
                ) {
                    viewModel.toggleSelectionLock()
                }
                Button("Löschen", systemImage: "trash", role: .destructive) {
                    viewModel.deleteSelection()
                }
                .disabled(viewModel.selectedObjectIsLocked)
            }
            .disabled(viewModel.document.selectedIndex == nil && !viewModel.canPaste)

            Menu("Export", systemImage: "square.and.arrow.up") {
                ForEach(SceneExportFormat.allCases) { format in
                    Button(
                        "Als \(format.title) exportieren",
                        systemImage: format == .usdz
                            ? "shippingbox" : "doc.text"
                    ) {
                        viewModel.export(format)
                    }
                }
            }

            Menu("Kamera", systemImage: viewModel.cameraMode.symbol) {
                Picker("Kamerasteuerung", selection: $viewModel.cameraMode) {
                    ForEach(CameraNavigationMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Button("Ansicht zentrieren", systemImage: "scope") {
                    viewModel.resetCamera()
                }
                Button("Auswahl fokussieren", systemImage: "viewfinder") {
                    viewModel.focusSelectedObject()
                }
                Divider()
                Button("Vergrößern", systemImage: "plus.magnifyingglass") {
                    viewModel.zoomIn()
                }
                Button("Verkleinern", systemImage: "minus.magnifyingglass") {
                    viewModel.zoomOut()
                }
            }
        }
    }

    private var inspectorShelf: some View {
        HStack(spacing: 6) {
            Spacer()

            Button(
                isInspectorVisible ? "Inspector schließen" : "Inspector öffnen",
                systemImage: isInspectorVisible
                    ? "chevron.right" : "chevron.left"
            ) {
                withAnimation(.snappy) {
                    isInspectorVisible.toggle()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .accessibilityLabel(
                isInspectorVisible ? "Inspector schließen" : "Inspector öffnen"
            )

            if isInspectorVisible {
                EditorInspectorPanel(
                    viewModel: viewModel,
                    selectedTool: viewModel.selectedTool
                )
                .frame(width: 220)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(8)
    }

    private var toolShelf: some View {
        HStack(spacing: 0) {
            if isToolShelfVisible {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ShelfSection("WERKZEUGE") {
                            ForEach(EditorTool.allCases) { tool in
                                Button {
                                    viewModel.selectTool(tool)
                                } label: {
                                    Label(tool.title, systemImage: tool.symbol)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading
                                        )
                                        .padding(.vertical, 7)
                                }
                                .buttonStyle(.bordered)
                                .tint(
                                    viewModel.selectedTool == tool
                                        ? Color.accentColor : .secondary
                                )
                            }
                        }

                        if viewModel.selectedTool == .points {
                            ShelfSection("MESH-AUSWAHL") {
                                MeshSelectionControls(viewModel: viewModel)
                            }
                        }

                        ShelfSection("FORMEN") {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                ],
                                spacing: 8
                            ) {
                                ForEach(PrimitiveKind.allCases) { kind in
                                    Button {
                                        viewModel.addPrimitive(kind)
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: kind.symbol)
                                                .font(.title3)
                                            Text(kind.title)
                                                .font(.caption2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 55)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        ShelfSection("AUSWAHL") {
                            SceneHierarchyPanel(viewModel: viewModel)
                        }
                    }
                    .padding(12)
                }
                .frame(width: 190)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .padding(.leading, 8)
                .padding(.vertical, 8)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button(
                isToolShelfVisible ? "Werkzeuge schließen" : "Werkzeuge öffnen",
                systemImage: isToolShelfVisible
                    ? "chevron.left" : "chevron.right"
            ) {
                withAnimation(.snappy) {
                    isToolShelfVisible.toggle()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .padding(.leading, 6)

            Spacer()
        }
    }

    private var viewport: some View {
        ZStack(alignment: .topLeading) {
            RealityViewport(
                document: $viewModel.document,
                selectedTool: $viewModel.selectedTool,
                orbit: $viewModel.orbit,
                zoom: $viewModel.zoom,
                cameraPan: $viewModel.cameraPan,
                cameraMode: $viewModel.cameraMode,
                beginProjectChange: viewModel.beginChange,
                endProjectChange: viewModel.endChange
            )
            .dropDestination(for: ProjectMaterial.self) { materials, _ in
                guard let material = materials.first else { return false }
                return viewModel.apply(material)
            } isTargeted: { isTargeted in
                viewModel.setMaterialDropTargeted(isTargeted)
            }

            LinearGradient(
                colors: [.black.opacity(0.24), .clear, .black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                Label(
                    viewModel.project.activeSceneName,
                    systemImage: "view.3d"
                )
                Spacer()
                Label(
                    "\(viewModel.objectCount)",
                    systemImage: "cube.transparent"
                )
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.7))
            .padding()

            if viewModel.projectLibrary.isDroppingMaterial {
                VStack {
                    Spacer()
                    Label(
                        "Auf \(viewModel.selectedObjectName) anwenden",
                        systemImage: "paintbrush.pointed.fill"
                    )
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(.blue), in: .capsule)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ViewportButton(symbol: "scope") {
                            viewModel.resetOrbitAndZoom()
                        }
                        ViewportButton(symbol: "square.grid.3x3") {
                            viewModel.toggleGrid()
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }

}

extension Color {
    static let editorBackground = Color(
        red: 0.055,
        green: 0.06,
        blue: 0.075
    )
}

#Preview {
    HomeView()
}
