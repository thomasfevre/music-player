import Foundation
import AVFoundation
import Combine

// MARK: - MusicLibraryManager
/// Manages the local track library: importing, persisting, sorting, and searching tracks.
@MainActor
final class MusicLibraryManager: ObservableObject {

    // MARK: Published State
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isImporting: Bool = false
    @Published var sortOrder: SortOrder = .newest
    @Published var searchText: String = ""

    // MARK: Persistence
    private let saveFileName = "library.json"
    private var saveURL: URL {
        Track.documentsDirectory.appendingPathComponent(saveFileName)
    }

    // MARK: Init
    init() {
        loadLibrary()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED") {
            seedDemoLibrary()
        }
        #endif
    }

    #if DEBUG
    /// Populates a demo library for App Store screenshot capture (DEBUG only, launch-arg gated).
    /// The first track gets a real silent file so playback / now-playing renders.
    func seedDemoLibrary() {
        let meta: [(String, String, TimeInterval)] = [
            ("Midnight Drive", "NEON", 210),
            ("Velvet Sky", "Aurora Keys", 184),
            ("Coastline", "The Tides", 232),
            ("Paper Planes", "Lo-Fi Club", 167),
            ("Golden Hour", "Sundara", 198),
            ("Echoes", "Mono Lake", 245),
        ]
        var demo: [Track] = []
        for (i, m) in meta.enumerated() {
            let fileName = "demo-\(i).wav"
            if i == 0 {
                try? Self.silentWAV(seconds: m.2).write(to: Track.documentsDirectory.appendingPathComponent(fileName))
            }
            demo.append(Track(title: m.0, artist: m.1, fileName: fileName, duration: m.2,
                              dateImported: Date().addingTimeInterval(Double(-i) * 3600)))
        }
        tracks = demo
    }

    private static func silentWAV(seconds: Double, sampleRate: Int = 8000) -> Data {
        let bytesPerSample = 2
        let dataSize = Int(seconds * Double(sampleRate)) * bytesPerSample
        var d = Data()
        func s(_ x: String) { d.append(x.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        s("RIFF"); u32(UInt32(36 + dataSize)); s("WAVE"); s("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * bytesPerSample)); u16(UInt16(bytesPerSample)); u16(16)
        s("data"); u32(UInt32(dataSize)); d.append(Data(count: dataSize))
        return d
    }
    #endif

    // MARK: - Computed: Filtered & Sorted Tracks
    var displayedTracks: [Track] {
        TrackQuery.apply(tracks: tracks, searchText: searchText, sortOrder: sortOrder)
    }

    // MARK: - Import
    /// Imports audio files from the given URLs into the app's documents directory.
    /// File copying and metadata extraction run off the main actor; results are published on it.
    /// Skips duplicates based on file name.
    func importTracks(from urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return } // ignore overlapping imports (dedup race)
        isImporting = true
        let existingNames = Set(tracks.map(\.fileName))
        let docDir = Track.documentsDirectory

        Task {
            let imported = await Self.processImports(
                urls: urls,
                existingNames: existingNames,
                docDir: docDir
            )
            tracks.append(contentsOf: imported)
            if !imported.isEmpty { saveLibrary() }
            isImporting = false
        }
    }

    nonisolated private static func processImports(
        urls: [URL],
        existingNames: Set<String>,
        docDir: URL
    ) async -> [Track] {
        let fm = FileManager.default
        var result: [Track] = []
        var seen = existingNames

        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            let fileName = url.lastPathComponent
            if seen.contains(fileName) { continue }
            let destination = docDir.appendingPathComponent(fileName)

            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: url, to: destination)

                let (title, artist, duration) = await extractMetadata(from: destination, fallbackName: fileName)
                result.append(
                    Track(title: title, artist: artist, fileName: fileName, duration: duration, dateImported: Date())
                )
                seen.insert(fileName)
            } catch {
                print("Failed to import \(fileName): \(error)")
            }
        }
        return result
    }

    // MARK: - Delete
    /// Deletes a track. Removes the backing file first; only on success does it mutate the
    /// in-memory library and persist. Returns true on success so the caller can coordinate the
    /// player. If persistence fails, the load-time existence filter reconciles on next launch.
    @discardableResult
    func deleteTrack(_ track: Track) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: track.fileURL.path) {
            do {
                try fm.removeItem(at: track.fileURL)
            } catch {
                print("Failed to delete file for \(track.title): \(error)")
                return false
            }
        }
        tracks.removeAll { $0.id == track.id }
        saveLibrary()
        return true
    }

    // MARK: - Metadata Extraction
    nonisolated private static func extractMetadata(
        from url: URL,
        fallbackName: String
    ) async -> (title: String, artist: String?, duration: TimeInterval) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        var duration: TimeInterval = 0
        var title = cleanFileName(fallbackName)
        var artist: String? = nil

        do {
            let loadedDuration = try await asset.load(.duration).seconds
            if loadedDuration.isFinite && !loadedDuration.isNaN && loadedDuration >= 0 {
                duration = loadedDuration
            }
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata {
                if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue), !value.isEmpty {
                    title = value
                }
                if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue) {
                    artist = value.isEmpty ? nil : value
                }
            }
        } catch {
            print("Metadata load failed for \(fallbackName): \(error)")
        }

        return (title, artist, duration)
    }

    /// Strips file extension and cleans up underscores/hyphens for display.
    nonisolated private static func cleanFileName(_ name: String) -> String {
        let noExt = (name as NSString).deletingPathExtension
        return noExt
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - Persistence
    private func saveLibrary() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save library: \(error)")
        }
    }

    private func loadLibrary() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([Track].self, from: data)
            // Filter out tracks whose audio files no longer exist on disk.
            tracks = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        } catch {
            print("Failed to load library: \(error)")
        }
    }
}
