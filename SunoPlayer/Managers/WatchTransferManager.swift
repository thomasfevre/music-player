import Foundation
import WatchConnectivity

/// Queues local audio files for background delivery to the paired Apple Watch.
final class WatchTransferManager: NSObject, ObservableObject {
    static let shared = WatchTransferManager()

    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var pendingTrackIDs: Set<UUID> = []
    @Published private(set) var completedTrackIDs: Set<UUID> = []
    @Published private(set) var lastError: String?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshState(from: session)
    }

    var canTransfer: Bool {
        activationState == .activated && isWatchAppInstalled
    }

    var pendingCount: Int { pendingTrackIDs.count }

    @discardableResult
    func send(_ track: Track) -> Bool {
        guard canTransfer else {
            lastError = "Install Music Player on your paired Apple Watch first."
            return false
        }
        guard !pendingTrackIDs.contains(track.id) else { return false }
        guard FileManager.default.fileExists(atPath: track.fileURL.path) else {
            lastError = "The downloaded file for \(track.title) is missing."
            return false
        }

        let metadata: [String: Any] = [
            "trackID": track.id.uuidString,
            "title": track.title,
            "artist": track.artist ?? "",
            "album": track.album ?? "",
            "duration": track.duration,
            "fileExtension": track.fileURL.pathExtension
        ]
        WCSession.default.transferFile(track.fileURL, metadata: metadata)
        pendingTrackIDs.insert(track.id)
        lastError = nil
        return true
    }

    @discardableResult
    func send(_ tracks: [Track]) -> Int {
        var seen = Set<UUID>()
        return tracks.reduce(into: 0) { count, track in
            guard seen.insert(track.id).inserted else { return }
            if send(track) { count += 1 }
        }
    }

    func clearError() {
        lastError = nil
    }

    private func refreshState(from session: WCSession) {
        DispatchQueue.main.async {
            self.activationState = session.activationState
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
}

extension WatchTransferManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        refreshState(from: session)
        if let error {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        refreshState(from: session)
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        refreshState(from: session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshState(from: session)
    }

    func session(
        _ session: WCSession,
        fileTransfer: WCSessionFileTransfer,
        didFinishWithError error: Error?
    ) {
        guard
            let rawID = fileTransfer.file.metadata?["trackID"] as? String,
            let trackID = UUID(uuidString: rawID)
        else { return }

        DispatchQueue.main.async {
            self.pendingTrackIDs.remove(trackID)
            if let error {
                self.lastError = error.localizedDescription
            } else {
                self.completedTrackIDs.insert(trackID)
            }
        }
    }
}
