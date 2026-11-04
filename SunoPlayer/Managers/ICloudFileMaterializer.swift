import Foundation

/// Makes a picked file locally available before it is copied into the app.
///
/// Files living only in iCloud are placeholders: `copyItem` can produce an empty or missing
/// file. This waits for the explicit download, coordinates the read with other processes,
/// and hands back a stable temporary copy.
enum ICloudFileMaterializer {
    enum MaterializeError: LocalizedError {
        case downloadTimedOut
        case downloadFailed(String)
        case notReadable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .downloadTimedOut: return "The iCloud download timed out."
            case .downloadFailed(let reason): return "The iCloud download failed: \(reason)"
            case .notReadable: return "The file could not be read."
            case .cancelled: return "Import cancelled."
            }
        }
    }

    /// Returns a local copy of `url` inside `directory`, keeping the original file name.
    static func materialize(
        _ url: URL,
        in directory: URL,
        timeout: TimeInterval = 300
    ) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try await ensureDownloaded(url, timeout: timeout)

        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: destination)
        try coordinateCopy(from: url, to: destination)
        guard fm.fileExists(atPath: destination.path) else { throw MaterializeError.notReadable }
        return destination
    }

    static func shouldDownload(
        isUbiquitous: Bool,
        status: URLUbiquitousItemDownloadingStatus?
    ) -> Bool {
        guard isUbiquitous else { return false }
        return status != .current
    }

    static func needsDownload(_ values: URLResourceValues) -> Bool {
        shouldDownload(
            isUbiquitous: values.isUbiquitousItem == true,
            status: values.ubiquitousItemDownloadingStatus
        )
    }

    static func ensureDownloaded(_ url: URL, timeout: TimeInterval) async throws {
        let fm = FileManager.default
        var values = try? url.resourceValues(forKeys: downloadKeys)
        guard let initial = values, needsDownload(initial) else { return }

        try fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: String?

        while Date() < deadline {
            if Task.isCancelled { throw MaterializeError.cancelled }
            try await Task.sleep(nanoseconds: 250_000_000)
            guard let current = try? url.resourceValues(forKeys: downloadKeys) else { continue }
            switch current.ubiquitousItemDownloadingStatus {
            case .current?:
                values = current
                return
            case .notDownloaded?:
                continue
            default:
                if let error = current.ubiquitousItemDownloadingError {
                    lastError = error.localizedDescription
                }
            }
        }
        throw lastError.map(MaterializeError.downloadFailed) ?? MaterializeError.downloadTimedOut
    }

    private static let downloadKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemDownloadingErrorKey
    ]

    /// Coordinates the read so iCloud (or another process) cannot change the file mid-copy.
    private static func coordinateCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.copyItem(at: coordinatedURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
}
