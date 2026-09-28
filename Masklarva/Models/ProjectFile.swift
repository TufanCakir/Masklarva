import Foundation

nonisolated struct MasklarvaProjectFile: Codable, Sendable {
    static let currentVersion = 2

    var formatVersion: Int
    var project: MasklarvaProject

    init(project: MasklarvaProject) {
        formatVersion = Self.currentVersion
        self.project = project
    }
}

nonisolated enum ProjectFileError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Diese Projektdatei verwendet die nicht unterstützte Version \(version)."
        }
    }
}

nonisolated struct ProjectLoadResult: Sendable {
    var project: MasklarvaProject
    var recoveredFromBackup: Bool
}
