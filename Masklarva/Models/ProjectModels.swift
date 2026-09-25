import Foundation

struct MasklarvaScene: Identifiable, Equatable {
    var id: UUID
    var name: String
    var document: ModelDocument

    init(
        id: UUID = UUID(),
        name: String,
        document: ModelDocument = .empty
    ) {
        self.id = id
        self.name = name
        self.document = document
    }
}

struct MasklarvaProject: Equatable {
    var id: UUID
    var name: String
    private(set) var scenes: [MasklarvaScene]
    private(set) var activeSceneID: UUID

    init(
        id: UUID = UUID(),
        name: String,
        scenes: [MasklarvaScene],
        activeSceneID: UUID? = nil
    ) {
        let initialScenes = scenes.isEmpty
            ? [MasklarvaScene(name: "Scene")]
            : scenes
        self.id = id
        self.name = name
        self.scenes = initialScenes
        self.activeSceneID = activeSceneID.flatMap { requestedID in
            initialScenes.contains { $0.id == requestedID } ? requestedID : nil
        } ?? initialScenes[0].id
    }

    static let sample: MasklarvaProject = {
        let scene = MasklarvaScene(name: "Main Scene", document: .sample)
        return MasklarvaProject(
            name: "Untitled Project",
            scenes: [scene],
            activeSceneID: scene.id
        )
    }()

    var activeSceneIndex: Int {
        scenes.firstIndex { $0.id == activeSceneID } ?? 0
    }

    var activeSceneName: String {
        scenes[activeSceneIndex].name
    }

    var activeDocument: ModelDocument {
        get { scenes[activeSceneIndex].document }
        set { scenes[activeSceneIndex].document = newValue }
    }

    var canDeleteScene: Bool { scenes.count > 1 }
    mutating func selectScene(_ id: UUID) {
        guard scenes.contains(where: { $0.id == id }) else { return }
        activeSceneID = id
    }

    mutating func createScene() {
        let scene = MasklarvaScene(name: uniqueSceneName(base: "Scene"))
        scenes.append(scene)
        activeSceneID = scene.id
    }

    mutating func duplicateActiveScene() {
        let source = scenes[activeSceneIndex]
        let duplicate = MasklarvaScene(
            name: uniqueSceneName(base: "\(source.name) Copy"),
            document: source.document.duplicateForNewScene()
        )
        scenes.insert(duplicate, at: activeSceneIndex + 1)
        activeSceneID = duplicate.id
    }

    mutating func renameActiveScene(to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != activeSceneName else { return }
        scenes[activeSceneIndex].name = name
    }

    mutating func deleteActiveScene() {
        guard canDeleteScene else { return }
        let removedIndex = activeSceneIndex
        scenes.remove(at: removedIndex)
        activeSceneID = scenes[min(removedIndex, scenes.count - 1)].id
    }

    private func uniqueSceneName(base: String) -> String {
        let names = Set(scenes.map(\.name))
        guard names.contains(base) else { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}
