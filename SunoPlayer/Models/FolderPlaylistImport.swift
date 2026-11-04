import Foundation

/// One audio file discovered inside an imported folder.
struct FolderAudioFile: Identifiable, Equatable {
    let id = UUID()
    let relativePath: String
    let url: URL
    let byteCount: Int64

    var fileName: String { url.lastPathComponent }
    var folderPath: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}

/// A playlist that the folder scan proposes to create.
struct FolderPlaylistPlan: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let files: [FolderAudioFile]
}

struct FolderImportPlan: Equatable {
    let playlists: [FolderPlaylistPlan]
    let duplicateFileNames: [String]
    let ignoredFileCount: Int

    var totalTracks: Int { playlists.reduce(0) { $0 + $1.files.count } }
    var isEmpty: Bool { playlists.isEmpty }
}

enum FolderAudioFormat {
    /// Formats AVFoundation can open on iOS. FLAC is supported since iOS 11.
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "mp4", "flac"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

/// Pure planning logic for "import a folder as playlists".
/// One directory containing audio becomes one playlist named after the directory; nested
/// directories become their own playlists. No disk access happens here, which keeps it testable.
enum FolderImportPlanner {
    struct ScannedFile: Equatable {
        let url: URL
        let relativePath: String
        let byteCount: Int64
    }

    static func plan(
        scannedFiles: [ScannedFile],
        existingLibraryFileNames: Set<String>,
        existingPlaylistNames: Set<String> = [],
        rootFolderName: String = "Imported Playlist"
    ) -> FolderImportPlan {
        var accepted: [ScannedFile] = []
        var duplicates: [String] = []
        var ignored = 0
        var seenNames = Set(existingLibraryFileNames.map { $0.lowercased() })

        for file in scannedFiles.sorted(by: { $0.relativePath < $1.relativePath }) {
            guard FolderAudioFormat.isSupported(file.url) else {
                ignored += 1
                continue
            }
            let key = file.url.lastPathComponent.lowercased()
            guard seenNames.insert(key).inserted else {
                duplicates.append(file.relativePath)
                continue
            }
            accepted.append(file)
        }

        var grouped: [String: [ScannedFile]] = [:]
        var folderOrder: [String] = []
        for file in accepted {
            let folder = (file.relativePath as NSString).deletingLastPathComponent
            if grouped[folder] == nil { folderOrder.append(folder) }
            grouped[folder, default: []].append(file)
        }

        var usedNames = Set(existingPlaylistNames.map { $0.lowercased() })
        var playlists: [FolderPlaylistPlan] = []
        for folder in folderOrder {
            guard let files = grouped[folder], !files.isEmpty else { continue }
            let baseName = folder.isEmpty
                ? rootFolderName
                : (folder as NSString).lastPathComponent
            let name = uniqueName(baseName, used: &usedNames)
            playlists.append(
                FolderPlaylistPlan(
                    name: name,
                    files: files.map {
                        FolderAudioFile(relativePath: $0.relativePath, url: $0.url, byteCount: $0.byteCount)
                    }
                )
            )
        }
        return FolderImportPlan(
            playlists: playlists,
            duplicateFileNames: duplicates,
            ignoredFileCount: ignored
        )
    }

    private static func uniqueName(_ base: String, used: inout Set<String>) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "Imported Playlist" : trimmed
        guard used.contains(candidate.lowercased()) else {
            used.insert(candidate.lowercased())
            return candidate
        }
        var index = 2
        while used.contains("\(candidate) (\(index))".lowercased()) { index += 1 }
        let name = "\(candidate) (\(index))"
        used.insert(name.lowercased())
        return name
    }
}

/// Recursively enumerates a folder. Runs off the main actor because it touches the disk.
enum FolderScanner {
    static func scan(root: URL) throws -> [FolderImportPlanner.ScannedFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [FolderImportPlanner.ScannedFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(
                FolderImportPlanner.ScannedFile(
                    url: url,
                    relativePath: relative,
                    byteCount: Int64(values.fileSize ?? 0)
                )
            )
        }
        return files
    }
}
