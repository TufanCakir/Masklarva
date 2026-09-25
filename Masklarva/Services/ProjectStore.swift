import Foundation

actor ProjectStore {
    let autosaveURL: URL

    var backupURL: URL {
        autosaveURL
            .deletingLastPathComponent()
            .appending(path: "Autosave.backup.masklarva")
    }

    init(autosaveURL: URL? = nil) {
        if let autosaveURL {
            self.autosaveURL = autosaveURL
            return
        }
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.autosaveURL = applicationSupport
            .appending(path: "Masklarva", directoryHint: .isDirectory)
            .appending(path: "Autosave.masklarva")
    }

    func loadAutosave() throws -> ProjectLoadResult? {
        let primaryExists = fileExists(at: autosaveURL)
        let backupExists = fileExists(at: backupURL)
        guard primaryExists || backupExists else { return nil }

        if primaryExists {
            do {
                return ProjectLoadResult(
                    project: try decodeProject(at: autosaveURL),
                    recoveredFromBackup: false
                )
            } catch {
                guard backupExists else { throw error }
            }
        }

        return ProjectLoadResult(
            project: try decodeProject(at: backupURL),
            recoveredFromBackup: true
        )
    }

    func saveAutosave(_ project: MasklarvaProject) throws {
        let directory = autosaveURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        if fileExists(at: autosaveURL) {
            let previousData = try Data(contentsOf: autosaveURL)
            try previousData.write(to: backupURL, options: [.atomic])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(MasklarvaProjectFile(project: project))
        try data.write(to: autosaveURL, options: [.atomic])
    }

    private func decodeProject(at url: URL) throws -> MasklarvaProject {
        let data = try Data(contentsOf: url)
        let projectFile = try JSONDecoder().decode(
            MasklarvaProjectFile.self,
            from: data
        )
        guard projectFile.formatVersion <= MasklarvaProjectFile.currentVersion else {
            throw ProjectFileError.unsupportedVersion(projectFile.formatVersion)
        }
        return projectFile.project
    }

    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false)
        )
    }
}
