import Foundation
import Combine
import WatchConnectivity

/// All durable state and WC calls belong to `queue`; only snapshots cross to the UI.
final class WatchOfflineManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchOfflineManager()
    @Published private(set) var ledger = WatchTransferLedger()
    @Published private(set) var connection = "Activating Watch connection…"
    @Published private(set) var diagnostic: String?
    @Published private(set) var checkingInventory = false

    private let queue = DispatchQueue(label: "com.thomas.sunoplayer.watch-outbox")
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let root = Track.documentsDirectory.appendingPathComponent("WatchOutbox", isDirectory: true)
    private var state = WatchTransferLedger()
    private var requestID: UUID?
    private var requestDate = Date.distantPast
    private var inventoryFallbackWorkItem: DispatchWorkItem?
    private var ready = false
    private var storageHealthy = true
    private var timer: DispatchSourceTimer?
    private var stateURL: URL { root.appendingPathComponent("ledger.json") }

    private override init() {
        super.init()
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: stateURL.path) {
                    state = try WatchWire.read(WatchTransferLedger.self, at: stateURL)
                }
            } catch { storageHealthy = false; report("Cannot restore transfer queue: \(error.localizedDescription)") }
            publish()
            session?.delegate = self
            session?.activate()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 15, repeating: 15)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func send(_ tracks: [Track]) {
        let additions = tracks.map { WatchTransferJob(id: $0.id, title: $0.title, artist: $0.artist, sourceFileName: $0.fileName) }
        queue.async {
            guard self.storageHealthy else { return }
            for job in additions {
                if let index = self.state.jobs.firstIndex(where: { $0.id == job.id }) {
                    if [.failed, .cancelled].contains(self.state.jobs[index].phase) { self.state.jobs[index] = job }
                } else { self.state.jobs.append(job) }
            }
            self.state.paused = false
            guard self.save() else { return }
            self.requestInventory()
        }
    }

    /// Refresh is additive by ID. It never deletes Watch music absent from the iPhone.
    func refresh(_ tracks: [Track]) { send(tracks) }

    func checkInventory() { queue.async { self.requestInventory() } }

    func pause() {
        queue.async {
            self.state.paused = true
            _ = self.save()
        }
    }

    func resume() {
        queue.async {
            self.state.paused = false
            guard self.save() else { return }
            self.requestInventory()
        }
    }

    func retryFailures() {
        queue.async {
            for index in self.state.jobs.indices where self.state.jobs[index].phase == .failed {
                self.state.jobs[index].phase = .queued
                self.state.jobs[index].attempts = 0
                self.state.jobs[index].attemptID = nil
                self.state.jobs[index].error = nil
            }
            self.state.paused = false
            guard self.save() else { return }
            self.requestInventory()
        }
    }

    func cancelAll() {
        queue.async {
            self.state.paused = true
            for index in self.state.jobs.indices where ![.persisted, .failed].contains(self.state.jobs[index].phase) {
                self.state.jobs[index].phase = .cancelled
            }
            guard self.save() else { return }
            self.session?.outstandingFileTransfers.filter { $0.file.metadata?[WatchWire.kind] as? String == WatchWire.track }
                .forEach { $0.cancel() }
            self.publish()
        }
    }

    private func tick() {
        guard let session, session.activationState == .activated else { return }
        if requestID != nil {
            if Date().timeIntervalSince(requestDate) > 120 { requestInventory() }
        } else if state.jobs.contains(where: {
            ($0.phase == .awaitingReceipt || $0.phase == .transferring) && Date().timeIntervalSince($0.updatedAt) > 120
        }) { requestInventory() }
        else { pump() }
        updateConnection()
    }

    private func requestInventory() {
        ready = false
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            updateConnection(); publish(); return
        }
        let id = UUID()
        requestID = id
        requestDate = Date()
        inventoryFallbackWorkItem?.cancel()
        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.requestID == id else { return }
            self.requestID = nil
            self.ready = true
            self.report("Watch inventory timed out; starting a bounded bootstrap transfer.")
            self.updateConnection()
            self.publish()
            self.pump()
        }
        inventoryFallbackWorkItem = fallback
        queue.asyncAfter(deadline: .now() + 12, execute: fallback)
        let message: [String: Any] = [WatchWire.kind: WatchWire.request, "requestID": id.uuidString]
        do { try session.updateApplicationContext(message) }
        catch { report("Inventory request: \(error.localizedDescription)") }
        if session.isReachable { session.sendMessage(message, replyHandler: nil, errorHandler: { _ in }) }
        updateConnection()
        publish()
    }

    private func accept(_ inventory: WatchInventory) {
        guard inventory.version == WatchWire.version, inventory.requestID == requestID else { return }
        if inventory.watchID == state.watchID && inventory.revision < state.revision {
            requestInventory() // A receipt overtook this snapshot in transit.
            return
        }
        // Every activation is gated by a new nonce. Cached context cannot identify a new Watch.
        if state.watchID != nil && state.watchID != inventory.watchID {
            session?.outstandingFileTransfers.forEach { $0.cancel() }
            for index in state.jobs.indices { state.jobs[index].attempts = 0; state.jobs[index].attemptID = nil }
        }
        let outstanding = Set((session?.outstandingFileTransfers ?? []).compactMap { transfer -> UUID? in
            guard let data = transfer.file.metadata?[WatchWire.payload] as? Data,
                  let delivery = try? JSONDecoder().decode(TrackDelivery.self, from: data),
                  delivery.targetWatch == inventory.watchID else { return nil }
            return delivery.attemptID
        })
        state.reconcile(inventory, outstanding: outstanding)
        inventoryFallbackWorkItem?.cancel()
        inventoryFallbackWorkItem = nil
        requestID = nil
        ready = true
        guard save() else { return }
        cleanupStaging()
        updateConnection()
        pump()
    }

    private func pump() {
        guard storageHealthy, ready, requestID == nil, !state.paused,
              let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        // Awaiting an application receipt occupies a slot too: the receiver applies backpressure.
        var capacity = state.availableSlots(systemTransfers: session.outstandingFileTransfers.count)
        for index in state.jobs.indices where capacity > 0 && state.jobs[index].phase == .queued {
            let job = state.jobs[index]
            let attempt = UUID()
            let staged = root.appendingPathComponent(attempt.uuidString)
            do {
                let source = Track.documentsDirectory.appendingPathComponent(job.sourceFileName)
                try FileManager.default.copyItem(at: source, to: staged)
                let size = try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let track = OfflineTrack(id: job.id, title: job.title, artist: job.artist,
                                         fileExtension: source.pathExtension.lowercased(), byteCount: Int64(size),
                                         sha256: try WatchWire.checksum(staged))
                let delivery = TrackDelivery(version: WatchWire.version, attemptID: attempt, targetWatch: state.watchID, track: track)
                let metadata: [String: Any] = [WatchWire.kind: WatchWire.track, WatchWire.payload: try JSONEncoder().encode(delivery)]
                state.jobs[index].phase = .transferring
                state.jobs[index].attemptID = attempt
                state.jobs[index].attempts += 1
                state.jobs[index].updatedAt = Date()
                guard save() else { return } // Durable intent precedes submitting to the OS.
                session.transferFile(staged, metadata: metadata)
                capacity -= 1
            } catch {
                state.jobs[index].phase = .failed
                state.jobs[index].error = error.localizedDescription
                try? FileManager.default.removeItem(at: staged)
            }
        }
        _ = save()
    }

    private func cleanupStaging() {
        let live = Set((session?.outstandingFileTransfers ?? []).map { $0.file.fileURL.lastPathComponent })
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for file in files where UUID(uuidString: file.lastPathComponent) != nil && !live.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @discardableResult private func save() -> Bool {
        guard storageHealthy else { return false }
        do { try WatchWire.write(state, to: stateURL); publish(); return true }
        catch { storageHealthy = false; ready = false; report("Transfer queue could not be saved. Restart after freeing storage: \(error.localizedDescription)"); publish(); return false }
    }

    private func publish() {
        let snapshot = state
        let checking = requestID != nil
        DispatchQueue.main.async { self.ledger = snapshot; self.checkingInventory = checking }
    }

    private func report(_ value: String) { DispatchQueue.main.async { self.diagnostic = value } }
    private func updateConnection() {
        let text: String
        if session == nil { text = "WatchConnectivity is not supported." }
        else if session?.activationState != .activated { text = "Activating Watch connection…" }
        else if session?.isPaired != true { text = "Pair an Apple Watch to continue." }
        else if session?.isWatchAppInstalled != true { text = "Install SunoPlayer on your Watch." }
        else if requestID != nil { text = "Waiting for a fresh Watch inventory. Open SunoPlayer on Watch if needed." }
        else if session?.isReachable == true { text = "Watch is reachable. Background transfers are scheduled by watchOS." }
        else { text = "Watch is not reachable now. The system can continue queued transfers in the background." }
        DispatchQueue.main.async { self.connection = text }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        queue.sync {
            if let error { report(error.localizedDescription) }
            requestInventory()
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) { queue.sync { ready = false; requestID = nil; updateConnection(); publish() } }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { queue.sync { requestInventory() } }
    func sessionReachabilityDidChange(_ session: WCSession) { queue.sync { updateConnection(); if session.isReachable { requestInventory() } } }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        queue.sync {
            guard let data = fileTransfer.file.metadata?[WatchWire.payload] as? Data,
                  let delivery = try? JSONDecoder().decode(TrackDelivery.self, from: data) else { return }
            // A receipt may arrive before this callback. Never demote a persisted job.
            state.transportFinished(attemptID: delivery.attemptID, error: error?.localizedDescription)
            try? FileManager.default.removeItem(at: root.appendingPathComponent(delivery.attemptID.uuidString))
            guard save() else { return }
            pump()
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        queue.sync {
            guard userInfo[WatchWire.kind] as? String == WatchWire.receipt,
                  let data = userInfo[WatchWire.payload] as? Data,
                  let receipt = try? JSONDecoder().decode(WatchReceipt.self, from: data) else { return }
            state.apply(receipt)
            guard save() else { return }
            pump()
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Decode synchronously while WC owns this URL. No deferred access to its temporary file.
        guard file.metadata?[WatchWire.kind] as? String == WatchWire.inventory else { return }
        queue.sync {
            do { accept(try WatchWire.read(WatchInventory.self, at: file.fileURL)) }
            catch { report("Cannot read Watch inventory: \(error.localizedDescription)") }
        }
    }
}
