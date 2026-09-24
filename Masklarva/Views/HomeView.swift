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
    @State private var document = ModelDocument.sample
    @State private var selectedTool: EditorTool = .move
    @State private var orbit = CGSize.zero
    @State private var zoom: Float = 1
    @State private var cameraPan = SIMD2<Float>.zero
    @State private var cameraMode: CameraNavigationMode = .pan
    @State private var isToolShelfVisible = true
    @State private var isInspectorVisible = false
    @State private var isProjectPanelVisible = true
    @State private var projectPanelHeight: CGFloat = 190
    @State private var projectPanelResizeStart: CGFloat?
    @State private var projectLibrary = ProjectLibraryModel()

    var body: some View {
        editorWorkspace
            .preferredColorScheme(.dark)
    }

    private var editorWorkspace: some View {
        NavigationStack {
            ZStack {
                Color.editorBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack {
                        viewport
                        toolShelf
                        inspectorShelf
                    }

                    if isProjectPanelVisible {
                        projectPanel
                            .frame(height: projectPanelHeight)
                            .transition(
                                .move(edge: .bottom).combined(with: .opacity)
                            )
                    }
                }
            }
            .navigationTitle("Clay Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Werkzeuge", systemImage: "sidebar.left") {
                withAnimation(.snappy) {
                    isToolShelfVisible.toggle()
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu("Form", systemImage: "plus") {
                ForEach(PrimitiveKind.allCases) { kind in
                    Button(kind.title, systemImage: kind.symbol) {
                        document.add(kind)
                    }
                }
            }

            Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                document.undo()
            }
            .disabled(!document.canUndo)

            Button("Wiederholen", systemImage: "arrow.uturn.forward") {
                document.redo()
            }
            .disabled(!document.canRedo)

            Button("Projekt", systemImage: "folder") {
                withAnimation(.snappy) {
                    isProjectPanelVisible.toggle()
                }
            }

            Button("Inspector", systemImage: "slider.horizontal.3") {
                withAnimation(.snappy) {
                    isInspectorVisible.toggle()
                }
            }

            Menu("Kamera", systemImage: cameraMode.symbol) {
                Picker("Kamerasteuerung", selection: $cameraMode) {
                    ForEach(CameraNavigationMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Button("Ansicht zentrieren", systemImage: "scope") {
                    orbit = .zero
                    cameraPan = .zero
                    zoom = 1
                }
                Button("Auswahl fokussieren", systemImage: "viewfinder") {
                    focusSelectedObject()
                }
                Divider()
                Button("Vergrößern", systemImage: "plus.magnifyingglass") {
                    zoom = min(5, zoom * 1.25)
                }
                Button("Verkleinern", systemImage: "minus.magnifyingglass") {
                    zoom = max(0.2, zoom / 1.25)
                }
            }
        }
    }

    private var inspectorShelf: some View {
        HStack {
            Spacer()
            if isInspectorVisible {
                EditorInspectorPanel(
                    document: $document,
                    selectedTool: selectedTool
                )
                .frame(width: 220)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .padding(8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var projectPanel: some View {
        ProjectLibraryPanel(
            library: projectLibrary,
            selectedObjectName: document.selectedObjectName
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(.secondary.opacity(0.65))
                .frame(width: 48, height: 5)
                .padding(.top, 6)
                .contentShape(Rectangle().inset(by: -12))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if projectPanelResizeStart == nil {
                                projectPanelResizeStart = projectPanelHeight
                            }
                            projectPanelHeight = min(
                                360,
                                max(
                                    120,
                                    (projectPanelResizeStart
                                        ?? projectPanelHeight)
                                        - value.translation.height
                                )
                            )
                        }
                        .onEnded { _ in
                            projectPanelResizeStart = nil
                        }
                )
        }
    }

    private func focusSelectedObject() {
        guard let selected = document.selectedIndex else { return }
        let position = document.objects[selected].position
        withAnimation(.smooth) {
            cameraPan = [position.x, position.y]
            zoom = 2.2
        }
    }

    private var toolShelf: some View {
        HStack(spacing: 0) {
            if isToolShelfVisible {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        shelfSection("WERKZEUGE") {
                            ForEach(EditorTool.allCases) { tool in
                                Button {
                                    selectedTool = tool
                                    if tool == .sculpt {
                                        document.sculptSelected(amount: 0.08)
                                    }
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
                                    selectedTool == tool
                                        ? Color.accentColor : .secondary
                                )
                            }
                        }

                        shelfSection("FORMEN") {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                ],
                                spacing: 8
                            ) {
                                ForEach(PrimitiveKind.allCases) { kind in
                                    Button {
                                        document.add(kind)
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

                        shelfSection("AUSWAHL") {
                            ForEach(document.objects) { object in
                                Button {
                                    document.selectedID = object.id
                                } label: {
                                    Label(
                                        object.name,
                                        systemImage: object.kind.symbol
                                    )
                                    .lineLimit(1)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(7)
                                .background(
                                    document.selectedID == object.id
                                        ? Color.accentColor.opacity(0.25)
                                        : .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
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

    private func shelfSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var viewport: some View {
        ZStack(alignment: .topLeading) {
            RealityViewport(
                document: $document,
                selectedTool: $selectedTool,
                orbit: $orbit,
                zoom: $zoom,
                cameraPan: $cameraPan,
                cameraMode: $cameraMode
            )
            .dropDestination(for: ProjectMaterial.self) { materials, _ in
                guard
                    let material = materials.first,
                    let selected = document.selectedIndex
                else { return false }
                document.beginChange()
                document.objects[selected].material = material.editorMaterial
                document.endChange()
                return true
            } isTargeted: { isTargeted in
                projectLibrary.isDroppingMaterial = isTargeted
            }

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

            if projectLibrary.isDroppingMaterial {
                VStack {
                    Spacer()
                    Label(
                        "Auf \(document.selectedObjectName) anwenden",
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

}

private struct RealityViewport: View {
    @Binding var document: ModelDocument
    @Binding var selectedTool: EditorTool
    @Binding var orbit: CGSize
    @Binding var zoom: Float
    @Binding var cameraPan: SIMD2<Float>
    @Binding var cameraMode: CameraNavigationMode

    @State private var dragStart: SceneTransform?
    @State private var draggedAxis: GizmoAxis?
    @State private var cameraDragStart: CameraDragStart?
    @State private var magnifyStart: Float?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(makeSceneRoot())
        } update: { content in
            if let root = content.entities.first {
                updateSceneRoot(root)
            }
        }
        .simultaneousGesture(focusGesture)
        .simultaneousGesture(selectionGesture)
        .simultaneousGesture(transformGesture)
        .simultaneousGesture(cameraOrbitGesture)
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if magnifyStart == nil {
                        magnifyStart = zoom
                    }
                    zoom = max(
                        0.2,
                        min(
                            5,
                            (magnifyStart ?? zoom) * Float(value.magnification)
                        )
                    )
                }
                .onEnded { _ in
                    magnifyStart = nil
                }
        )
    }

    private var focusGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { value in
                guard
                    let id = objectID(from: value.entity),
                    let object = document.objects.first(where: { $0.id == id })
                else { return }
                document.selectedID = id
                cameraPan = [object.position.x, object.position.y]
                zoom = 2.2
            }
    }

    private var cameraOrbitGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard selectedTool == .select else { return }
                if cameraDragStart == nil {
                    cameraDragStart = CameraDragStart(
                        orbit: orbit,
                        pan: cameraPan
                    )
                }
                guard let cameraDragStart else { return }
                switch cameraMode {
                case .orbit:
                    orbit = CGSize(
                        width: cameraDragStart.orbit.width
                            + value.translation.width,
                        height: cameraDragStart.orbit.height
                            + value.translation.height
                    )
                case .pan:
                    cameraPan =
                        cameraDragStart.pan
                        + SIMD2<Float>(
                            -Float(value.translation.width) * 0.004,
                            Float(value.translation.height) * 0.004
                        )
                }
            }
            .onEnded { _ in
                cameraDragStart = nil
            }
    }

    private var selectionGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let id = objectID(from: value.entity) {
                    document.selectedID = id
                    document.revision += 1
                }
            }
    }

    private var transformGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .targetedToAnyEntity()
            .onChanged { value in
                guard selectedTool != .select, selectedTool != .sculpt else {
                    return
                }

                if dragStart == nil {
                    if let id = objectID(from: value.entity) {
                        document.selectedID = id
                    }
                    guard let selected = document.selectedIndex else { return }
                    document.beginChange()
                    dragStart = SceneTransform(
                        object: document.objects[selected]
                    )
                    draggedAxis = axis(from: value.entity) ?? .screen
                }

                guard
                    let selected = document.selectedIndex,
                    let dragStart,
                    let draggedAxis
                else { return }

                let horizontal = Float(value.translation.width)
                let vertical = Float(value.translation.height)
                applyTransform(
                    to: selected,
                    start: dragStart,
                    axis: draggedAxis,
                    horizontal: horizontal,
                    vertical: vertical
                )
            }
            .onEnded { _ in
                if dragStart != nil {
                    document.endChange()
                }
                dragStart = nil
                draggedAxis = nil
            }
    }

    private func applyTransform(
        to index: Int,
        start: SceneTransform,
        axis: GizmoAxis,
        horizontal: Float,
        vertical: Float
    ) {
        let amount = axis == .y ? -vertical : horizontal

        switch selectedTool {
        case .move:
            var position = start.position
            switch axis {
            case .x: position.x += amount * 0.004
            case .y: position.y += amount * 0.004
            case .z: position.z += amount * 0.004
            case .screen:
                position.x += horizontal * 0.004
                position.y -= vertical * 0.004
            }
            if document.snapEnabled {
                position = SIMD3<Float>(
                    snap(position.x, step: document.moveSnap),
                    snap(position.y, step: document.moveSnap),
                    snap(position.z, step: document.moveSnap)
                )
            }
            document.objects[index].position = position

        case .rotate:
            var rotation = start.rotation
            let radians = amount * 0.012
            switch axis {
            case .x: rotation.x += radians
            case .y: rotation.y += radians
            case .z: rotation.z += radians
            case .screen:
                rotation.x -= vertical * 0.012
                rotation.z += horizontal * 0.012
            }
            if document.snapEnabled {
                let step = document.rotationSnapDegrees * .pi / 180
                rotation = SIMD3<Float>(
                    snap(rotation.x, step: step),
                    snap(rotation.y, step: step),
                    snap(rotation.z, step: step)
                )
            }
            document.objects[index].rotation = rotation

        case .scale:
            var scale = start.scale
            let factor = max(0.12, 1 + amount * 0.008)
            switch axis {
            case .x: scale.x = max(0.08, start.scale.x * factor)
            case .y: scale.y = max(0.08, start.scale.y * factor)
            case .z: scale.z = max(0.08, start.scale.z * factor)
            case .screen: scale = start.scale * factor
            }
            if document.snapEnabled {
                scale = SIMD3<Float>(
                    max(0.08, snap(scale.x, step: document.scaleSnap)),
                    max(0.08, snap(scale.y, step: document.scaleSnap)),
                    max(0.08, snap(scale.z, step: document.scaleSnap))
                )
            }
            document.objects[index].scale = scale

        case .select, .sculpt:
            break
        }
    }

    private func snap(_ value: Float, step: Float) -> Float {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    private func makeSceneRoot() -> Entity {
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

        if let selected = document.objects.first(where: {
            $0.id == document.selectedID
        }) {
            root.addChild(
                makeGizmo(at: selected.position, objectID: selected.id)
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
        camera.name = "EditorCamera"
        camera.components.set(
            PerspectiveCameraComponent(
                near: 0.01,
                far: 100,
                fieldOfViewInDegrees: 48
            )
        )
        let yaw = Float(orbit.width) * 0.006
        let pitch = max(-0.9, min(0.9, Float(orbit.height) * 0.005))
        let distance = max(1.8, 8 / max(zoom, 0.2))
        let position = SIMD3<Float>(
            cameraPan.x + sin(yaw) * distance,
            cameraPan.y + 1.3 + pitch * 1.5,
            cos(yaw) * distance
        )
        camera.look(
            at: [cameraPan.x, cameraPan.y + 0.45, 0],
            from: position,
            relativeTo: nil
        )
        root.addChild(camera)
        return root
    }

    private func updateSceneRoot(_ root: Entity) {
        let validIDs = Set(document.objects.map { $0.id.uuidString })

        for child in root.children {
            if UUID(uuidString: child.name) != nil,
                !validIDs.contains(child.name)
            {
                child.removeFromParent()
            }
        }

        for object in document.objects {
            let entity: ModelEntity
            if let existing = root.findEntity(named: object.id.uuidString)
                as? ModelEntity
            {
                entity = existing
                updateEntity(
                    entity,
                    from: object,
                    selected: object.id == document.selectedID
                )
            } else {
                entity = makeEntity(
                    for: object,
                    selected: object.id == document.selectedID
                )
                root.addChild(entity)
            }
        }

        if let selected = document.objects.first(where: {
            $0.id == document.selectedID
        }) {
            let expectedName = gizmoName(for: selected.id)
            let existingGizmo = root.children.first {
                $0.name.hasPrefix("gizmoRoot:")
            }
            if existingGizmo?.name == expectedName {
                existingGizmo?.position = selected.position
            } else {
                existingGizmo?.removeFromParent()
                root.addChild(
                    makeGizmo(at: selected.position, objectID: selected.id)
                )
            }
        }

        if let camera = root.findEntity(named: "EditorCamera") {
            let yaw = Float(orbit.width) * 0.006
            let pitch = max(-0.9, min(0.9, Float(orbit.height) * 0.005))
            let distance = max(1.8, 8 / max(zoom, 0.2))
            let position = SIMD3<Float>(
                cameraPan.x + sin(yaw) * distance,
                cameraPan.y + 1.3 + pitch * 1.5,
                cos(yaw) * distance
            )
            camera.look(
                at: [cameraPan.x, cameraPan.y + 0.45, 0],
                from: position,
                relativeTo: nil
            )
        }
    }

    private func updateEntity(
        _ entity: ModelEntity,
        from object: SceneObject,
        selected: Bool
    ) {
        entity.position = object.position
        entity.scale = object.scale
        let xRotation = simd_quatf(
            angle: object.rotation.x,
            axis: [1, 0, 0]
        )
        let yRotation = simd_quatf(
            angle: object.rotation.y,
            axis: [0, 1, 0]
        )
        let zRotation = simd_quatf(
            angle: object.rotation.z,
            axis: [0, 0, 1]
        )
        entity.orientation = xRotation * yRotation * zRotation
        entity.model?.materials = [
            makeMaterial(object.material, selected: selected)
        ]
        if document.light.castsShadow {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        } else {
            entity.components.remove(GroundingShadowComponent.self)
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

        let entity = ModelEntity(
            mesh: mesh,
            materials: [makeMaterial(object.material, selected: selected)]
        )
        entity.name = object.id.uuidString
        entity.position = object.position
        entity.scale = object.scale
        let xRotation = simd_quatf(angle: object.rotation.x, axis: [1, 0, 0])
        let yRotation = simd_quatf(angle: object.rotation.y, axis: [0, 1, 0])
        let zRotation = simd_quatf(angle: object.rotation.z, axis: [0, 0, 1])
        entity.orientation = xRotation * yRotation * zRotation
        if document.light.castsShadow {
            entity.components.set(
                GroundingShadowComponent(castsShadow: true)
            )
        }
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(InputTargetComponent())
        return entity
    }

    private func makeMaterial(
        _ editorMaterial: EditorMaterial,
        selected: Bool
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(editorMaterial.color))
        material.metallic = .init(floatLiteral: editorMaterial.metallic)
        material.roughness = .init(floatLiteral: editorMaterial.roughness)
        material.clearcoat = .init(floatLiteral: selected ? 0.22 : 0)
        return material
    }

    private func makeGizmo(
        at position: SIMD3<Float>,
        objectID: UUID? = nil
    ) -> Entity {
        let gizmo = Entity()
        gizmo.name = objectID.map(gizmoName(for:)) ?? "gizmoRoot:initial"
        gizmo.position = position
        if selectedTool == .rotate {
            gizmo.addChild(makeRotationRing(.x, color: .systemRed))
            gizmo.addChild(makeRotationRing(.y, color: .systemGreen))
            gizmo.addChild(makeRotationRing(.z, color: .systemBlue))
        } else {
            gizmo.addChild(makeAxis(.x, color: .systemRed))
            gizmo.addChild(makeAxis(.y, color: .systemGreen))
            gizmo.addChild(makeAxis(.z, color: .systemBlue))
        }
        return gizmo
    }

    private func gizmoName(for objectID: UUID) -> String {
        "gizmoRoot:\(selectedTool.title):\(objectID.uuidString)"
    }

    private func makeRotationRing(
        _ axis: GizmoAxis,
        color: UIColor
    ) -> Entity {
        let ring = Entity()
        ring.name = "gizmo:\(axis.rawValue)"
        let material = UnlitMaterial(color: color)
        let segmentCount = 12
        let radius: Float = 0.68

        for segment in 0..<segmentCount {
            let angle = Float(segment) / Float(segmentCount) * 2 * .pi
            let point: SIMD3<Float> =
                switch axis {
                case .x: [0, cos(angle) * radius, sin(angle) * radius]
                case .y: [cos(angle) * radius, 0, sin(angle) * radius]
                case .z: [cos(angle) * radius, sin(angle) * radius, 0]
                case .screen: .zero
                }
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.025),
                materials: [material]
            )
            marker.position = point
            marker.generateCollisionShapes(recursive: false)
            marker.components.set(InputTargetComponent())
            ring.addChild(marker)
        }

        ring.components.set(InputTargetComponent())
        return ring
    }

    private func makeAxis(_ axis: GizmoAxis, color: UIColor) -> Entity {
        let container = Entity()
        container.name = "gizmo:\(axis.rawValue)"
        let material = UnlitMaterial(color: color)

        let shaft = ModelEntity(
            mesh: .generateCylinder(height: 0.62, radius: 0.025),
            materials: [material]
        )
        shaft.position.y = 0.31

        let tip = ModelEntity(
            mesh: .generateCone(height: 0.18, radius: 0.075),
            materials: [material]
        )
        tip.position.y = 0.71

        shaft.generateCollisionShapes(recursive: false)
        shaft.components.set(InputTargetComponent())
        tip.generateCollisionShapes(recursive: false)
        tip.components.set(InputTargetComponent())

        container.addChild(shaft)
        container.addChild(tip)
        switch axis {
        case .x:
            container.orientation = simd_quatf(
                angle: -.pi / 2,
                axis: [0, 0, 1]
            )
        case .y:
            break
        case .z:
            container.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        case .screen:
            break
        }
        container.generateCollisionShapes(recursive: true)
        container.components.set(InputTargetComponent())
        return container
    }

    private func objectID(from entity: Entity) -> UUID? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let id = UUID(uuidString: current.name) {
                return id
            }
            candidate = current.parent
        }
        return nil
    }

    private func axis(from entity: Entity) -> GizmoAxis? {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name.hasPrefix("gizmo:") {
                return GizmoAxis(
                    rawValue: String(current.name.dropFirst("gizmo:".count))
                )
            }
            candidate = current.parent
        }
        return nil
    }

    private func makeGrid() -> Entity {
        let container = Entity()
        let lineMaterial = UnlitMaterial(
            color: UIColor.white.withAlphaComponent(0.11)
        )
        for step in -10...10 {
            let offset = Float(step)
            let xLine = ModelEntity(
                mesh: .generateBox(size: [20, 0.003, 0.012]),
                materials: [lineMaterial]
            )
            xLine.position = [0, -0.53, offset]
            container.addChild(xLine)
            let zLine = ModelEntity(
                mesh: .generateBox(size: [0.012, 0.003, 20]),
                materials: [lineMaterial]
            )
            zLine.position = [offset, -0.53, 0]
            container.addChild(zLine)
        }
        return container
    }
}

private struct SceneTransform {
    let position: SIMD3<Float>
    let rotation: SIMD3<Float>
    let scale: SIMD3<Float>

    init(object: SceneObject) {
        position = object.position
        rotation = object.rotation
        scale = object.scale
    }
}

private enum GizmoAxis: String {
    case x, y, z, screen
}

private struct CameraDragStart {
    let orbit: CGSize
    let pan: SIMD2<Float>
}

private enum CameraNavigationMode: CaseIterable, Identifiable {
    case pan, orbit

    var id: Self { self }
    var title: String {
        switch self {
        case .pan: "Arbeitsfläche bewegen"
        case .orbit: "Ansicht drehen"
        }
    }
    var symbol: String {
        switch self {
        case .pan: "hand.draw"
        case .orbit: "rotate.3d"
        }
    }
}

@MainActor
@Observable
private final class ProjectLibraryModel {
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

private struct ProjectFolder: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var symbol: String
}

private struct ProjectMaterial: Identifiable, Codable, Hashable, Transferable {
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
            color: color,
            metallic: metallic,
            roughness: roughness
        )
    }
}

private struct ProjectLibraryPanel: View {
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

private struct EditorInspectorPanel: View {
    @Binding var document: ModelDocument
    let selectedTool: EditorTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Inspector", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    Text(document.selectedObjectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if document.selectedIndex != nil {
                    transformSection
                    materialSection
                    snappingSection
                } else {
                    ContentUnavailableView(
                        "Keine Auswahl",
                        systemImage: "cube.transparent"
                    )
                }
            }
            .padding(12)
        }
    }

    private var transformSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                switch selectedTool {
                case .rotate:
                    valueRow(
                        title: "Rotation",
                        channels: [.rotationX, .rotationY, .rotationZ],
                        suffix: "°"
                    )
                case .scale:
                    valueRow(
                        title: "Skalierung",
                        channels: [.scaleX, .scaleY, .scaleZ]
                    )
                default:
                    valueRow(
                        title: "Position",
                        channels: [.positionX, .positionY, .positionZ]
                    )
                }
            }
        } label: {
            Label("Transform", systemImage: selectedTool.symbol)
        }
    }

    private func valueRow(
        title: String,
        channels: [InspectorChannel],
        suffix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(channels) { channel in
                    VStack(spacing: 3) {
                        Text(channel.axis)
                            .font(.caption2.bold())
                            .foregroundStyle(channel.color)
                        TextField(
                            channel.axis,
                            value: channelBinding(channel),
                            format: .number.precision(.fractionLength(2))
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        if !suffix.isEmpty {
                            Text(suffix)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var materialSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                ColorPicker(
                    "Farbe",
                    selection: materialColorBinding,
                    supportsOpacity: false
                )
                inspectorSlider(
                    "Metall",
                    value: materialFloatBinding(\.metallic)
                )
                inspectorSlider(
                    "Rauheit",
                    value: materialFloatBinding(\.roughness)
                )
            }
        } label: {
            Label("Material", systemImage: "paintpalette.fill")
        }
    }

    private func inspectorSlider(
        _ title: String,
        value: Binding<Float>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(
                    value.wrappedValue,
                    format: .number.precision(.fractionLength(2))
                )
                .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: 0...1)
        }
    }

    private var snappingSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                Toggle("Snapping", isOn: $document.snapEnabled)
                Picker("Position", selection: $document.moveSnap) {
                    Text("0,1").tag(Float(0.1))
                    Text("0,25").tag(Float(0.25))
                    Text("0,5").tag(Float(0.5))
                    Text("1").tag(Float(1))
                }
                Picker("Winkel", selection: $document.rotationSnapDegrees) {
                    Text("5°").tag(Float(5))
                    Text("15°").tag(Float(15))
                    Text("30°").tag(Float(30))
                    Text("45°").tag(Float(45))
                }
                Picker("Größe", selection: $document.scaleSnap) {
                    Text("0,05").tag(Float(0.05))
                    Text("0,1").tag(Float(0.1))
                    Text("0,25").tag(Float(0.25))
                    Text("0,5").tag(Float(0.5))
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        } label: {
            Label("Einrasten", systemImage: "dot.scope")
        }
    }

    private func channelBinding(_ channel: InspectorChannel) -> Binding<Float> {
        Binding {
            guard let index = document.selectedIndex else { return 0 }
            return channel.value(from: document.objects[index])
        } set: { newValue in
            guard let index = document.selectedIndex else { return }
            document.beginChange()
            channel.set(newValue, on: &document.objects[index])
            document.endChange()
        }
    }

    private var materialColorBinding: Binding<Color> {
        Binding {
            guard let index = document.selectedIndex else { return .white }
            return document.objects[index].material.color
        } set: { newValue in
            guard let index = document.selectedIndex else { return }
            document.beginChange()
            document.objects[index].material.color = newValue
            document.endChange()
        }
    }

    private func materialFloatBinding(
        _ keyPath: WritableKeyPath<EditorMaterial, Float>
    ) -> Binding<Float> {
        Binding {
            guard let index = document.selectedIndex else { return 0 }
            return document.objects[index].material[keyPath: keyPath]
        } set: { newValue in
            guard let index = document.selectedIndex else { return }
            document.beginChange()
            document.objects[index].material[keyPath: keyPath] = newValue
            document.endChange()
        }
    }
}

private enum InspectorChannel: String, Identifiable {
    case positionX, positionY, positionZ
    case rotationX, rotationY, rotationZ
    case scaleX, scaleY, scaleZ

    var id: Self { self }
    var axis: String {
        switch self {
        case .positionX, .rotationX, .scaleX: "X"
        case .positionY, .rotationY, .scaleY: "Y"
        case .positionZ, .rotationZ, .scaleZ: "Z"
        }
    }
    var color: Color {
        switch self {
        case .positionX, .rotationX, .scaleX: .red
        case .positionY, .rotationY, .scaleY: .green
        case .positionZ, .rotationZ, .scaleZ: .blue
        }
    }

    func value(from object: SceneObject) -> Float {
        switch self {
        case .positionX: object.position.x
        case .positionY: object.position.y
        case .positionZ: object.position.z
        case .rotationX: object.rotation.x * 180 / .pi
        case .rotationY: object.rotation.y * 180 / .pi
        case .rotationZ: object.rotation.z * 180 / .pi
        case .scaleX: object.scale.x
        case .scaleY: object.scale.y
        case .scaleZ: object.scale.z
        }
    }

    func set(_ value: Float, on object: inout SceneObject) {
        switch self {
        case .positionX: object.position.x = value
        case .positionY: object.position.y = value
        case .positionZ: object.position.z = value
        case .rotationX: object.rotation.x = value * .pi / 180
        case .rotationY: object.rotation.y = value * .pi / 180
        case .rotationZ: object.rotation.z = value * .pi / 180
        case .scaleX: object.scale.x = max(0.01, value)
        case .scaleY: object.scale.y = max(0.01, value)
        case .scaleZ: object.scale.z = max(0.01, value)
        }
    }
}

private struct SceneSnapshot: Equatable {
    var objects: [SceneObject]
    var selectedID: UUID?
}

private struct ModelDocument: Equatable {
    var objects: [SceneObject]
    var selectedID: UUID?
    var light = SceneLight()
    var gridVisible = true
    var revision = 0
    var showExportNotice = false
    var snapEnabled = true
    var moveSnap: Float = 0.25
    var rotationSnapDegrees: Float = 15
    var scaleSnap: Float = 0.1
    private var undoStack: [SceneSnapshot] = []
    private var redoStack: [SceneSnapshot] = []
    private var pendingSnapshot: SceneSnapshot?

    static let sample: ModelDocument = {
        let cube = SceneObject(
            name: "Cube",
            kind: .cube,
            position: .zero,
            scale: [0.7, 0.7, 0.7],
            material: .clay
        )
        return ModelDocument(
            objects: [cube],
            selectedID: cube.id
        )
    }()

    var selectedIndex: Int? {
        objects.firstIndex { $0.id == selectedID }
    }

    var selectedObjectName: String {
        guard let selectedIndex else { return "Kein Objekt ausgewählt" }
        return objects[selectedIndex].name
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func add(_ kind: PrimitiveKind) {
        beginChange()
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
        endChange()
    }

    mutating func duplicateSelected() {
        guard let selectedIndex else { return }
        beginChange()
        var copy = objects[selectedIndex]
        copy.id = UUID()
        copy.name += " Copy"
        copy.position.x += 0.25
        objects.append(copy)
        selectedID = copy.id
        endChange()
    }

    mutating func deleteSelected() {
        guard let selectedIndex else { return }
        beginChange()
        objects.remove(at: selectedIndex)
        ensureSelection()
        endChange()
    }

    mutating func sculptSelected(amount: Float) {
        guard let selectedIndex else { return }
        beginChange()
        objects[selectedIndex].scale.y += amount
        objects[selectedIndex].scale.x = max(
            0.15,
            objects[selectedIndex].scale.x - amount * 0.25
        )
        endChange()
    }

    mutating func ensureSelection() {
        if !objects.contains(where: { $0.id == selectedID }) {
            selectedID = objects.first?.id
        }
    }

    mutating func commitChange() {
        revision += 1
    }

    mutating func beginChange() {
        guard pendingSnapshot == nil else { return }
        pendingSnapshot = snapshot
    }

    mutating func endChange() {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard pendingSnapshot != snapshot else { return }
        undoStack.append(pendingSnapshot)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        redoStack.removeAll()
        revision += 1
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
    }

    private var snapshot: SceneSnapshot {
        SceneSnapshot(objects: objects, selectedID: selectedID)
    }

    private mutating func restore(_ snapshot: SceneSnapshot) {
        objects = snapshot.objects
        selectedID = snapshot.selectedID
        ensureSelection()
        pendingSnapshot = nil
        revision += 1
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
    var castsShadow = false
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
