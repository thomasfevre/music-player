import Foundation
import WatchConnectivity

/// Queues local audio files for background delivery to the paired Apple Watch.
final class WatchTransferManager: NSObject, ObservableObject {
    static let shared = WatchTransferManager()

    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var pendingTrackIDs: Set<UUID> = []
    @Published private(set) var completedTrackIDs: Set<UUID> = []
    @Published private(set) var batchTotal = 0
    @Published private(set) var batchCompleted = 0
    @Published private(set) var watchStorageBytes: Int64?
    @Published private(set) var watchAvailableBytes: Int64?
    @Published private(set) var watchTrackIDs: Set<UUID> = []
    @Published private(set) var lastError: String?

    private let maxConcurrentTransfers = 8
    private var scheduledTracks: [Track] = []
    private var inFlightTrackIDs: Set<UUID> = []

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshState(from: session)
        syncOutstandingTransfers(from: session)
    }

    var canTransfer: Bool {
        activationState == .activated && isWatchAppInstalled
    }

    var pendingCount: Int { pendingTrackIDs.count }

    var batchProgress: Double {
        guard batchTotal > 0 else { return 0 }
        return Double(batchCompleted) / Double(batchTotal)
    }

    @discardableResult
    func send(_ track: Track) -> Bool {
        send([track]) == 1
    }

    @discardableResult
    func send(_ tracks: [Track]) -> Int {
        guard canTransfer else {
            lastError = "Install Music Player on your paired Apple Watch first."
            return 0
        }

        let candidates = tracks.filter { track in
            !watchTrackIDs.contains(track.id)
                && !pendingTrackIDs.contains(track.id)
                && FileManager.default.fileExists(atPath: track.fileURL.path)
        }
        var seen = Set<UUID>()
        let uniqueCandidates = candidates.filter { seen.insert($0.id).inserted }
        guard !uniqueCandidates.isEmpty else { return 0 }
        batchTotal = uniqueCandidates.count
        batchCompleted = 0
        scheduledTracks.append(contentsOf: uniqueCandidates)
        pumpTransfers()
        return uniqueCandidates.count
    }

    func refresh(with tracks: [Track]) -> Int { send(tracks) }

    func cancelPendingTransfers() {
        WCSession.default.outstandingFileTransfers.forEach { $0.cancel() }
        scheduledTracks.removeAll()
        inFlightTrackIDs.removeAll()
        pendingTrackIDs.removeAll()
        batchTotal = 0
        batchCompleted = 0
    }

    func clearError() {
        lastError = nil
    }

    private func refreshState(from session: WCSession) {
        let context = session.receivedApplicationContext
        let stored = (context["watchStorageBytes"] as? NSNumber)?.int64Value
        let available = (context["watchAvailableBytes"] as? NSNumber)?.int64Value
        let trackIDs = (context["watchTrackIDs"] as? [String])?.compactMap(UUID.init(uuidString:)) ?? []
        DispatchQueue.main.async {
            self.activationState = session.activationState
            self.isWatchAppInstalled = session.isWatchAppInstalled
            if let stored { self.watchStorageBytes = stored }
            if let available { self.watchAvailableBytes = available }
            self.watchTrackIDs = Set(trackIDs)
        }
    }

    private func pumpTransfers() {
        while inFlightTrackIDs.count < maxConcurrentTransfers, !scheduledTracks.isEmpty {
            let track = scheduledTracks.removeFirst()
            guard !pendingTrackIDs.contains(track.id) else { continue }
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
            inFlightTrackIDs.insert(track.id)
        }
    }

    private func syncOutstandingTransfers(from session: WCSession) {
        let outstandingIDs = session.outstandingFileTransfers.compactMap { transfer in
            (transfer.file.metadata?["trackID"] as? String).flatMap(UUID.init(uuidString:))
        }
        DispatchQueue.main.async {
            self.pendingTrackIDs = Set(outstandingIDs)
            self.inFlightTrackIDs = Set(outstandingIDs)
            if self.batchTotal == 0, !outstandingIDs.isEmpty {
                self.batchTotal = outstandingIDs.count
                self.batchCompleted = 0
            }
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
        syncOutstandingTransfers(from: session)
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
        syncOutstandingTransfers(from: session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshState(from: session)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let stored = (applicationContext["watchStorageBytes"] as? NSNumber)?.int64Value
        let available = (applicationContext["watchAvailableBytes"] as? NSNumber)?.int64Value
        let trackIDs = (applicationContext["watchTrackIDs"] as? [String])?.compactMap(UUID.init(uuidString:)) ?? []
        DispatchQueue.main.async {
            self.watchStorageBytes = stored
            self.watchAvailableBytes = available
            self.watchTrackIDs = Set(trackIDs)
        }
    }

    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        guard
            let rawID = fileTransfer.file.metadata?["trackID"] as? String,
            let trackID = UUID(uuidString: rawID)
        else { return }

        DispatchQueue.main.async {
            guard self.pendingTrackIDs.remove(trackID) != nil else { return }
            self.inFlightTrackIDs.remove(trackID)
            if let error {
                self.lastError = error.localizedDescription
            } else {
                self.completedTrackIDs.insert(trackID)
            }
            if self.batchCompleted < self.batchTotal {
                self.batchCompleted += 1
            }
            self.pumpTransfers()
        }
    }
}
