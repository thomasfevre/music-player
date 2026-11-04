import Foundation

/// Durable description of a folder import, so a background task can resume it.
struct FolderImportJob: Codable, Identifiable, Equatable {
    struct PlaylistSpec: Codable, Equatable {
        let name: String
        let relativePaths: [String]
        let collidesWithExisting: Bool
    }

    let id: UUID
    var bookmark: Data?
    var folderName: String
    var playlists: [PlaylistSpec]
    var totalFiles: Int
    var strategy: String
    var createdAt: Date

    var allRelativePaths: [String] { playlists.flatMap(\.relativePaths) }
}

struct FolderImportSummary: Equatable {
    var playlistsCreated = 0
    var playlistsMerged = 0
    var tracksImported = 0
    var duplicates = 0
    var ignored = 0
    var failures = 0
    var emptyPlaylists: [String] = []
    var failureReasons: [String] = []
}

enum FolderImportJobStore {
    static var directory: URL {
        Track.documentsDirectory.appendingPathComponent("FolderImports", isDirectory: true)
    }
    static var jobURL: URL { directory.appendingPathComponent("job.json") }

    static func save(_ job: FolderImportJob) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
    }

    static func load() -> FolderImportJob? {
        guard let data = try? Data(contentsOf: jobURL) else { return nil }
        return try? JSONDecoder().decode(FolderImportJob.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: jobURL)
    }
}
