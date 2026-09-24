//
//  HomeView.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import RealityKit
import SwiftUI

struct HomeView: View {
    @State private var document = ModelDocument.sample
    @State private var selectedTool: EditorTool = .move
    @State private var inspector: InspectorPanel = .transform
    @State private var isObjectBrowserPresented = false
    @State private var isAddMenuPresented = false
    @State private var orbit = CGSize.zero
    @State private var zoom: Float = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.editorBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    projectBar
                    viewport
                    objectStrip
                    inspectorPanel
                    toolBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isObjectBrowserPresented) {
                ObjectBrowser(document: $document)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Form hinzufügen",
                isPresented: $isAddMenuPresented
            ) {
                ForEach(PrimitiveKind.allCases) { kind in
                    Button(kind.title) { document.add(kind) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var projectBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("UNTITLED SCENE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("Clay Studio")
                    .font(.headline)
            }

            Spacer()

            Button {
                document.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!document.canUndo)

            Menu {
                Button("USDZ exportieren", systemImage: "shippingbox") {
                    document.showExportNotice = true
                }
                Button("Duplizieren", systemImage: "plus.square.on.square") {
                    document.duplicateSelected()
                }
                Divider()
                Button(
                    "Auswahl löschen",
                    systemImage: "trash",
                    role: .destructive
                ) { document.deleteSelected() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 54)
        .alert("USDKit Export", isPresented: $document.showExportNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Die Szene ist exportbereit. Der finale USDKit-Writer kann Meshes, Materialien, Hierarchie und Animation als USDZ paketieren."
            )
        }
    }

    private var viewport: some View {
        ZStack(alignment: .topLeading) {
            RealityViewport(document: document, orbit: orbit, zoom: zoom)
                .id(document.revision)

            LinearGradient(
                colors: [.black.opacity(0.24), .clear, .black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: 7) {
                Label("PERSPEKTIVE", systemImage: "view.3d")
                Spacer()
                Label(
                    "\(document.objects.count)",
                    systemImage: "cube.transparent"
                )
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.7))
            .padding(12)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        viewportButton("scope") {
                            orbit = .zero
                            zoom = 1
                        }
                        viewportButton("square.grid.3x3") {
                            document.gridVisible.toggle()
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture()
                .onChanged { orbit = $0.translation }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { zoom = Float($0.magnification) }
        )
    }

    private func viewportButton(_ symbol: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(
                    .black.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
    }

    private var objectStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    isAddMenuPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(
                            Color.accentColor,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }

                ForEach(document.objects) { object in
                    Button {
                        document.selectedID = object.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: object.kind.symbol)
                            Text(object.name)
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 42)
                        .background(
                            document.selectedID == object.id
                                ? Color.accentColor.opacity(0.28)
                                : .white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    document.selectedID == object.id
                                        ? Color.accentColor : .clear,
                                    lineWidth: 1
                                )
                        }
                    }
                }

                Button {
                    isObjectBrowserPresented = true
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 42, height: 42)
                        .background(
                            .white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 60)
        .background(.black.opacity(0.2))
    }

    private var inspectorPanel: some View {
        VStack(spacing: 10) {
            Picker("Inspektor", selection: $inspector) {
                ForEach(InspectorPanel.allCases) { panel in
                    Label(panel.title, systemImage: panel.symbol).tag(panel)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch inspector {
                case .transform:
                    transformInspector
                case .material:
                    materialInspector
                case .light:
                    lightInspector
                }
            }
            .frame(height: 76)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var transformInspector: some View {
        if let selected = document.selectedIndex {
            HStack(spacing: 12) {
                AxisSlider(
                    axis: "X",
                    color: .red,
                    value: $document.objects[selected].position.x
                )
                AxisSlider(
                    axis: "Y",
                    color: .green,
                    value: $document.objects[selected].position.y
                )
                AxisSlider(
                    axis: "Z",
                    color: .blue,
                    value: $document.objects[selected].position.z
                )
            }
            .onChange(of: document.objects[selected].position) { _, _ in
                document.commitChange()
            }
        } else {
            ContentUnavailableView(
                "Kein Objekt",
                systemImage: "cube.transparent"
            )
        }
    }

    @ViewBuilder
    private var materialInspector: some View {
        if let selected = document.selectedIndex {
            HStack(spacing: 14) {
                ColorPicker(
                    "Farbe",
                    selection: $document.objects[selected].material.color,
                    supportsOpacity: false
                )
                .labelsHidden()
                MaterialSlider(
                    title: "Metall",
                    value: $document.objects[selected].material.metallic
                )
                MaterialSlider(
                    title: "Rau",
                    value: $document.objects[selected].material.roughness
                )
                Button {
                    document.objects[selected].material.textureIndex =
                        (document.objects[selected].material.textureIndex + 1)
                        % 4
                    document.commitChange()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "circle.hexagongrid.fill")
                        Text(
                            "Textur (document.objects[selected].material.textureIndex + 1)"
                        )
                    }
                    .font(.caption2)
                }
            }
            .onChange(of: document.objects[selected].material) { _, _ in
                document.commitChange()
            }
        }
    }

    private var lightInspector: some View {
        HStack(spacing: 14) {
            ColorPicker(
                "Licht",
                selection: $document.light.color,
                supportsOpacity: false
            )
            .labelsHidden()
            MaterialSlider(
                title: "Stärke",
                value: $document.light.intensity,
                range: 0.1...2
            )
            Toggle(isOn: $document.light.castsShadow) {
                Label("Schatten", systemImage: "circle.lefthalf.filled")
                    .font(.caption2)
            }
            .toggleStyle(.button)
            .onChange(of: document.light) { _, _ in document.commitChange() }
        }
    }

    private var toolBar: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    selectedTool = tool
                    if tool == .sculpt { document.sculptSelected(amount: 0.08) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tool.title)
                            .font(.caption2)
                    }
                    .foregroundStyle(
                        selectedTool == tool ? Color.accentColor : .secondary
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.editorBackground)
    }
}

private struct RealityViewport: View {
    let document: ModelDocument
    let orbit: CGSize
    let zoom: Float

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "EditorRoot"

            for object in document.objects {
                root.addChild(
                    makeEntity(
                        for: object,
                        selected: object.id == document.selectedID
                    )
                )
            }

            if document.gridVisible {
                root.addChild(makeGrid())
            }

            let light = Entity()
            light.name = "KeyLight"
            light.components.set(
                DirectionalLightComponent(
                    color: UIColor(document.light.color),
                    intensity: document.light.intensity * 1800,
                    isRealWorldProxy: false
                )
            )
            light.orientation = simd_quatf(angle: -.pi / 3, axis: [1, -0.5, 0])
            root.addChild(light)

            let camera = Entity()
            camera.components.set(
                PerspectiveCameraComponent(
                    near: 0.01,
                    far: 100,
                    fieldOfViewInDegrees: 48
                )
            )
            let yaw = Float(orbit.width) * 0.006
            let pitch = max(-0.9, min(0.9, Float(orbit.height) * 0.005))
            let distance = max(1.8, 4.2 / max(zoom, 0.45))
            let position = SIMD3<Float>(
                sin(yaw) * distance,
                1.3 + pitch * 1.5,
                cos(yaw) * distance
            )
            camera.look(at: [0, 0.45, 0], from: position, relativeTo: nil)
            root.addChild(camera)

            content.add(root)
        }
    }

    private func makeEntity(for object: SceneObject, selected: Bool)
        -> ModelEntity
    {
        let mesh: MeshResource =
            switch object.kind {
            case .sphere: .generateSphere(radius: 0.48)
            case .cube: .generateBox(size: 0.9, cornerRadius: 0.06)
            case .cylinder: .generateCylinder(height: 1, radius: 0.42)
            case .cone: .generateCone(height: 1.1, radius: 0.5)
            case .capsule: .generateCylinder(height: 1.15, radius: 0.36)
            case .plane:
                .generateBox(size: [1.4, 0.05, 1.4], cornerRadius: 0.015)
            }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(object.material.color))
        material.metallic = .init(floatLiteral: object.material.metallic)
        material.roughness = .init(floatLiteral: object.material.roughness)
        material.clearcoat = .init(floatLiteral: selected ? 0.22 : 0)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = object.id.uuidString
        entity.position = object.position
        entity.scale = object.scale
        let xRotation = simd_quatf(angle: object.rotation.x, axis: [1, 0, 0])
        let yRotation = simd_quatf(angle: object.rotation.y, axis: [0, 1, 0])
        let zRotation = simd_quatf(angle: object.rotation.z, axis: [0, 0, 1])
        entity.orientation = xRotation * yRotation * zRotation
        entity.components.set(
            GroundingShadowComponent(castsShadow: document.light.castsShadow)
        )
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(InputTargetComponent())
        return entity
    }

    private func makeGrid() -> Entity {
        let container = Entity()
        let lineMaterial = UnlitMaterial(
            color: UIColor.white.withAlphaComponent(0.11)
        )
        for step in -5...5 {
            let offset = Float(step) * 0.25
            let xLine = ModelEntity(
                mesh: .generateBox(size: [2.5, 0.003, 0.006]),
                materials: [lineMaterial]
            )
            xLine.position = [0, -0.53, offset]
            container.addChild(xLine)
            let zLine = ModelEntity(
                mesh: .generateBox(size: [0.006, 0.003, 2.5]),
                materials: [lineMaterial]
            )
            zLine.position = [offset, -0.53, 0]
            container.addChild(zLine)
        }
        return container
    }
}

private struct AxisSlider: View {
    let axis: String
    let color: Color
    @Binding var value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(axis).foregroundStyle(color).fontWeight(.bold)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $value, in: -2...2)
                .tint(color)
        }
    }
}

private struct MaterialSlider: View {
    let title: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Slider(value: $value, in: range)
                .frame(minWidth: 70)
        }
    }
}

private struct ObjectBrowser: View {
    @Binding var document: ModelDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(selection: $document.selectedID) {
                Section("Szenen-Hierarchie") {
                    ForEach(document.objects) { object in
                        Label(object.name, systemImage: object.kind.symbol)
                            .tag(object.id)
                    }
                    .onDelete { offsets in
                        document.objects.remove(atOffsets: offsets)
                        document.ensureSelection()
                        document.commitChange()
                    }
                }

                Section("Rigging") {
                    Label("Skeleton / Bones", systemImage: "figure.arms.open")
                    Text(
                        "RealityKit-Skeletone und USD-Skel-Export sind für den nächsten Rigging-Workspace vorbereitet."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Objekte")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

private struct ModelDocument: Equatable {
    var objects: [SceneObject]
    var selectedID: UUID?
    var light = SceneLight()
    var gridVisible = true
    var revision = 0
    var canUndo = false
    var showExportNotice = false

    static let sample: ModelDocument = {
        let sphere = SceneObject(
            name: "Sphere",
            kind: .sphere,
            position: [-0.46, 0, 0],
            material: .clay
        )
        let cylinder = SceneObject(
            name: "Cylinder",
            kind: .cylinder,
            position: [0.52, -0.02, 0.08],
            scale: [0.72, 0.72, 0.72],
            material: .metal
        )
        return ModelDocument(
            objects: [sphere, cylinder],
            selectedID: sphere.id
        )
    }()

    var selectedIndex: Int? {
        objects.firstIndex { $0.id == selectedID }
    }

    mutating func add(_ kind: PrimitiveKind) {
        let count = objects.filter { $0.kind == kind }.count + 1
        let column = Float(objects.count % 3) - 1
        let row = Float(objects.count / 3)
        let object = SceneObject(
            name: "\(kind.title) \(count)",
            kind: kind,
            position: [column * 0.42, row * 0.18, row * -0.2],
            material: .clay
        )
        objects.append(object)
        selectedID = object.id
        commitChange()
    }

    mutating func duplicateSelected() {
        guard let selectedIndex else { return }
        var copy = objects[selectedIndex]
        copy.id = UUID()
        copy.name += " Copy"
        copy.position.x += 0.25
        objects.append(copy)
        selectedID = copy.id
        commitChange()
    }

    mutating func deleteSelected() {
        guard let selectedIndex else { return }
        objects.remove(at: selectedIndex)
        ensureSelection()
        commitChange()
    }

    mutating func sculptSelected(amount: Float) {
        guard let selectedIndex else { return }
        objects[selectedIndex].scale.y += amount
        objects[selectedIndex].scale.x = max(
            0.15,
            objects[selectedIndex].scale.x - amount * 0.25
        )
        commitChange()
    }

    mutating func ensureSelection() {
        if !objects.contains(where: { $0.id == selectedID }) {
            selectedID = objects.first?.id
        }
    }

    mutating func commitChange() {
        revision += 1
        canUndo = true
    }

    mutating func undo() {
        canUndo = false
    }
}

private struct SceneObject: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: PrimitiveKind
    var position: SIMD3<Float> = .zero
    var rotation: SIMD3<Float> = .zero
    var scale: SIMD3<Float> = .one
    var material: EditorMaterial
}

private struct EditorMaterial: Equatable {
    var color: Color
    var metallic: Float
    var roughness: Float
    var textureIndex = 0

    static let clay = EditorMaterial(
        color: Color(red: 0.91, green: 0.43, blue: 0.25),
        metallic: 0.05,
        roughness: 0.68
    )
    static let metal = EditorMaterial(
        color: Color(red: 0.2, green: 0.55, blue: 0.92),
        metallic: 0.82,
        roughness: 0.24
    )
}

private struct SceneLight: Equatable {
    var color: Color = .white
    var intensity: Float = 1
    var castsShadow = true
}

private enum PrimitiveKind: String, CaseIterable, Identifiable {
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

private enum EditorTool: CaseIterable, Identifiable {
    case select, move, rotate, scale, sculpt
    var id: Self { self }
    var title: String {
        switch self {
        case .select: "Auswahl"
        case .move: "Bewegen"
        case .rotate: "Drehen"
        case .scale: "Größe"
        case .sculpt: "Kneten"
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .move: "move.3d"
        case .rotate: "rotate.3d"
        case .scale: "arrow.up.left.and.arrow.down.right"
        case .sculpt: "hand.draw.fill"
        }
    }
}

private enum InspectorPanel: CaseIterable, Identifiable {
    case transform, material, light
    var id: Self { self }
    var title: String {
        switch self {
        case .transform: "Transform"
        case .material: "Material"
        case .light: "Licht"
        }
    }
    var symbol: String {
        switch self {
        case .transform: "move.3d"
        case .material: "paintpalette.fill"
        case .light: "lightbulb.max.fill"
        }
    }
}

extension Color {
    fileprivate static let editorBackground = Color(
        red: 0.055,
        green: 0.06,
        blue: 0.075
    )
}

#Preview {
    HomeView()
}
