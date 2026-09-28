import Foundation

struct MeshControlPoint: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
    var tangent: SIMD4<Float>

    init(
        id: UUID = UUID(),
        position: SIMD3<Float>,
        normal: SIMD3<Float> = [0, 1, 0],
        uv: SIMD2<Float> = .zero,
        tangent: SIMD4<Float> = [1, 0, 0, 1]
    ) {
        self.id = id
        self.position = position
        self.normal = normal
        self.uv = uv
        self.tangent = tangent
    }

    private enum CodingKeys: String, CodingKey {
        case id, position, normal, uv, tangent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        position = try container.decode(SIMD3<Float>.self, forKey: .position)
        normal = try container.decodeIfPresent(
            SIMD3<Float>.self,
            forKey: .normal
        ) ?? [0, 1, 0]
        uv = try container.decodeIfPresent(SIMD2<Float>.self, forKey: .uv) ?? .zero
        tangent = try container.decodeIfPresent(
            SIMD4<Float>.self,
            forKey: .tangent
        ) ?? [1, 0, 0, 1]
    }
}

struct MeshEdge: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var vertexIDs: [UUID]

    init(id: UUID = UUID(), vertexIDs: [UUID]) {
        precondition(vertexIDs.count == 2, "An edge requires exactly two vertices.")
        self.id = id
        self.vertexIDs = vertexIDs
    }
}

struct MeshFace: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var vertexIDs: [UUID]
    var materialIndex: Int

    init(
        id: UUID = UUID(),
        vertexIDs: [UUID],
        materialIndex: Int = 0
    ) {
        self.id = id
        self.vertexIDs = vertexIDs
        self.materialIndex = materialIndex
    }
}

enum MeshSelectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case vertex
    case edge
    case face

    var id: Self { self }

    var title: String {
        switch self {
        case .vertex: "Punkte"
        case .edge: "Kanten"
        case .face: "Flächen"
        }
    }

    var symbol: String {
        switch self {
        case .vertex: "circle.fill"
        case .edge: "line.diagonal"
        case .face: "square.fill"
        }
    }
}

struct MeshSelection: Codable, Equatable, Sendable {
    var mode: MeshSelectionMode = .vertex
    var vertexIDs: Set<UUID> = []
    var edgeIDs: Set<UUID> = []
    var faceIDs: Set<UUID> = []

    mutating func deselectAll() {
        vertexIDs.removeAll()
        edgeIDs.removeAll()
        faceIDs.removeAll()
    }
}

struct SkeletonJoint: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var position: SIMD3<Float>

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        position: SIMD3<Float>
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.position = position
    }
}

struct VertexWeight: Codable, Equatable, Sendable {
    var pointID: UUID
    var jointID: UUID
    var weight: Float

    init(pointID: UUID, jointID: UUID, weight: Float) {
        self.pointID = pointID
        self.jointID = jointID
        self.weight = min(max(weight, 0), 1)
    }
}

/// CPU-owned mesh data. RealityKit and future Metal renderers consume this
/// representation but do not own topology or editor selection state.
struct EditableGeometry: Codable, Equatable, Sendable {
    var points: [MeshControlPoint]
    var triangleIndices: [UInt32]
    var edges: [MeshEdge]
    var faces: [MeshFace]
    var joints: [SkeletonJoint]
    var weights: [VertexWeight]
    var selection: MeshSelection

    init(
        points: [MeshControlPoint] = [],
        triangleIndices: [UInt32] = [],
        edges: [MeshEdge] = [],
        faces: [MeshFace] = [],
        joints: [SkeletonJoint] = [],
        weights: [VertexWeight] = [],
        selection: MeshSelection = MeshSelection()
    ) {
        self.points = points
        self.triangleIndices = triangleIndices
        self.edges = edges
        self.faces = faces
        self.joints = joints
        self.weights = weights
        self.selection = selection
        if self.edges.isEmpty || self.faces.isEmpty {
            rebuildTopologyIfNeeded()
        }
    }

    var selectedPointID: UUID? {
        get { selection.vertexIDs.first }
        set {
            selection.vertexIDs = newValue.map { [$0] } ?? []
        }
    }

    mutating func setSelectionMode(_ mode: MeshSelectionMode) {
        selection.mode = mode
    }

    mutating func toggleSelection(_ id: UUID) {
        switch selection.mode {
        case .vertex:
            toggle(id, in: &selection.vertexIDs)
        case .edge:
            toggle(id, in: &selection.edgeIDs)
        case .face:
            toggle(id, in: &selection.faceIDs)
        }
    }

    mutating func selectAll() {
        switch selection.mode {
        case .vertex: selection.vertexIDs = Set(points.map(\.id))
        case .edge: selection.edgeIDs = Set(edges.map(\.id))
        case .face: selection.faceIDs = Set(faces.map(\.id))
        }
    }

    mutating func deselectAll() {
        selection.deselectAll()
    }

    mutating func invertSelection() {
        switch selection.mode {
        case .vertex:
            selection.vertexIDs = Set(points.map(\.id)).subtracting(
                selection.vertexIDs
            )
        case .edge:
            selection.edgeIDs = Set(edges.map(\.id)).subtracting(
                selection.edgeIDs
            )
        case .face:
            selection.faceIDs = Set(faces.map(\.id)).subtracting(
                selection.faceIDs
            )
        }
    }

    @discardableResult
    mutating func deleteSelectedGeometry() -> Bool {
        let pointIDs = Set(points.map(\.id))
        let selectedVertexIDs: Set<UUID>
        let selectedEdgeIDs: Set<UUID>
        let selectedFaceIDs: Set<UUID>

        switch selection.mode {
        case .vertex:
            selectedVertexIDs = selection.vertexIDs.intersection(pointIDs)
            selectedEdgeIDs = []
            selectedFaceIDs = []
        case .edge:
            selectedVertexIDs = []
            selectedEdgeIDs = selection.edgeIDs
            selectedFaceIDs = []
        case .face:
            selectedVertexIDs = []
            selectedEdgeIDs = []
            selectedFaceIDs = selection.faceIDs
        }

        guard !selectedVertexIDs.isEmpty
            || !selectedEdgeIDs.isEmpty
            || !selectedFaceIDs.isEmpty
        else { return false }

        let deletedEdgePairs = Set(
            edges
                .filter { selectedEdgeIDs.contains($0.id) && $0.vertexIDs.count == 2 }
                .map { VertexPair($0.vertexIDs[0], $0.vertexIDs[1]) }
        )
        faces.removeAll { face in
            if selectedFaceIDs.contains(face.id) { return true }
            if !selectedVertexIDs.isDisjoint(with: face.vertexIDs) { return true }
            return Self.faceEdgePairs(face).contains { deletedEdgePairs.contains($0) }
        }
        edges.removeAll { edge in
            selectedEdgeIDs.contains(edge.id)
                || !selectedVertexIDs.isDisjoint(with: edge.vertexIDs)
        }
        if !selectedVertexIDs.isEmpty {
            points.removeAll { selectedVertexIDs.contains($0.id) }
            weights.removeAll { selectedVertexIDs.contains($0.pointID) }
        }

        removeInvalidTopologyReferences()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.deselectAll()
        return true
    }

    @discardableResult
    mutating func recalculateNormals() -> Bool {
        guard !points.isEmpty, triangleIndices.count >= 3 else { return false }
        var accumulated = Array(repeating: SIMD3<Float>.zero, count: points.count)
        var updatedTriangle = false
        for start in stride(
            from: 0,
            to: triangleIndices.count - triangleIndices.count % 3,
            by: 3
        ) {
            let first = Int(triangleIndices[start])
            let second = Int(triangleIndices[start + 1])
            let third = Int(triangleIndices[start + 2])
            guard points.indices.contains(first), points.indices.contains(second),
                points.indices.contains(third)
            else { continue }
            let a = points[second].position - points[first].position
            let b = points[third].position - points[first].position
            let normal = Self.cross(a, b)
            accumulated[first] += normal
            accumulated[second] += normal
            accumulated[third] += normal
            updatedTriangle = true
        }
        guard updatedTriangle else { return false }
        for index in points.indices {
            let normal = accumulated[index]
            let length = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
            points[index].normal = length > 0.000_001 ? normal / length : [0, 1, 0]
        }
        return true
    }

    mutating func extractSelectedFaces() -> EditableGeometry? {
        guard selection.mode == .face else { return nil }
        let selectedFaceIDs = selection.faceIDs
        let extractedFaces = faces.filter { selectedFaceIDs.contains($0.id) }
        guard !extractedFaces.isEmpty else { return nil }

        let extractedVertexIDs = Set(extractedFaces.flatMap(\.vertexIDs))
        let pointIDMap = Dictionary(
            uniqueKeysWithValues: extractedVertexIDs.map { ($0, UUID()) }
        )
        let extractedPoints = points.compactMap { point -> MeshControlPoint? in
            guard let newID = pointIDMap[point.id] else { return nil }
            return MeshControlPoint(
                id: newID,
                position: point.position,
                normal: point.normal,
                uv: point.uv,
                tangent: point.tangent
            )
        }
        let remappedFaces = extractedFaces.map { face in
            MeshFace(
                vertexIDs: face.vertexIDs.compactMap { pointIDMap[$0] },
                materialIndex: face.materialIndex
            )
        }
        let remappedEdges = Self.edges(for: remappedFaces)
        let remappedWeights = weights.compactMap { weight -> VertexWeight? in
            guard let newPointID = pointIDMap[weight.pointID] else { return nil }
            return VertexWeight(
                pointID: newPointID,
                jointID: weight.jointID,
                weight: weight.weight
            )
        }

        var extracted = EditableGeometry(
            points: extractedPoints,
            edges: remappedEdges,
            faces: remappedFaces,
            joints: joints,
            weights: remappedWeights,
            selection: MeshSelection(mode: .face)
        )
        extracted.rebuildTriangleIndicesFromFaces()
        extracted.recalculateNormals()

        faces.removeAll { selectedFaceIDs.contains($0.id) }
        pruneToReferencedFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.deselectAll()
        return extracted
    }

    @discardableResult
    mutating func extrudeSelectedFaces(distance: Float) -> Bool {
        guard selection.mode == .face, abs(distance) > 0.000_001 else { return false }
        let selectedFaceIDs = selection.faceIDs
        let selectedFaces = faces.filter { selectedFaceIDs.contains($0.id) }
        guard !selectedFaces.isEmpty else { return false }

        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        var normalSums: [UUID: SIMD3<Float>] = [:]
        var edgeOccurrences: [VertexPair: DirectedBoundaryEdge] = [:]
        for face in selectedFaces {
            guard let normal = Self.normal(for: face, pointsByID: pointsByID) else {
                continue
            }
            for vertexID in face.vertexIDs {
                normalSums[vertexID, default: .zero] += normal
            }
            for index in face.vertexIDs.indices {
                let start = face.vertexIDs[index]
                let end = face.vertexIDs[(index + 1) % face.vertexIDs.count]
                let pair = VertexPair(start, end)
                if var occurrence = edgeOccurrences[pair] {
                    occurrence.count += 1
                    edgeOccurrences[pair] = occurrence
                } else {
                    edgeOccurrences[pair] = DirectedBoundaryEdge(
                        start: start,
                        end: end,
                        materialIndex: face.materialIndex
                    )
                }
            }
        }
        guard !normalSums.isEmpty else { return false }

        let pointIDMap = Dictionary(
            uniqueKeysWithValues: normalSums.keys.map { ($0, UUID()) }
        )
        let duplicatedPoints = points.compactMap { point -> MeshControlPoint? in
            guard let newID = pointIDMap[point.id],
                let normalSum = normalSums[point.id]
            else { return nil }
            return MeshControlPoint(
                id: newID,
                position: point.position + Self.normalized(normalSum) * distance,
                normal: point.normal,
                uv: point.uv,
                tangent: point.tangent
            )
        }
        points.append(contentsOf: duplicatedPoints)
        let duplicatedWeights = weights.compactMap { weight -> VertexWeight? in
            guard let newPointID = pointIDMap[weight.pointID] else { return nil }
            return VertexWeight(
                pointID: newPointID,
                jointID: weight.jointID,
                weight: weight.weight
            )
        }
        weights.append(contentsOf: duplicatedWeights)

        for index in faces.indices where selectedFaceIDs.contains(faces[index].id) {
            faces[index].vertexIDs = faces[index].vertexIDs.compactMap { pointIDMap[$0] }
        }
        for boundary in edgeOccurrences.values where boundary.count == 1 {
            guard let newStart = pointIDMap[boundary.start],
                let newEnd = pointIDMap[boundary.end]
            else { continue }
            faces.append(
                MeshFace(
                    vertexIDs: [boundary.start, boundary.end, newEnd, newStart],
                    materialIndex: boundary.materialIndex
                )
            )
        }

        pruneUnusedPoints()
        synchronizeEdgesWithFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.vertexIDs.removeAll()
        selection.edgeIDs.removeAll()
        return true
    }

    @discardableResult
    mutating func insetSelectedFaces(amount: Float) -> Bool {
        guard selection.mode == .face, amount > 0, amount < 1 else { return false }
        let selectedFaceIDs = selection.faceIDs
        let selectedFaces = faces.filter { selectedFaceIDs.contains($0.id) }
        guard !selectedFaces.isEmpty else { return false }

        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        guard selectedFaces.allSatisfy({ face in
            face.vertexIDs.count >= 3
                && face.vertexIDs.allSatisfy { pointsByID[$0] != nil }
        }) else { return false }

        var newPoints: [MeshControlPoint] = []
        var newWeights: [VertexWeight] = []
        var borderFaces: [MeshFace] = []
        var insetVertexIDsByFace: [UUID: [UUID]] = [:]

        for face in selectedFaces {
            let sourcePoints = face.vertexIDs.compactMap { pointsByID[$0] }
            let centerPosition = sourcePoints.reduce(SIMD3<Float>.zero) {
                $0 + $1.position
            } / Float(sourcePoints.count)
            let centerUV = sourcePoints.reduce(SIMD2<Float>.zero) {
                $0 + $1.uv
            } / Float(sourcePoints.count)
            var insetVertexIDs: [UUID] = []

            for point in sourcePoints {
                let insetID = UUID()
                insetVertexIDs.append(insetID)
                newPoints.append(
                    MeshControlPoint(
                        id: insetID,
                        position: point.position + (centerPosition - point.position) * amount,
                        normal: point.normal,
                        uv: point.uv + (centerUV - point.uv) * amount,
                        tangent: point.tangent
                    )
                )
                newWeights.append(contentsOf: weights.compactMap { weight in
                    guard weight.pointID == point.id else { return nil }
                    return VertexWeight(
                        pointID: insetID,
                        jointID: weight.jointID,
                        weight: weight.weight
                    )
                })
            }
            insetVertexIDsByFace[face.id] = insetVertexIDs
            for index in face.vertexIDs.indices {
                let next = (index + 1) % face.vertexIDs.count
                borderFaces.append(
                    MeshFace(
                        vertexIDs: [
                            face.vertexIDs[index],
                            face.vertexIDs[next],
                            insetVertexIDs[next],
                            insetVertexIDs[index],
                        ],
                        materialIndex: face.materialIndex
                    )
                )
            }
        }

        points.append(contentsOf: newPoints)
        weights.append(contentsOf: newWeights)
        for index in faces.indices {
            guard let insetVertexIDs = insetVertexIDsByFace[faces[index].id] else {
                continue
            }
            faces[index].vertexIDs = insetVertexIDs
        }
        faces.append(contentsOf: borderFaces)
        synchronizeEdgesWithFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.vertexIDs.removeAll()
        selection.edgeIDs.removeAll()
        return true
    }

    @discardableResult
    mutating func bevelSelectedEdge(width: Float) -> Bool {
        guard selection.mode == .edge, selection.edgeIDs.count == 1,
            width > 0,
            let selectedEdgeID = selection.edgeIDs.first,
            let selectedEdge = edges.first(where: { $0.id == selectedEdgeID }),
            selectedEdge.vertexIDs.count == 2
        else { return false }

        let firstVertexID = selectedEdge.vertexIDs[0]
        let secondVertexID = selectedEdge.vertexIDs[1]
        let selectedPair = VertexPair(firstVertexID, secondVertexID)
        let adjacentFaces = faces.filter {
            Self.faceEdgePairs($0).contains(selectedPair)
        }
        guard adjacentFaces.count == 2 else { return false }

        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        var replacementIDsByFace: [UUID: [UUID: UUID]] = [:]
        var beveledPoints: [MeshControlPoint] = []
        var beveledWeights: [VertexWeight] = []

        for face in adjacentFaces {
            for (vertexID, otherEdgeVertexID) in [
                (firstVertexID, secondVertexID),
                (secondVertexID, firstVertexID),
            ] {
                guard let source = pointsByID[vertexID],
                    let sourceIndex = face.vertexIDs.firstIndex(of: vertexID)
                else { return false }
                let previousID = face.vertexIDs[
                    (sourceIndex - 1 + face.vertexIDs.count) % face.vertexIDs.count
                ]
                let nextID = face.vertexIDs[(sourceIndex + 1) % face.vertexIDs.count]
                let neighborID = previousID == otherEdgeVertexID ? nextID : previousID
                guard neighborID != otherEdgeVertexID,
                    let neighbor = pointsByID[neighborID]
                else { return false }

                let direction = neighbor.position - source.position
                let edgeLength = sqrt(
                    direction.x * direction.x
                        + direction.y * direction.y
                        + direction.z * direction.z
                )
                guard edgeLength > 0.000_001 else { return false }
                let fraction = min(width / edgeLength, 0.45)
                let beveledID = UUID()
                replacementIDsByFace[face.id, default: [:]][vertexID] = beveledID
                beveledPoints.append(
                    MeshControlPoint(
                        id: beveledID,
                        position: source.position + direction * fraction,
                        normal: source.normal,
                        uv: source.uv + (neighbor.uv - source.uv) * fraction,
                        tangent: source.tangent
                    )
                )
                beveledWeights.append(contentsOf: weights.compactMap { weight in
                    guard weight.pointID == vertexID else { return nil }
                    return VertexWeight(
                        pointID: beveledID,
                        jointID: weight.jointID,
                        weight: weight.weight
                    )
                })
            }
        }

        guard let firstFaceIDs = replacementIDsByFace[adjacentFaces[0].id],
            let secondFaceIDs = replacementIDsByFace[adjacentFaces[1].id],
            let firstA = firstFaceIDs[firstVertexID],
            let firstB = firstFaceIDs[secondVertexID],
            let secondA = secondFaceIDs[firstVertexID],
            let secondB = secondFaceIDs[secondVertexID]
        else { return false }

        points.append(contentsOf: beveledPoints)
        weights.append(contentsOf: beveledWeights)
        for index in faces.indices {
            guard let replacements = replacementIDsByFace[faces[index].id] else {
                continue
            }
            faces[index].vertexIDs = faces[index].vertexIDs.map {
                replacements[$0] ?? $0
            }
        }
        faces.append(
            MeshFace(
                vertexIDs: [firstA, firstB, secondB, secondA],
                materialIndex: adjacentFaces[0].materialIndex
            )
        )
        pruneUnusedPoints()
        synchronizeEdgesWithFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.deselectAll()
        return true
    }

    @discardableResult
    mutating func weldSelectedVerticesToCenter() -> Bool {
        guard selection.mode == .vertex else { return false }
        let selectedPoints = points.filter { selection.vertexIDs.contains($0.id) }
        guard selectedPoints.count >= 2, let survivor = selectedPoints.first,
            let survivorIndex = points.firstIndex(where: { $0.id == survivor.id })
        else { return false }

        let selectedIDs = Set(selectedPoints.map(\.id))
        let count = Float(selectedPoints.count)
        let centerPosition = selectedPoints.reduce(SIMD3<Float>.zero) {
            $0 + $1.position
        } / count
        let centerUV = selectedPoints.reduce(SIMD2<Float>.zero) {
            $0 + $1.uv
        } / count
        let centerTangent = selectedPoints.reduce(SIMD4<Float>.zero) {
            $0 + $1.tangent
        } / count

        points[survivorIndex].position = centerPosition
        points[survivorIndex].uv = centerUV
        points[survivorIndex].tangent = centerTangent
        points.removeAll {
            $0.id != survivor.id && selectedIDs.contains($0.id)
        }

        for index in faces.indices {
            let remapped = faces[index].vertexIDs.map {
                selectedIDs.contains($0) ? survivor.id : $0
            }
            faces[index].vertexIDs = Self.uniquePolygonVertexIDs(remapped)
        }
        faces.removeAll { $0.vertexIDs.count < 3 }

        let selectedWeights = weights.filter { selectedIDs.contains($0.pointID) }
        var weightByJoint: [UUID: Float] = [:]
        for weight in selectedWeights {
            weightByJoint[weight.jointID, default: 0] += weight.weight / count
        }
        let totalWeight = weightByJoint.values.reduce(0, +)
        weights.removeAll { selectedIDs.contains($0.pointID) }
        if totalWeight > 0.000_001 {
            weights.append(contentsOf: weightByJoint.map { jointID, weight in
                VertexWeight(
                    pointID: survivor.id,
                    jointID: jointID,
                    weight: weight / totalWeight
                )
            })
        }

        pruneUnusedPoints()
        synchronizeEdgesWithFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.vertexIDs = [survivor.id]
        selection.edgeIDs.removeAll()
        selection.faceIDs.removeAll()
        return true
    }

    @discardableResult
    mutating func duplicateSelectedGeometry(
        offset: SIMD3<Float> = .zero
    ) -> Bool {
        switch selection.mode {
        case .vertex:
            let selectedPoints = points.filter {
                selection.vertexIDs.contains($0.id)
            }
            guard !selectedPoints.isEmpty else { return false }
            let pointIDMap = duplicatePoints(Set(selectedPoints.map(\.id)))
            selection.vertexIDs = Set(pointIDMap.values)
            selection.edgeIDs.removeAll()
            selection.faceIDs.removeAll()

        case .edge:
            let selectedEdges = edges.filter { selection.edgeIDs.contains($0.id) }
            guard !selectedEdges.isEmpty else { return false }
            let sourceVertexIDs = Set(selectedEdges.flatMap(\.vertexIDs))
            let availableVertexIDs = Set(points.map(\.id))
            guard sourceVertexIDs.isSubset(of: availableVertexIDs),
                selectedEdges.allSatisfy({ $0.vertexIDs.count == 2 })
            else { return false }
            let pointIDMap = duplicatePoints(sourceVertexIDs)
            let duplicatedEdges = selectedEdges.map { edge in
                MeshEdge(vertexIDs: edge.vertexIDs.compactMap { pointIDMap[$0] })
            }
            edges.append(contentsOf: duplicatedEdges)
            selection.vertexIDs.removeAll()
            selection.edgeIDs = Set(duplicatedEdges.map(\.id))
            selection.faceIDs.removeAll()

        case .face:
            let selectedFaces = faces.filter { selection.faceIDs.contains($0.id) }
            guard !selectedFaces.isEmpty else { return false }
            let sourceVertexIDs = Set(selectedFaces.flatMap(\.vertexIDs))
            let availableVertexIDs = Set(points.map(\.id))
            guard sourceVertexIDs.isSubset(of: availableVertexIDs),
                selectedFaces.allSatisfy({ $0.vertexIDs.count >= 3 })
            else { return false }
            let pointIDMap = duplicatePoints(sourceVertexIDs)
            let duplicatedFaces = selectedFaces.map { face in
                MeshFace(
                    vertexIDs: face.vertexIDs.compactMap { pointIDMap[$0] },
                    materialIndex: face.materialIndex
                )
            }
            faces.append(contentsOf: duplicatedFaces)
            edges.append(contentsOf: Self.edges(for: duplicatedFaces))
            rebuildTriangleIndicesFromFaces()
            recalculateNormals()
            selection.vertexIDs.removeAll()
            selection.edgeIDs.removeAll()
            selection.faceIDs = Set(duplicatedFaces.map(\.id))
        }
        if offset != .zero {
            let selectedPointIDs = pointIDsForCurrentSelection()
            for index in points.indices where selectedPointIDs.contains(points[index].id) {
                points[index].position += offset
            }
        }
        return true
    }

    @discardableResult
    mutating func flipSelectedFaceNormals() -> Bool {
        guard selection.mode == .face else { return false }
        let selectedFaceIDs = selection.faceIDs
        let selectedFaces = faces.filter { selectedFaceIDs.contains($0.id) }
        guard !selectedFaces.isEmpty else { return false }

        let selectedVertexIDs = Set(selectedFaces.flatMap(\.vertexIDs))
        let unselectedVertexIDs = Set(
            faces
                .filter { !selectedFaceIDs.contains($0.id) }
                .flatMap(\.vertexIDs)
        )
        let sharedVertexIDs = selectedVertexIDs.intersection(unselectedVertexIDs)
        let splitPointIDMap = duplicatePoints(sharedVertexIDs)

        for index in faces.indices where selectedFaceIDs.contains(faces[index].id) {
            faces[index].vertexIDs = faces[index].vertexIDs
                .map { splitPointIDMap[$0] ?? $0 }
                .reversed()
        }
        let flippedVertexIDs = Set(
            faces
                .filter { selectedFaceIDs.contains($0.id) }
                .flatMap(\.vertexIDs)
        )
        for index in points.indices where flippedVertexIDs.contains(points[index].id) {
            points[index].tangent.w *= -1
        }

        synchronizeEdgesWithFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.vertexIDs.removeAll()
        selection.edgeIDs.removeAll()
        return true
    }

    @discardableResult
    mutating func linearSubdivide() -> Bool {
        subdivide(smoothingStrength: 0)
    }

    @discardableResult
    mutating func catmullClarkSubdivide(strength: Float) -> Bool {
        guard strength >= 0, strength <= 1 else { return false }
        return subdivide(smoothingStrength: strength)
    }

    private mutating func subdivide(smoothingStrength: Float) -> Bool {
        guard !faces.isEmpty else { return false }
        let sourceFaces = faces
        let pointsByID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        guard sourceFaces.allSatisfy({ face in
            face.vertexIDs.count >= 3
                && face.vertexIDs.allSatisfy { pointsByID[$0] != nil }
        }) else { return false }

        let faceCenterPositions = Dictionary(
            uniqueKeysWithValues: sourceFaces.map { face in
                let facePoints = face.vertexIDs.compactMap { pointsByID[$0] }
                let center = facePoints.reduce(SIMD3<Float>.zero) {
                    $0 + $1.position
                } / Float(facePoints.count)
                return (face.id, center)
            }
        )
        var faceIDsByEdge: [VertexPair: [UUID]] = [:]
        var faceIDsByVertex: [UUID: Set<UUID>] = [:]
        var neighborIDsByVertex: [UUID: Set<UUID>] = [:]
        for face in sourceFaces {
            for vertexID in face.vertexIDs {
                faceIDsByVertex[vertexID, default: []].insert(face.id)
            }
            for index in face.vertexIDs.indices {
                let firstID = face.vertexIDs[index]
                let secondID = face.vertexIDs[(index + 1) % face.vertexIDs.count]
                faceIDsByEdge[VertexPair(firstID, secondID), default: []].append(face.id)
                neighborIDsByVertex[firstID, default: []].insert(secondID)
                neighborIDsByVertex[secondID, default: []].insert(firstID)
            }
        }

        var midpointIDByEdge: [VertexPair: UUID] = [:]
        var centerIDByFace: [UUID: UUID] = [:]
        var generatedPoints: [MeshControlPoint] = []
        var generatedWeights: [VertexWeight] = []

        for face in sourceFaces {
            let facePoints = face.vertexIDs.compactMap { pointsByID[$0] }
            let centerID = UUID()
            centerIDByFace[face.id] = centerID
            generatedPoints.append(
                MeshControlPoint(
                    id: centerID,
                    position: faceCenterPositions[face.id] ?? .zero,
                    normal: facePoints.reduce(SIMD3<Float>.zero) {
                        $0 + $1.normal
                    } / Float(facePoints.count),
                    uv: facePoints.reduce(SIMD2<Float>.zero) {
                        $0 + $1.uv
                    } / Float(facePoints.count),
                    tangent: facePoints.reduce(SIMD4<Float>.zero) {
                        $0 + $1.tangent
                    } / Float(facePoints.count)
                )
            )
            generatedWeights.append(
                contentsOf: averagedWeights(
                    for: face.vertexIDs,
                    newPointID: centerID
                )
            )

            for index in face.vertexIDs.indices {
                let firstID = face.vertexIDs[index]
                let secondID = face.vertexIDs[(index + 1) % face.vertexIDs.count]
                let pair = VertexPair(firstID, secondID)
                guard midpointIDByEdge[pair] == nil,
                    let first = pointsByID[firstID],
                    let second = pointsByID[secondID]
                else { continue }
                let midpointID = UUID()
                midpointIDByEdge[pair] = midpointID
                let linearPosition = (first.position + second.position) / 2
                let adjacentFaceIDs = faceIDsByEdge[pair] ?? []
                let smoothedPosition: SIMD3<Float>
                if adjacentFaceIDs.count == 2,
                    let firstCenter = faceCenterPositions[adjacentFaceIDs[0]],
                    let secondCenter = faceCenterPositions[adjacentFaceIDs[1]]
                {
                    smoothedPosition = (
                        first.position + second.position + firstCenter + secondCenter
                    ) / 4
                } else {
                    smoothedPosition = linearPosition
                }
                generatedPoints.append(
                    MeshControlPoint(
                        id: midpointID,
                        position: Self.interpolate(
                            linearPosition,
                            smoothedPosition,
                            amount: smoothingStrength
                        ),
                        normal: (first.normal + second.normal) / 2,
                        uv: (first.uv + second.uv) / 2,
                        tangent: (first.tangent + second.tangent) / 2
                    )
                )
                generatedWeights.append(
                    contentsOf: averagedWeights(
                        for: [firstID, secondID],
                        newPointID: midpointID
                    )
                )
            }
        }

        if smoothingStrength > 0 {
            var boundaryNeighborIDs: [UUID: Set<UUID>] = [:]
            for (pair, faceIDs) in faceIDsByEdge where faceIDs.count == 1 {
                boundaryNeighborIDs[pair.first, default: []].insert(pair.second)
                boundaryNeighborIDs[pair.second, default: []].insert(pair.first)
            }
            for index in points.indices {
                let pointID = points[index].id
                guard let sourcePoint = pointsByID[pointID] else { continue }
                let smoothedPosition: SIMD3<Float>
                let boundaryNeighbors = boundaryNeighborIDs[pointID] ?? []
                if boundaryNeighbors.count == 2 {
                    let positions = boundaryNeighbors.compactMap {
                        pointsByID[$0]?.position
                    }
                    guard positions.count == 2 else { continue }
                    smoothedPosition = (
                        sourcePoint.position * 6 + positions[0] + positions[1]
                    ) / 8
                } else {
                    let faceIDs = faceIDsByVertex[pointID] ?? []
                    let neighborIDs = neighborIDsByVertex[pointID] ?? []
                    guard faceIDs.count >= 3, !neighborIDs.isEmpty else { continue }
                    let faceAverage = faceIDs.compactMap { faceCenterPositions[$0] }
                        .reduce(SIMD3<Float>.zero, +) / Float(faceIDs.count)
                    let edgeAverage = neighborIDs.compactMap { neighborID in
                        pointsByID[neighborID].map {
                            (sourcePoint.position + $0.position) / 2
                        }
                    }.reduce(SIMD3<Float>.zero, +) / Float(neighborIDs.count)
                    let valence = Float(faceIDs.count)
                    smoothedPosition = (
                        faceAverage
                            + edgeAverage * 2
                            + sourcePoint.position * (valence - 3)
                    ) / valence
                }
                points[index].position = Self.interpolate(
                    sourcePoint.position,
                    smoothedPosition,
                    amount: smoothingStrength
                )
            }
        }

        let previouslySelectedFaces = selection.faceIDs
        var subdividedFaces: [MeshFace] = []
        var subdividedSelection: Set<UUID> = []
        for face in sourceFaces {
            guard let centerID = centerIDByFace[face.id] else { continue }
            for index in face.vertexIDs.indices {
                let vertexID = face.vertexIDs[index]
                let nextID = face.vertexIDs[(index + 1) % face.vertexIDs.count]
                let previousID = face.vertexIDs[
                    (index - 1 + face.vertexIDs.count) % face.vertexIDs.count
                ]
                guard let nextMidpointID = midpointIDByEdge[
                    VertexPair(vertexID, nextID)
                ], let previousMidpointID = midpointIDByEdge[
                    VertexPair(previousID, vertexID)
                ] else { continue }
                let child = MeshFace(
                    id: index == 0 ? face.id : UUID(),
                    vertexIDs: [
                        vertexID,
                        nextMidpointID,
                        centerID,
                        previousMidpointID,
                    ],
                    materialIndex: face.materialIndex
                )
                subdividedFaces.append(child)
                if previouslySelectedFaces.contains(face.id) {
                    subdividedSelection.insert(child.id)
                }
            }
        }

        guard !subdividedFaces.isEmpty else { return false }
        points.append(contentsOf: generatedPoints)
        weights.append(contentsOf: generatedWeights)
        faces = subdividedFaces
        synchronizeEdgesWithFaces()
        rebuildTriangleIndicesFromFaces()
        recalculateNormals()
        selection.vertexIDs.removeAll()
        selection.edgeIDs.removeAll()
        selection.faceIDs = subdividedSelection
        return true
    }

    static var cube: EditableGeometry {
        let positions: [SIMD3<Float>] = [
            [0.45, 0.45, -0.45], [-0.45, 0.45, -0.45],
            [-0.45, 0.45, 0.45], [0.45, 0.45, 0.45],
            [0.45, -0.45, -0.45], [-0.45, -0.45, -0.45],
            [-0.45, -0.45, 0.45], [0.45, -0.45, 0.45],
        ]
        let points = positions.map { position in
            let length = sqrt(
                position.x * position.x
                    + position.y * position.y
                    + position.z * position.z
            )
            return MeshControlPoint(
                position: position,
                normal: position / length,
                uv: [position.x + 0.5, position.z + 0.5]
            )
        }
        let faceVertexIndices: [[Int]] = [
            [0, 1, 2, 3], [4, 7, 6, 5], [0, 3, 7, 4],
            [0, 4, 5, 1], [2, 1, 5, 6], [3, 2, 6, 7],
        ]
        let faces = faceVertexIndices.map { indices in
            MeshFace(vertexIDs: indices.map { points[$0].id })
        }
        let edgeIndices = [
            [0, 1], [1, 2], [2, 3], [3, 0],
            [4, 5], [5, 6], [6, 7], [7, 4],
            [0, 4], [1, 5], [2, 6], [3, 7],
        ]
        let edges = edgeIndices.map { indices in
            MeshEdge(vertexIDs: indices.map { points[$0].id })
        }
        return EditableGeometry(
            points: points,
            triangleIndices: [
                0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
                0, 3, 7, 7, 4, 0, 0, 4, 1, 4, 5, 1,
                2, 1, 5, 5, 6, 2, 3, 2, 6, 6, 7, 3,
            ],
            edges: edges,
            faces: faces
        )
    }

    private enum CodingKeys: String, CodingKey {
        case points, triangleIndices, edges, faces, joints, weights, selection
        case selectedPointID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decodeIfPresent(
            [MeshControlPoint].self,
            forKey: .points
        ) ?? []
        triangleIndices = try container.decodeIfPresent(
            [UInt32].self,
            forKey: .triangleIndices
        ) ?? []
        edges = try container.decodeIfPresent([MeshEdge].self, forKey: .edges) ?? []
        faces = try container.decodeIfPresent([MeshFace].self, forKey: .faces) ?? []
        joints = try container.decodeIfPresent(
            [SkeletonJoint].self,
            forKey: .joints
        ) ?? []
        weights = try container.decodeIfPresent(
            [VertexWeight].self,
            forKey: .weights
        ) ?? []
        selection = try container.decodeIfPresent(
            MeshSelection.self,
            forKey: .selection
        ) ?? MeshSelection()
        if let legacySelectedID = try container.decodeIfPresent(
            UUID.self,
            forKey: .selectedPointID
        ) {
            selection.vertexIDs = [legacySelectedID]
        }
        rebuildTopologyIfNeeded()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
        try container.encode(triangleIndices, forKey: .triangleIndices)
        try container.encode(edges, forKey: .edges)
        try container.encode(faces, forKey: .faces)
        try container.encode(joints, forKey: .joints)
        try container.encode(weights, forKey: .weights)
        try container.encode(selection, forKey: .selection)
    }

    private func toggle(_ id: UUID, in selection: inout Set<UUID>) {
        if selection.remove(id) == nil {
            selection.insert(id)
        }
    }

    private static func faceEdgePairs(_ face: MeshFace) -> [VertexPair] {
        guard face.vertexIDs.count >= 2 else { return [] }
        return face.vertexIDs.indices.map { index in
            VertexPair(
                face.vertexIDs[index],
                face.vertexIDs[(index + 1) % face.vertexIDs.count]
            )
        }
    }

    private static func edges(for faces: [MeshFace]) -> [MeshEdge] {
        var pairs: Set<VertexPair> = []
        var result: [MeshEdge] = []
        for face in faces {
            for pair in faceEdgePairs(face) where pairs.insert(pair).inserted {
                result.append(MeshEdge(vertexIDs: [pair.first, pair.second]))
            }
        }
        return result
    }

    private static func normal(
        for face: MeshFace,
        pointsByID: [UUID: MeshControlPoint]
    ) -> SIMD3<Float>? {
        guard face.vertexIDs.count >= 3,
            let first = pointsByID[face.vertexIDs[0]]?.position,
            let second = pointsByID[face.vertexIDs[1]]?.position,
            let third = pointsByID[face.vertexIDs[2]]?.position
        else { return nil }
        let value = cross(second - first, third - first)
        let normalizedValue = normalized(value)
        return normalizedValue == .zero ? nil : normalizedValue
    }

    private mutating func duplicatePoints(
        _ pointIDs: Set<UUID>
    ) -> [UUID: UUID] {
        let sourcePoints = points.filter { pointIDs.contains($0.id) }
        let pointIDMap = Dictionary(
            uniqueKeysWithValues: sourcePoints.map { ($0.id, UUID()) }
        )
        let duplicatedPoints = sourcePoints.compactMap { point -> MeshControlPoint? in
            guard let duplicatedID = pointIDMap[point.id] else { return nil }
            return MeshControlPoint(
                id: duplicatedID,
                position: point.position,
                normal: point.normal,
                uv: point.uv,
                tangent: point.tangent
            )
        }
        let sourceWeights = weights.filter { pointIDs.contains($0.pointID) }
        let duplicatedWeights = sourceWeights.compactMap { weight -> VertexWeight? in
            guard let duplicatedID = pointIDMap[weight.pointID] else { return nil }
            return VertexWeight(
                pointID: duplicatedID,
                jointID: weight.jointID,
                weight: weight.weight
            )
        }
        points.append(contentsOf: duplicatedPoints)
        weights.append(contentsOf: duplicatedWeights)
        return pointIDMap
    }

    private func averagedWeights(
        for pointIDs: [UUID],
        newPointID: UUID
    ) -> [VertexWeight] {
        guard !pointIDs.isEmpty else { return [] }
        let sourceIDs = Set(pointIDs)
        var weightByJoint: [UUID: Float] = [:]
        for weight in weights where sourceIDs.contains(weight.pointID) {
            weightByJoint[weight.jointID, default: 0] += weight.weight
                / Float(pointIDs.count)
        }
        let total = weightByJoint.values.reduce(0, +)
        guard total > 0.000_001 else { return [] }
        return weightByJoint.map { jointID, weight in
            VertexWeight(
                pointID: newPointID,
                jointID: jointID,
                weight: weight / total
            )
        }
    }

    private func pointIDsForCurrentSelection() -> Set<UUID> {
        switch selection.mode {
        case .vertex:
            selection.vertexIDs
        case .edge:
            Set(
                edges
                    .filter { selection.edgeIDs.contains($0.id) }
                    .flatMap(\.vertexIDs)
            )
        case .face:
            Set(
                faces
                    .filter { selection.faceIDs.contains($0.id) }
                    .flatMap(\.vertexIDs)
            )
        }
    }

    private static func uniquePolygonVertexIDs(_ vertexIDs: [UUID]) -> [UUID] {
        var result: [UUID] = []
        var seen: Set<UUID> = []
        for vertexID in vertexIDs where seen.insert(vertexID).inserted {
            result.append(vertexID)
        }
        return result
    }

    private static func normalized(_ value: SIMD3<Float>) -> SIMD3<Float> {
        let length = sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
        return length > 0.000_001 ? value / length : .zero
    }

    private static func interpolate(
        _ start: SIMD3<Float>,
        _ end: SIMD3<Float>,
        amount: Float
    ) -> SIMD3<Float> {
        start + (end - start) * amount
    }

    private mutating func pruneUnusedPoints() {
        let referencedVertexIDs = Set(faces.flatMap(\.vertexIDs))
        points.removeAll { !referencedVertexIDs.contains($0.id) }
        weights.removeAll { !referencedVertexIDs.contains($0.pointID) }
    }

    private mutating func synchronizeEdgesWithFaces() {
        let existingEdges = Dictionary(
            uniqueKeysWithValues: edges.compactMap { edge -> (VertexPair, MeshEdge)? in
                guard edge.vertexIDs.count == 2 else { return nil }
                return (VertexPair(edge.vertexIDs[0], edge.vertexIDs[1]), edge)
            }
        )
        var seenPairs: Set<VertexPair> = []
        var synchronized: [MeshEdge] = []
        for face in faces {
            for pair in Self.faceEdgePairs(face) where seenPairs.insert(pair).inserted {
                synchronized.append(
                    existingEdges[pair] ?? MeshEdge(vertexIDs: [pair.first, pair.second])
                )
            }
        }
        edges = synchronized
        selection.edgeIDs.formIntersection(edges.map(\.id))
        selection.vertexIDs.formIntersection(points.map(\.id))
    }

    private mutating func pruneToReferencedFaces() {
        let referencedVertexIDs = Set(faces.flatMap(\.vertexIDs))
        var referencedEdgePairs: Set<VertexPair> = []
        for face in faces {
            referencedEdgePairs.formUnion(Self.faceEdgePairs(face))
        }
        points.removeAll { !referencedVertexIDs.contains($0.id) }
        edges.removeAll { edge in
            guard edge.vertexIDs.count == 2 else { return true }
            return !referencedEdgePairs.contains(
                VertexPair(edge.vertexIDs[0], edge.vertexIDs[1])
            )
        }
        weights.removeAll { !referencedVertexIDs.contains($0.pointID) }
    }

    private mutating func removeInvalidTopologyReferences() {
        let validVertexIDs = Set(points.map(\.id))
        faces.removeAll {
            $0.vertexIDs.count < 3 || !$0.vertexIDs.allSatisfy(validVertexIDs.contains)
        }
        edges.removeAll {
            $0.vertexIDs.count != 2 || !$0.vertexIDs.allSatisfy(validVertexIDs.contains)
        }
    }

    private mutating func rebuildTriangleIndicesFromFaces() {
        let indicesByID = Dictionary(
            uniqueKeysWithValues: points.enumerated().map { ($0.element.id, UInt32($0.offset)) }
        )
        triangleIndices = faces.flatMap { face -> [UInt32] in
            let indices = face.vertexIDs.compactMap { indicesByID[$0] }
            guard indices.count == face.vertexIDs.count, indices.count >= 3 else { return [] }
            return (1..<(indices.count - 1)).flatMap {
                [indices[0], indices[$0], indices[$0 + 1]]
            }
        }
    }

    private static func cross(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> SIMD3<Float> {
        [
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x,
        ]
    }

    private mutating func rebuildTopologyIfNeeded() {
        guard !points.isEmpty else { return }
        var derivedEdges: [MeshEdge] = []
        var edgeKeys: Set<VertexPair> = []
        var derivedFaces: [MeshFace] = []

        for triangleStart in stride(
            from: 0,
            to: triangleIndices.count - triangleIndices.count % 3,
            by: 3
        ) {
            let indices = triangleIndices[triangleStart..<(triangleStart + 3)]
                .map(Int.init)
            guard indices.allSatisfy({ points.indices.contains($0) }) else {
                continue
            }
            let vertexIDs = indices.map { points[$0].id }
            derivedFaces.append(MeshFace(vertexIDs: vertexIDs))
            for pair in [(0, 1), (1, 2), (2, 0)] {
                let key = VertexPair(vertexIDs[pair.0], vertexIDs[pair.1])
                if edgeKeys.insert(key).inserted {
                    derivedEdges.append(
                        MeshEdge(vertexIDs: [key.first, key.second])
                    )
                }
            }
        }
        if edges.isEmpty { edges = derivedEdges }
        if faces.isEmpty { faces = derivedFaces }
    }
}

private struct DirectedBoundaryEdge {
    var start: UUID
    var end: UUID
    var materialIndex: Int
    var count = 1
}

private struct VertexPair: Hashable {
    let first: UUID
    let second: UUID

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
