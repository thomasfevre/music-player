import Foundation
import WatchConnectivity

final class WatchLibrary: NSObject, ObservableObject {
    static let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    )[0]

    @Published private(set) var tracks: [WatchTrack] = []
    @Published private(set) var lastError: String?

    private var saveURL: URL {
        Self.documentsDirectory.appendingPathComponent("watch-library.json")
    }

    override init() {
        super.init()
        load()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var storageBytes: Int64 {
        tracks.reduce(0) { total, track in
            let size = (try? track.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: tracks[index].fileURL)
        }
        tracks.remove(atOffsets: offsets)
        save()
    }

    func clearError() {
        lastError = nil
    }

    private func receive(_ file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard
            let rawID = metadata["trackID"] as? String,
            let id = UUID(uuidString: rawID),
            let title = metadata["title"] as? String
        else {
            lastError = "A received track had invalid metadata."
            return
        }

        let ext = (metadata["fileExtension"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? file.fileURL.pathExtension
        let fileName = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        let destination = Self.documentsDirectory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
            let track = WatchTrack(
                id: id,
                title: title,
                artist: metadata["artist"] as? String ?? "",
                album: metadata["album"] as? String ?? "",
                duration: metadata["duration"] as? TimeInterval ?? 0,
                fileName: fileName,
                receivedAt: Date()
            )
            tracks.removeAll { $0.id == id }
            tracks.insert(track, at: 0)
            save()
            lastError = nil
        } catch {
            lastError = "Could not store \(title): \(error.localizedDescription)"
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        tracks = (try? JSONDecoder().decode([WatchTrack].self, from: data)) ?? []
        tracks.removeAll { !FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension WatchLibrary: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        DispatchQueue.main.async { self.receive(file) }
    }
}
