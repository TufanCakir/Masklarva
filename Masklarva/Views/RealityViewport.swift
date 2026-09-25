//
//  RealityViewport.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import RealityKit
import SwiftUI

struct RealityViewport: View {
    @Binding var document: ModelDocument
    @Binding var selectedTool: EditorTool
    @Binding var orbit: CGSize
    @Binding var zoom: Float
    @Binding var cameraPan: SIMD2<Float>
    @Binding var cameraMode: CameraNavigationMode

    @State private var dragStart: SceneTransform?
    @State private var draggedAxis: GizmoAxis?
    @State private var pointDragStart: SIMD3<Float>?
    @State private var draggedPointID: UUID?
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
                if let pointID = pointID(from: value.entity),
                    let selected = document.selectedIndex
                {
                    document.objects[selected].editableGeometry
                        .selectedPointID =
                        pointID
                    document.revision += 1
                    return
                }
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

                if selectedTool == .points {
                    guard let selected = document.selectedIndex else { return }
                    if draggedPointID == nil {
                        guard let id = pointID(from: value.entity),
                            let point = document.objects[selected]
                                .editableGeometry.points.first(where: {
                                    $0.id == id
                                })
                        else { return }
                        document.beginChange()
                        draggedPointID = id
                        pointDragStart = point.position
                        document.objects[selected].editableGeometry
                            .selectedPointID =
                            id
                    }
                    guard let draggedPointID, let pointDragStart,
                        let pointIndex = document.objects[selected]
                            .editableGeometry.points.firstIndex(where: {
                                $0.id == draggedPointID
                            })
                    else { return }
                    var position = pointDragStart
                    position.x += Float(value.translation.width) * 0.006
                    position.y -= Float(value.translation.height) * 0.006
                    document.objects[selected].editableGeometry.points[
                        pointIndex
                    ]
                    .position = position
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
                if dragStart != nil || pointDragStart != nil {
                    document.endChange()
                }
                dragStart = nil
                draggedAxis = nil
                pointDragStart = nil
                draggedPointID = nil
            }
    }

    private func applyTransform(
        to index: Int,
        start: SceneTransform,
        axis: GizmoAxis,
        horizontal: Float,
        vertical: Float
    ) {
        let amount: Float
        switch axis {
        case .x, .screen:
            amount = horizontal
        case .y, .z:
            amount = -vertical
        }

        switch selectedTool {
        case .move:
            var position = start.position
            switch axis {
            case .x: position.x += amount * 0.006
            case .y: position.y += amount * 0.006
            case .z: position.z += amount * 0.006
            case .screen:
                position.x += horizontal * 0.006
                position.y -= vertical * 0.006
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

        case .select, .sculpt, .points:
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
            if selectedTool != .points {
                root.addChild(
                    makeGizmo(at: selected.position, objectID: selected.id)
                )
            }
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
            if selectedTool == .points {
                existingGizmo?.removeFromParent()
            } else if existingGizmo?.name == expectedName {
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
        if let mesh = editableMesh(for: object) {
            entity.model?.mesh = mesh
            entity.generateCollisionShapes(recursive: false)
        }
        updatePointHandles(
            on: entity,
            object: object,
            visible: selected && selectedTool == .points
        )
        if document.light.castsShadow {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        } else {
            entity.components.remove(GroundingShadowComponent.self)
        }
    }

    private func makeEntity(for object: SceneObject, selected: Bool)
        -> ModelEntity
    {
        let fallbackMesh: MeshResource =
            switch object.kind {
            case .sphere: .generateSphere(radius: 0.48)
            case .cube: .generateBox(size: 0.9, cornerRadius: 0.06)
            case .cylinder: .generateCylinder(height: 1, radius: 0.42)
            case .cone: .generateCone(height: 1.1, radius: 0.5)
            case .capsule: .generateCylinder(height: 1.15, radius: 0.36)
            case .plane:
                .generateBox(size: [1.4, 0.05, 1.4], cornerRadius: 0.015)
            }
        let mesh = editableMesh(for: object) ?? fallbackMesh

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
        updatePointHandles(
            on: entity,
            object: object,
            visible: selected && selectedTool == .points
        )
        return entity
    }

    private func editableMesh(for object: SceneObject) -> MeshResource? {
        guard !object.editableGeometry.points.isEmpty,
            object.editableGeometry.triangleIndices.count >= 3
        else { return nil }
        var descriptor = MeshDescriptor(name: object.name)
        descriptor.positions = MeshBuffers.Positions(
            object.editableGeometry.points.map(\.position)
        )
        descriptor.primitives = .triangles(
            object.editableGeometry.triangleIndices
        )
        return try? MeshResource.generate(from: [descriptor])
    }

    private func updatePointHandles(
        on entity: ModelEntity,
        object: SceneObject,
        visible: Bool
    ) {
        entity.children
            .filter { $0.name.hasPrefix("meshPoint:") }
            .forEach { $0.removeFromParent() }
        guard visible else { return }
        for point in object.editableGeometry.points {
            let isSelected =
                point.id == object.editableGeometry.selectedPointID
            let handle = ModelEntity(
                mesh: .generateSphere(radius: isSelected ? 0.055 : 0.04),
                materials: [
                    UnlitMaterial(color: isSelected ? .systemYellow : .white)
                ]
            )
            handle.name = "meshPoint:\(point.id.uuidString)"
            handle.position = point.position
            handle.generateCollisionShapes(recursive: false)
            handle.components.set(InputTargetComponent())
            entity.addChild(handle)
        }
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

    private func pointID(from entity: Entity) -> UUID? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name.hasPrefix("meshPoint:") {
                return UUID(
                    uuidString: String(
                        candidate.name.dropFirst("meshPoint:".count)
                    )
                )
            }
            current = candidate.parent
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
