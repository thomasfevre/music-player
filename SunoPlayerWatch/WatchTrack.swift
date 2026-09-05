import Foundation

struct WatchTrack: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var fileName: String
    var receivedAt: Date

    var fileURL: URL {
        WatchLibrary.documentsDirectory.appendingPathComponent(fileName)
    }
}
