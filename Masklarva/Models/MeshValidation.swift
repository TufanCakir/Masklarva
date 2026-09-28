import Foundation

enum MeshValidationSeverity: Int, Comparable, Sendable {
    case warning
    case error

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MeshValidationIssueKind: String, Sendable {
    case duplicateVertexIdentity
    case duplicateEdgeIdentity
    case duplicateFaceIdentity
    case incompleteTriangleIndices
    case invalidTriangleIndex
    case triangleCountMismatch
    case invalidFaceReference
    case degenerateFace
    case invalidEdge
    case duplicateEdge
    case missingTopologyEdge
    case nonManifoldEdge
    case orphanVertex
}

struct MeshValidationIssue: Identifiable, Equatable, Sendable {
    let id: String
    let kind: MeshValidationIssueKind
    let severity: MeshValidationSeverity
    let detail: String
}

struct MeshValidationReport: Identifiable, Equatable, Sendable {
    let id = UUID()
    let vertexCount: Int
    let edgeCount: Int
    let faceCount: Int
    let triangleCount: Int
    let issues: [MeshValidationIssue]

    var errorCount: Int { issues.count { $0.severity == .error } }
    var warningCount: Int { issues.count { $0.severity == .warning } }
    var isValid: Bool { errorCount == 0 }
}

extension EditableGeometry {
    func validationReport() -> MeshValidationReport {
        var issues: [MeshValidationIssue] = []
        let pointIDs = points.map(\.id)
        let validPointIDs = Set(pointIDs)
        var pointsByID: [UUID: MeshControlPoint] = [:]
        for point in points where pointsByID[point.id] == nil {
            pointsByID[point.id] = point
        }

        appendDuplicateIdentityIssue(
            ids: pointIDs,
            kind: .duplicateVertexIdentity,
            label: "Vertex",
            to: &issues
        )
        appendDuplicateIdentityIssue(
            ids: edges.map(\.id),
            kind: .duplicateEdgeIdentity,
            label: "Kante",
            to: &issues
        )
        appendDuplicateIdentityIssue(
            ids: faces.map(\.id),
            kind: .duplicateFaceIdentity,
            label: "Fläche",
            to: &issues
        )

        if triangleIndices.count % 3 != 0 {
            issues.append(issue(
                .incompleteTriangleIndices,
                severity: .error,
                subject: "indices",
                detail: "Die Indexanzahl ist nicht durch drei teilbar."
            ))
        }
        for (position, index) in triangleIndices.enumerated()
            where Int(index) >= points.count
        {
            issues.append(issue(
                .invalidTriangleIndex,
                severity: .error,
                subject: "\(position)",
                detail: "Index \(index) verweist auf keinen Vertex."
            ))
        }

        let expectedIndexCount = faces.reduce(0) {
            $0 + max(0, $1.vertexIDs.count - 2) * 3
        }
        if expectedIndexCount != triangleIndices.count {
            issues.append(issue(
                .triangleCountMismatch,
                severity: .error,
                subject: "triangles",
                detail: "Faces erwarten \(expectedIndexCount) Indizes, gespeichert sind \(triangleIndices.count)."
            ))
        }

        var faceEdgeUseCount: [MeshValidationEdgeKey: Int] = [:]
        var faceReferencedPointIDs: Set<UUID> = []
        for face in faces {
            let uniqueIDs = Set(face.vertexIDs)
            let hasInvalidReference = !uniqueIDs.isSubset(of: validPointIDs)
            if hasInvalidReference {
                issues.append(issue(
                    .invalidFaceReference,
                    severity: .error,
                    subject: face.id.uuidString,
                    detail: "Eine Fläche verweist auf einen fehlenden Vertex."
                ))
            }
            if uniqueIDs.count < 3 || faceArea(face, pointsByID: pointsByID) < 0.000_001 {
                issues.append(issue(
                    .degenerateFace,
                    severity: .error,
                    subject: face.id.uuidString,
                    detail: "Die Fläche besitzt keine gültige Fläche."
                ))
            }
            faceReferencedPointIDs.formUnion(uniqueIDs)
            guard face.vertexIDs.count >= 2 else { continue }
            for index in face.vertexIDs.indices {
                let key = MeshValidationEdgeKey(
                    face.vertexIDs[index],
                    face.vertexIDs[(index + 1) % face.vertexIDs.count]
                )
                faceEdgeUseCount[key, default: 0] += 1
            }
        }

        var explicitEdgeKeys: Set<MeshValidationEdgeKey> = []
        var edgeReferencedPointIDs: Set<UUID> = []
        for edge in edges {
            guard edge.vertexIDs.count == 2,
                edge.vertexIDs[0] != edge.vertexIDs[1],
                edge.vertexIDs.allSatisfy(validPointIDs.contains)
            else {
                issues.append(issue(
                    .invalidEdge,
                    severity: .error,
                    subject: edge.id.uuidString,
                    detail: "Die Kante besitzt ungültige Vertex-Referenzen."
                ))
                continue
            }
            edgeReferencedPointIDs.formUnion(edge.vertexIDs)
            let key = MeshValidationEdgeKey(edge.vertexIDs[0], edge.vertexIDs[1])
            if !explicitEdgeKeys.insert(key).inserted {
                issues.append(issue(
                    .duplicateEdge,
                    severity: .error,
                    subject: edge.id.uuidString,
                    detail: "Diese geometrische Kante ist mehrfach gespeichert."
                ))
            }
        }

        for (key, useCount) in faceEdgeUseCount {
            if !explicitEdgeKeys.contains(key) {
                issues.append(issue(
                    .missingTopologyEdge,
                    severity: .error,
                    subject: key.id,
                    detail: "Eine Face-Kante fehlt in der expliziten Topologie."
                ))
            }
            if useCount > 2 {
                issues.append(issue(
                    .nonManifoldEdge,
                    severity: .error,
                    subject: key.id,
                    detail: "Die Kante wird von \(useCount) Flächen verwendet."
                ))
            }
        }

        let referencedPointIDs = faceReferencedPointIDs.union(edgeReferencedPointIDs)
        for pointID in validPointIDs.subtracting(referencedPointIDs) {
            issues.append(issue(
                .orphanVertex,
                severity: .warning,
                subject: pointID.uuidString,
                detail: "Der Vertex wird von keiner Fläche oder Kante verwendet."
            ))
        }

        issues.sort {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.id < $1.id
        }
        return MeshValidationReport(
            vertexCount: points.count,
            edgeCount: edges.count,
            faceCount: faces.count,
            triangleCount: triangleIndices.count / 3,
            issues: issues
        )
    }

    private func appendDuplicateIdentityIssue(
        ids: [UUID],
        kind: MeshValidationIssueKind,
        label: String,
        to issues: inout [MeshValidationIssue]
    ) {
        var seen: Set<UUID> = []
        for id in ids where !seen.insert(id).inserted {
            issues.append(issue(
                kind,
                severity: .error,
                subject: id.uuidString,
                detail: "\(label)-UUID ist nicht eindeutig."
            ))
        }
    }

    private func issue(
        _ kind: MeshValidationIssueKind,
        severity: MeshValidationSeverity,
        subject: String,
        detail: String
    ) -> MeshValidationIssue {
        MeshValidationIssue(
            id: "\(kind.rawValue):\(subject)",
            kind: kind,
            severity: severity,
            detail: detail
        )
    }

    private func faceArea(
        _ face: MeshFace,
        pointsByID: [UUID: MeshControlPoint]
    ) -> Float {
        guard face.vertexIDs.count >= 3,
            let origin = pointsByID[face.vertexIDs[0]]?.position
        else { return 0 }
        var doubledArea: Float = 0
        for index in 1..<(face.vertexIDs.count - 1) {
            guard let second = pointsByID[face.vertexIDs[index]]?.position,
                let third = pointsByID[face.vertexIDs[index + 1]]?.position
            else { continue }
            let a = second - origin
            let b = third - origin
            let cross = SIMD3<Float>(
                a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x
            )
            doubledArea += sqrt(
                cross.x * cross.x + cross.y * cross.y + cross.z * cross.z
            )
        }
        return doubledArea / 2
    }
}

private struct MeshValidationEdgeKey: Hashable {
    let first: UUID
    let second: UUID

    var id: String { "\(first.uuidString):\(second.uuidString)" }

    init(_ lhs: UUID, _ rhs: UUID) {
        if lhs.uuidString < rhs.uuidString {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }
    }
}
