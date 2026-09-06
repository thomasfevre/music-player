import XCTest
@testable import SunoPlayer

final class WatchOfflineTests: XCTestCase {
    private func inventory(_ ids: Set<UUID>, watch: UUID) -> WatchInventory {
        WatchInventory(version: 1, requestID: UUID(), watchID: watch, revision: 1, trackIDs: ids, generatedAt: Date())
    }
    private func job(_ id: UUID = UUID(), phase: TransferPhase = .queued, attempt: UUID? = nil) -> WatchTransferJob {
        var job = WatchTransferJob(id: id, title: "Test", artist: nil, sourceFileName: "test.mp3")
        job.phase = phase
        job.attemptID = attempt
        return job
    }

    func testDifferentialUsesActualIDsRatherThanPriorCompletion() {
        let saved = UUID(), vanished = UUID(), watch = UUID()
        var ledger = WatchTransferLedger()
        ledger.jobs = [job(saved), job(vanished, phase: .persisted)]
        ledger.persistedIDs = [vanished]
        ledger.reconcile(inventory([saved], watch: watch), outstanding: [])
        XCTAssertEqual(ledger.jobs.map(\.phase), [.persisted, .queued])
        XCTAssertEqual(ledger.persistedIDs, [saved])
    }

    func testRestartRetainsOutstandingTransferAndRecoversLostCallback() {
        let outstanding = UUID(), lost = UUID(), awaiting = UUID()
        var ledger = WatchTransferLedger()
        ledger.jobs = [job(phase: .transferring, attempt: outstanding), job(phase: .transferring, attempt: lost), job(phase: .awaitingReceipt, attempt: awaiting)]
        ledger.reconcile(inventory([], watch: UUID()), outstanding: [outstanding])
        XCTAssertEqual(ledger.jobs.map(\.phase), [.transferring, .queued, .queued])
    }

    func testReceiptRequiresMatchingAttemptAndWatch() {
        let watch = UUID(), attempt = UUID(), id = UUID()
        var ledger = WatchTransferLedger()
        ledger.watchID = watch
        ledger.jobs = [job(id, phase: .awaitingReceipt, attempt: attempt)]
        ledger.apply(WatchReceipt(attemptID: UUID(), trackID: id, watchID: watch, revision: 1, error: nil))
        ledger.apply(WatchReceipt(attemptID: attempt, trackID: id, watchID: UUID(), revision: 1, error: nil))
        XCTAssertEqual(ledger.jobs[0].phase, .awaitingReceipt)
        ledger.apply(WatchReceipt(attemptID: attempt, trackID: id, watchID: watch, revision: 2, error: nil))
        XCTAssertEqual(ledger.jobs[0].phase, .persisted)
        XCTAssertEqual(ledger.revision, 2)
        XCTAssertEqual(ledger.jobs[0].attempts, 0)
    }

    func testBootstrapReceiptBindsWatchWhenInventoryHasNotArrived() {
        let watch = UUID(), attempt = UUID(), id = UUID()
        var ledger = WatchTransferLedger()
        ledger.jobs = [job(id, phase: .awaitingReceipt, attempt: attempt)]

        ledger.apply(WatchReceipt(attemptID: attempt, trackID: id, watchID: watch, revision: 1, error: nil))

        XCTAssertEqual(ledger.watchID, watch)
        XCTAssertEqual(ledger.jobs[0].phase, .persisted)
        XCTAssertTrue(ledger.persistedIDs.contains(id))
    }

    func testCancelledJobsDoNotResumeButLateReceiptIsTruthful() {
        let id = UUID(), watch = UUID(), attempt = UUID()
        var ledger = WatchTransferLedger()
        ledger.jobs = [job(id, phase: .cancelled, attempt: attempt)]
        ledger.reconcile(inventory([], watch: watch), outstanding: [])
        ledger.apply(WatchReceipt(attemptID: attempt, trackID: id, watchID: watch, revision: 1, error: nil))
        XCTAssertEqual(ledger.jobs[0].phase, .cancelled)
        XCTAssertTrue(ledger.persistedIDs.contains(id))
    }

    func testLostReceiptsHaveBoundedAutomaticAttempts() {
        var ledger = WatchTransferLedger()
        var exhausted = job(phase: .awaitingReceipt)
        exhausted.attempts = 3
        ledger.jobs = [exhausted]
        ledger.reconcile(inventory([], watch: UUID()), outstanding: [])
        XCTAssertEqual(ledger.jobs[0].phase, .failed)
        XCTAssertNotNil(ledger.jobs[0].error)
    }

    func testAwaitingReceiptsConsumeTransferWindow() {
        var ledger = WatchTransferLedger()
        ledger.jobs = [job(phase: .transferring), job(phase: .awaitingReceipt), job(phase: .awaitingReceipt)]
        XCTAssertEqual(WatchTransferLedger.window - ledger.busyCount, 0)
    }

    func testNineHundredTracksNeverCreateMoreThanThreeSystemSubmissions() {
        var ledger = WatchTransferLedger()
        ledger.jobs = (0..<900).map { _ in job() }
        XCTAssertEqual(ledger.availableSlots(systemTransfers: 0), 3)
        for index in 0..<3 { ledger.jobs[index].phase = .transferring }
        XCTAssertEqual(ledger.availableSlots(systemTransfers: 3), 0)
        ledger.jobs[0].phase = .awaitingReceipt
        XCTAssertEqual(ledger.availableSlots(systemTransfers: 2), 0)
        ledger.jobs[0].phase = .persisted
        XCTAssertEqual(ledger.availableSlots(systemTransfers: 2), 1)
        XCTAssertEqual(ledger.availableSlots(systemTransfers: 20), 0)
    }

    func testTransportCompletionIsNotPersistenceAndCannotOverwriteEarlyReceipt() {
        let watch = UUID(), attempt = UUID(), id = UUID()
        var ledger = WatchTransferLedger()
        ledger.watchID = watch
        ledger.jobs = [job(id, phase: .transferring, attempt: attempt)]
        ledger.transportFinished(attemptID: attempt, error: nil)
        XCTAssertEqual(ledger.jobs[0].phase, .awaitingReceipt)
        XCTAssertTrue(ledger.persistedIDs.isEmpty)
        ledger.apply(WatchReceipt(attemptID: attempt, trackID: id, watchID: watch, revision: 1, error: nil))
        ledger.transportFinished(attemptID: attempt, error: "Late transport error")
        XCTAssertEqual(ledger.jobs[0].phase, .persisted)
        XCTAssertNil(ledger.jobs[0].error)
    }

    func testLedgerRoundTripKeepsResumeAndCancellationState() throws {
        var ledger = WatchTransferLedger()
        ledger.jobs = [job(phase: .transferring, attempt: UUID()), job(phase: .cancelled)]
        ledger.paused = true
        let restored = try JSONDecoder().decode(WatchTransferLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.jobs.map(\.phase), [.transferring, .cancelled])
        XCTAssertEqual(restored.jobs[0].attemptID, ledger.jobs[0].attemptID)
        XCTAssertTrue(restored.paused)
    }

    func testStoreOwnsTemporaryFileAndSurvivesRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OfflineTrackStore(root: root)
        let source = root.appendingPathComponent("wc-temporary.mp3")
        try Data("synthetic audio bytes".utf8).write(to: source)
        let track = OfflineTrack(id: UUID(), title: "Offline", artist: nil, fileExtension: "mp3", byteCount: 21, sha256: try WatchWire.checksum(source))
        let delivery = TrackDelivery(version: 1, attemptID: UUID(), targetWatch: store.watchID, track: track)
        try store.receive(source, delivery: delivery)
        try FileManager.default.removeItem(at: source)
        let restored = try OfflineTrackStore(root: root)
        XCTAssertEqual(restored.watchID, store.watchID)
        XCTAssertEqual(try restored.tracks(), [track])
        XCTAssertEqual(try Data(contentsOf: restored.audioURL(track)), Data("synthetic audio bytes".utf8))
    }

    func testStoreRejectsTruncatedAndWrongWatchFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OfflineTrackStore(root: root)
        let source = root.appendingPathComponent("temporary.mp3")
        try Data([1, 2, 3]).write(to: source)
        let track = OfflineTrack(id: UUID(), title: "Invalid", artist: nil, fileExtension: "mp3", byteCount: 4, sha256: "bad")
        XCTAssertThrowsError(try store.receive(source, delivery: TrackDelivery(version: 1, attemptID: UUID(), targetWatch: store.watchID, track: track)))
        XCTAssertThrowsError(try store.receive(source, delivery: TrackDelivery(version: 1, attemptID: UUID(), targetWatch: UUID(), track: track)))
        XCTAssertEqual(try store.tracks().count, 0)
    }

    func testDuplicateDeliveriesAreIdempotentAndMissingAudioNotInventoried() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OfflineTrackStore(root: root)
        let source = root.appendingPathComponent("temporary.mp3")
        try Data([1, 2, 3]).write(to: source)
        let track = OfflineTrack(id: UUID(), title: "Test", artist: nil, fileExtension: "mp3", byteCount: 3, sha256: try WatchWire.checksum(source))
        for _ in 0..<2 { try store.receive(source, delivery: TrackDelivery(version: 1, attemptID: UUID(), targetWatch: store.watchID, track: track)) }
        XCTAssertEqual(try store.tracks().count, 1)
        XCTAssertEqual(store.revision, 1)
        try FileManager.default.removeItem(at: store.audioURL(track))
        XCTAssertTrue(try store.tracks().isEmpty)
    }
}
