import Foundation

/// A committed directory is the transaction boundary: audio + manifest appear together.
/// Call only from one serial owner. Staging must happen before didReceive returns.
final class OfflineTrackStore {
    let root: URL
    let watchID: UUID
    private(set) var revision: Int
    private let fm = FileManager.default

    init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let identityURL = root.appendingPathComponent("identity.json")
        if fm.fileExists(atPath: identityURL.path) {
            watchID = try WatchWire.read(UUID.self, at: identityURL)
        } else {
            watchID = UUID()
            try WatchWire.write(watchID, to: identityURL)
        }
        revision = (try? WatchWire.read(Int.self, at: root.appendingPathComponent("revision.json"))) ?? 0
        // Incomplete transactions never enter inventory; remove only our known staging area.
        let staging = root.appendingPathComponent("Incoming", isDirectory: true)
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
    }

    func tracks() throws -> [OfflineTrack] {
        try fm.contentsOfDirectory(at: root.appendingPathComponent("Tracks"), includingPropertiesForKeys: nil)
            .compactMap { directory in
                guard let id = UUID(uuidString: directory.lastPathComponent),
                      let track = try? WatchWire.read(OfflineTrack.self, at: directory.appendingPathComponent("track.json")),
                      track.id == id, validExtension(track.fileExtension),
                      let size = try? audioURL(track).resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      Int64(size) == track.byteCount else { return nil }
                return track
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func audioURL(_ track: OfflineTrack) -> URL {
        directory(track.id).appendingPathComponent("audio.\(track.fileExtension)")
    }

    /// Synchronously owns and validates the temporary WC file before returning to the delegate.
    func receive(_ source: URL, delivery: TrackDelivery) throws {
        guard delivery.version == WatchWire.version, delivery.targetWatch == watchID,
              validExtension(delivery.track.fileExtension), delivery.track.byteCount > 0 else {
            throw StoreError.invalidDelivery
        }
        let transaction = root.appendingPathComponent("Incoming/\(delivery.attemptID.uuidString)")
        if fm.fileExists(atPath: transaction.path) { try fm.removeItem(at: transaction) }
        try fm.createDirectory(at: transaction, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: transaction) }
        let stagedAudio = transaction.appendingPathComponent("audio.\(delivery.track.fileExtension)")
        try fm.copyItem(at: source, to: stagedAudio)
        let size = try stagedAudio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) == delivery.track.byteCount,
              try WatchWire.checksum(stagedAudio) == delivery.track.sha256 else { throw StoreError.corruptFile }
        try WatchWire.write(delivery.track, to: transaction.appendingPathComponent("track.json"))
        let destination = directory(delivery.track.id)
        if fm.fileExists(atPath: destination.path) {
            // Duplicate deliveries are idempotent. A damaged record is recoverably replaced.
            if let existing = try? WatchWire.read(OfflineTrack.self, at: destination.appendingPathComponent("track.json")),
               existing == delivery.track, (try? WatchWire.checksum(audioURL(existing))) == existing.sha256 { return }
            _ = try fm.replaceItemAt(destination, withItemAt: transaction)
        } else {
            try fm.moveItem(at: transaction, to: destination)
        }
        revision += 1
        try WatchWire.write(revision, to: root.appendingPathComponent("revision.json"))
    }

    private func directory(_ id: UUID) -> URL { root.appendingPathComponent("Tracks/\(id.uuidString)") }
    private func validExtension(_ value: String) -> Bool {
        ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "mp4"].contains(value.lowercased())
    }
    enum StoreError: LocalizedError {
        case invalidDelivery, corruptFile
        var errorDescription: String? {
            switch self {
            case .invalidDelivery: return "The file belongs to another Watch or has an unsupported format."
            case .corruptFile: return "The received audio did not pass its size and checksum checks."
            }
        }
    }
}
