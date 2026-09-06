import Foundation
import CryptoKit

/// IDs are immutable library identities, not file names or transport completion counts.
struct OfflineTrack: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let artist: String?
    let fileExtension: String
    let byteCount: Int64
    let sha256: String
}

struct TrackDelivery: Codable {
    let version: Int
    let attemptID: UUID
    let targetWatch: UUID?
    let track: OfflineTrack
}

struct WatchInventory: Codable {
    let version: Int
    let requestID: UUID
    let watchID: UUID
    let revision: Int
    let trackIDs: Set<UUID>
    let generatedAt: Date
}

struct WatchReceipt: Codable {
    let attemptID: UUID
    let trackID: UUID
    let watchID: UUID
    let revision: Int
    let error: String?
}

enum WatchWire {
    static let version = 1
    static let kind = "suno.kind"
    static let track = "track.v1"
    static let inventory = "inventory.v1"
    static let request = "inventory-request.v1"
    static let receipt = "receipt.v1"
    static let payload = "payload"

    static func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

enum TransferPhase: String, Codable {
    case queued, transferring, awaitingReceipt, persisted, failed, cancelled
}

struct WatchTransferJob: Codable, Identifiable {
    let id: UUID
    let title: String
    let artist: String?
    let sourceFileName: String
    var phase: TransferPhase = .queued
    var attemptID: UUID?
    var attempts = 0
    var updatedAt = Date()
    var error: String?
}

struct WatchTransferLedger: Codable {
    var jobs: [WatchTransferJob] = []
    var watchID: UUID?
    var persistedIDs: Set<UUID> = []
    var inventoryDate: Date?
    var revision = 0
    var paused = false

    static let window = 3
    static let maxAttempts = 3

    var busyCount: Int {
        jobs.filter { $0.phase == .transferring || $0.phase == .awaitingReceipt }.count
    }

    func availableSlots(systemTransfers: Int) -> Int {
        max(0, Self.window - max(busyCount, systemTransfers))
    }

    mutating func transportFinished(attemptID: UUID, error: String?) {
        guard let index = jobs.firstIndex(where: { $0.attemptID == attemptID }),
              jobs[index].phase == .transferring else { return }
        jobs[index].phase = error == nil ? .awaitingReceipt : .failed
        jobs[index].error = error
        jobs[index].updatedAt = Date()
    }

    /// Fresh inventory wins over remembered receipts. No outstanding transfer is re-submitted.
    mutating func reconcile(_ inventory: WatchInventory, outstanding: Set<UUID>) {
        watchID = inventory.watchID
        revision = inventory.revision
        persistedIDs = inventory.trackIDs
        inventoryDate = inventory.generatedAt
        for index in jobs.indices {
            guard jobs[index].phase != .cancelled else { continue }
            if persistedIDs.contains(jobs[index].id) {
                jobs[index].phase = .persisted
                jobs[index].attempts = 0
                jobs[index].error = nil
            } else if let attempt = jobs[index].attemptID, outstanding.contains(attempt) {
                jobs[index].phase = .transferring
            } else if jobs[index].phase != .failed {
                jobs[index].phase = jobs[index].attempts < Self.maxAttempts ? .queued : .failed
                if jobs[index].phase == .failed { jobs[index].error = "Not present on Watch after 3 attempts. Retry manually." }
            }
        }
    }

    mutating func apply(_ receipt: WatchReceipt) {
        if let watchID, receipt.watchID != watchID { return }
        if watchID == nil { self.watchID = receipt.watchID }
        guard let index = jobs.firstIndex(where: { $0.id == receipt.trackID && $0.attemptID == receipt.attemptID }) else { return }
        if receipt.error == nil { persistedIDs.insert(receipt.trackID) }
        revision = max(revision, receipt.revision)
        guard jobs[index].phase != .cancelled else { return }
        jobs[index].phase = receipt.error == nil ? .persisted : .failed
        if receipt.error == nil { jobs[index].attempts = 0 }
        jobs[index].error = receipt.error
        jobs[index].updatedAt = Date()
    }
}
