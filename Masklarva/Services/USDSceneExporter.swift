//
//  USDSceneExporter.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation
import RealityKit
import SceneKit
import SwiftUI
import USDKit

@MainActor
enum USDSceneExporter {
    static func export(
        document: ModelDocument,
        format: SceneExportFormat
    ) async throws -> ExportArtifact {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ClayStudioExports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(
            path: "ClayStudio.\(format.fileExtension)"
        )
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        switch format {
        case .usdz:
            let stage = try USDStage(string: makeUSDA(document: document))
            try stage.exportPackage(to: url)
        case .usda:
            let stage = try USDStage(string: makeUSDA(document: document))
            try stage.exportFlattened(to: url)
        case .reality:
            let root = makeRealityEntity(document: document)
            try await root.write(to: url, options: [.preferFastExport])
        case .scn:
            try exportSceneKit(document: document, to: url)
        }
        return ExportArtifact(url: url, format: format)
    }

    private static func makeRealityEntity(document: ModelDocument) -> Entity {
        let root = Entity()
        root.name = "ClayStudioScene"
        for object in document.objects where object.isVisible {
            let mesh: MeshResource
            if !object.editableGeometry.points.isEmpty {
                var descriptor = MeshDescriptor(name: object.name)
                descriptor.positions = MeshBuffers.Positions(
                    object.editableGeometry.points.map(\.position)
                )
                descriptor.primitives = .triangles(
                    object.editableGeometry.triangleIndices
                )
                mesh =
                    (try? MeshResource.generate(from: [descriptor]))
                    ?? .generateBox(size: 0.9)
            } else {
                mesh =
                    switch object.kind {
                    case .sphere: .generateSphere(radius: 0.48)
                    case .cube: .generateBox(size: 0.9)
                    case .cylinder: .generateCylinder(height: 1, radius: 0.42)
                    case .cone: .generateCone(height: 1.1, radius: 0.5)
                    case .capsule: .generateSphere(radius: 0.48)
                    case .plane: .generateBox(size: [1.4, 0.05, 1.4])
                    }
            }
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(object.material.color))
            material.metallic = .init(floatLiteral: object.material.metallic)
            material.roughness = .init(floatLiteral: object.material.roughness)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = object.name
            entity.position = object.position
            entity.scale = object.scale
            entity.orientation =
                simd_quatf(angle: object.rotation.x, axis: [1, 0, 0])
                * simd_quatf(angle: object.rotation.y, axis: [0, 1, 0])
                * simd_quatf(angle: object.rotation.z, axis: [0, 0, 1])
            root.addChild(entity)
        }
        return root
    }

    private static func exportSceneKit(
        document: ModelDocument,
        to url: URL
    ) throws {
        let scene = SCNScene()
        for object in document.objects where object.isVisible {
            let geometry: SCNGeometry
            if !object.editableGeometry.points.isEmpty {
                let vertices = object.editableGeometry.points.map {
                    SCNVector3($0.position.x, $0.position.y, $0.position.z)
                }
                let source = SCNGeometrySource(vertices: vertices)
                let element = SCNGeometryElement(
                    indices: object.editableGeometry.triangleIndices,
                    primitiveType: .triangles
                )
                geometry = SCNGeometry(
                    sources: [source],
                    elements: [element]
                )
            } else {
                geometry =
                    switch object.kind {
                    case .sphere: SCNSphere(radius: 0.48)
                    case .cube:
                        SCNBox(
                            width: 0.9,
                            height: 0.9,
                            length: 0.9,
                            chamferRadius: 0
                        )
                    case .cylinder: SCNCylinder(radius: 0.42, height: 1)
                    case .cone:
                        SCNCone(topRadius: 0, bottomRadius: 0.5, height: 1.1)
                    case .capsule: SCNCapsule(capRadius: 0.36, height: 1.15)
                    case .plane:
                        SCNBox(
                            width: 1.4,
                            height: 0.05,
                            length: 1.4,
                            chamferRadius: 0
                        )
                    }
            }
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(object.material.color)
            material.metalness.contents = object.material.metallic
            material.roughness.contents = object.material.roughness
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = object.name
            node.position = SCNVector3(
                object.position.x,
                object.position.y,
                object.position.z
            )
            node.eulerAngles = SCNVector3(
                object.rotation.x,
                object.rotation.y,
                object.rotation.z
            )
            node.scale = SCNVector3(
                object.scale.x,
                object.scale.y,
                object.scale.z
            )
            scene.rootNode.addChildNode(node)
        }
        let succeeded = scene.write(
            to: url,
            options: nil,
            delegate: nil,
            progressHandler: nil
        )
        guard succeeded else { throw ExportError.sceneKitWriteFailed }
    }

    private static func makeUSDA(document: ModelDocument) -> String {
        let objects = document.objects.filter(\.isVisible).map(makeObject)
            .joined(separator: "\n")
        return """
            #usda 1.0
            (
                defaultPrim = "Scene"
                metersPerUnit = 1
                upAxis = "Y"
            )

            def Xform "Scene"
            {
            \(objects)
            }
            """
    }

    private static func makeObject(_ object: SceneObject) -> String {
        let name = sanitized(object.name)
        let transform = """
                double3 xformOp:translate = \(vector(object.position))
                float3 xformOp:rotateXYZ = \(vector(object.rotation * 180 / .pi))
                float3 xformOp:scale = \(vector(object.scale))
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ", "xformOp:scale"]
            """

        if !object.editableGeometry.points.isEmpty {
            let points = object.editableGeometry.points
                .map { vector($0.position) }
                .joined(separator: ", ")
            let indices = object.editableGeometry.triangleIndices
                .map(String.init)
                .joined(separator: ", ")
            let counts = Array(
                repeating: "3",
                count: object.editableGeometry.triangleIndices.count / 3
            ).joined(separator: ", ")
            return """
                    def Mesh "\(name)"
                    {
                        \(transform)
                        point3f[] points = [\(points)]
                        int[] faceVertexCounts = [\(counts)]
                        int[] faceVertexIndices = [\(indices)]
                        uniform token subdivisionScheme = "none"
                    }
                """
        }

        let schema: String =
            switch object.kind {
            case .sphere: "Sphere"
            case .cube: "Cube"
            case .cylinder: "Cylinder"
            case .cone: "Cone"
            case .capsule: "Capsule"
            case .plane: "Cube"
            }
        return """
                def \(schema) "\(name)"
                {
                    \(transform)
                }
            """
    }

    private static func sanitized(_ name: String) -> String {
        let value = name.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return String(value)
    }

    private static func vector(_ value: SIMD3<Float>) -> String {
        "(\(value.x), \(value.y), \(value.z))"
    }
}

private enum ExportError: LocalizedError {
    case sceneKitWriteFailed

    var errorDescription: String? {
        "Die SceneKit-Datei konnte nicht geschrieben werden."
    }
}
