import Foundation
import Combine
import WatchConnectivity
import WatchKit

final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchBridge()
    @Published private(set) var tracks: [OfflineTrack] = []
    @Published private(set) var status = "Ready for offline music"
    @Published private(set) var error: String?
    private let queue = DispatchQueue(label: "com.thomas.sunoplayer.watch-library")
    private let session = WCSession.default
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OfflineMusic", isDirectory: true)
    private var store: OfflineTrackStore?
    private var pendingRequest: UUID?
    private var receipts: [WatchReceipt] = []
    private var observation: NSKeyValueObservation?
    var backgroundDrained: (() -> Void)?
    private var receiptsURL: URL { root.appendingPathComponent("receipts.json") }

    private override init() {
        super.init()
        queue.sync {
            do {
                store = try OfflineTrackStore(root: root)
                if FileManager.default.fileExists(atPath: receiptsURL.path) {
                    receipts = try WatchWire.read([WatchReceipt].self, at: receiptsURL)
                }
                publish()
            } catch { report(error) }
            session.delegate = self
            observation = session.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in
                self?.queue.async { self?.finishBackgroundIfDrained() }
            }
            session.activate()
        }
    }

    func foreground() {
        queue.async {
            self.readRequest(self.session.receivedApplicationContext)
            self.flush()
            self.publish()
        }
    }

    func checkBackgroundCompletion() { queue.async { self.finishBackgroundIfDrained() } }

    func audioURL(_ track: OfflineTrack) -> URL {
        root.appendingPathComponent("Tracks/\(track.id.uuidString)/audio.\(track.fileExtension)")
    }

    private func readRequest(_ message: [String: Any]) {
        guard message[WatchWire.kind] as? String == WatchWire.request,
              let text = message["requestID"] as? String, let id = UUID(uuidString: text) else { return }
        pendingRequest = id
        flush()
    }

    private func flush() {
        guard session.activationState == .activated, let store else { return }
        let sentReceipts = Set(session.outstandingUserInfoTransfers.compactMap { transfer -> UUID? in
            guard let data = transfer.userInfo[WatchWire.payload] as? Data,
                  let receipt = try? JSONDecoder().decode(WatchReceipt.self, from: data) else { return nil }
            return receipt.attemptID
        })
        for receipt in receipts where !sentReceipts.contains(receipt.attemptID) {
            if let data = try? JSONEncoder().encode(receipt) {
                session.transferUserInfo([WatchWire.kind: WatchWire.receipt, WatchWire.payload: data])
            }
        }
        // Inventory is a file, not applicationContext: large libraries do not hit message-size limits.
        guard let requestID = pendingRequest, session.outstandingFileTransfers.isEmpty else { return }
        do {
            let snapshot = WatchInventory(version: WatchWire.version, requestID: requestID, watchID: store.watchID,
                                          revision: store.revision, trackIDs: Set(try store.tracks().map(\.id)), generatedAt: Date())
            let directory = root.appendingPathComponent("Snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString + ".json")
            try WatchWire.write(snapshot, to: url)
            session.transferFile(url, metadata: [WatchWire.kind: WatchWire.inventory, "requestID": requestID.uuidString])
            pendingRequest = nil
        } catch { report(error) }
    }

    private func publish() {
        do {
            let current = try store?.tracks() ?? []
            DispatchQueue.main.async {
                self.tracks = current
                self.status = "\(current.count) tracks saved on this Watch"
            }
        } catch { report(error) }
    }

    private func report(_ error: Error) { DispatchQueue.main.async { self.error = error.localizedDescription } }

    private func finishBackgroundIfDrained() {
        guard session.activationState == .activated, !session.hasContentPending else { return }
        // All receiving work is synchronous on this queue, so durable file commits have finished.
        DispatchQueue.main.async { self.backgroundDrained?() }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        queue.sync {
            if let error { report(error) }
            readRequest(session.receivedApplicationContext)
            flush()
            finishBackgroundIfDrained()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        queue.sync { readRequest(applicationContext); finishBackgroundIfDrained() }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        queue.sync { readRequest(message) }
    }
    func sessionReachabilityDidChange(_ session: WCSession) { queue.sync { flush() } }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        queue.sync {
            guard file.metadata?[WatchWire.kind] as? String == WatchWire.track,
                  let data = file.metadata?[WatchWire.payload] as? Data,
                  let delivery = try? JSONDecoder().decode(TrackDelivery.self, from: data), let store else { return }
            var failure: String?
            do {
                // CRITICAL: copy the WC temporary file and commit it before this callback returns.
                try store.receive(file.fileURL, delivery: delivery)
            } catch { failure = error.localizedDescription; report(error) }
            let receipt = WatchReceipt(attemptID: delivery.attemptID, trackID: delivery.track.id,
                                       watchID: store.watchID, revision: store.revision, error: failure)
            receipts.removeAll { $0.attemptID == receipt.attemptID }
            receipts.append(receipt)
            do {
                try WatchWire.write(receipts, to: receiptsURL)
                flush() // An acknowledgement is sent only after the durable transaction completed.
            } catch { report(error) } // Fresh inventory recovers a lost acknowledgement.
            publish()
            finishBackgroundIfDrained()
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        queue.sync {
            guard error == nil, let data = userInfoTransfer.userInfo[WatchWire.payload] as? Data,
                  let receipt = try? JSONDecoder().decode(WatchReceipt.self, from: data) else { return }
            receipts.removeAll { $0.attemptID == receipt.attemptID }
            do { try WatchWire.write(receipts, to: receiptsURL) } catch { report(error) }
            finishBackgroundIfDrained()
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        queue.sync {
            guard fileTransfer.file.metadata?[WatchWire.kind] as? String == WatchWire.inventory else { return }
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            if let error {
                if pendingRequest == nil, let text = fileTransfer.file.metadata?["requestID"] as? String { pendingRequest = UUID(uuidString: text) }
                report(error) // Retry on foreground/reachability/new request, not an unbounded error loop.
            } else { flush() }
            finishBackgroundIfDrained()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private var tasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    func applicationDidFinishLaunching() {
        WatchBridge.shared.backgroundDrained = { [weak self] in
            guard let self, WCSession.default.activationState == .activated, !WCSession.default.hasContentPending else { return }
            self.tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
            self.tasks.removeAll()
        }
    }
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask { tasks.append(connectivity) }
            else { task.setTaskCompletedWithSnapshot(false) }
        }
        WatchBridge.shared.checkBackgroundCompletion()
    }
}
