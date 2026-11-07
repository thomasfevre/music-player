import Foundation
import Combine
import UIKit
import BackgroundTasks
import UserNotifications

/// Runs a folder import with real per-file progress, resumable state, background cover,
/// and a local notification at the end.
@MainActor
final class FolderImportCoordinator: ObservableObject {
    static let shared = FolderImportCoordinator()

    @Published private(set) var isRunning = false
    @Published private(set) var processed = 0
    @Published private(set) var total = 0
    @Published private(set) var status = ""
    @Published private(set) var summary: FolderImportSummary?

    private var library: MusicLibraryManager?
    private var playlists: PlaylistManager?
    private var task: Task<Void, Never>?
    private var cancelRequested = false
    private var folderURL: URL?
    private var scopedAccess = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func configure(library: MusicLibraryManager, playlists: PlaylistManager) {
        self.library = library
        self.playlists = playlists
    }

    /// `duplicates` and `ignored` come from the pre-import scan.
    func start(
        plan: FolderImportPlan,
        folderURL: URL,
        mergeIntoExisting: Bool,
        library: MusicLibraryManager,
        playlists: PlaylistManager,
        duplicates: Int,
        ignored: Int
    ) {
        if isRunning, task?.isCancelled == true { isRunning = false }
        guard !isRunning else { return }
        configure(library: library, playlists: playlists)
        self.folderURL = folderURL
        cancelRequested = false
        isRunning = true
        summary = nil
        processed = 0
        total = max(1, plan.totalTracks)
        status = "Preparing import…"

        let job = FolderImportJob(
            id: UUID(),
            bookmark: try? folderURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil),
            folderName: folderURL.lastPathComponent,
            playlists: plan.playlists.map {
                FolderImportJob.PlaylistSpec(
                    name: $0.name,
                    relativePaths: $0.files.map(\.relativePath),
                    collidesWithExisting: $0.collidesWithExistingPlaylist
                )
            },
            totalFiles: plan.totalTracks,
            strategy: mergeIntoExisting ? "merge" : "create",
            createdAt: Date()
        )
        try? FolderImportJobStore.save(job)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        beginBackgroundCover()

        task = Task { [weak self] in
            await self?.run(
                job: job,
                root: folderURL,
                duplicates: duplicates,
                ignored: ignored,
                mergeIntoExisting: mergeIntoExisting
            )
        }
    }

    /// Clears the previous run so reopening the sheet starts a new import.
    func clearSummary() {
        guard !isRunning else { return }
        summary = nil
        processed = 0
        total = 0
        status = ""
    }

    func cancel() {
        cancelRequested = true
        task?.cancel()
        status = "Cancelling…"
    }

    /// Called when the app starts or returns to the foreground.
    func resumeIfNeeded() {
        guard !isRunning, let job = FolderImportJobStore.load(), let library, let playlists else { return }
        guard let bookmark = job.bookmark else {
            FolderImportJobStore.clear()
            return
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            FolderImportJobStore.clear()
            return
        }
        folderURL = url
        scopedAccess = url.startAccessingSecurityScopedResource()
        isRunning = true
        cancelRequested = false
        processed = 0
        total = max(1, job.totalFiles)
        status = "Resuming import…"
        beginBackgroundCover()
        task = Task { [weak self] in
            await self?.run(
                job: job,
                root: url,
                duplicates: 0,
                ignored: 0,
                mergeIntoExisting: job.strategy == "merge"
            )
        }
    }

    private func run(
        job: FolderImportJob,
        root: URL,
        duplicates: Int,
        ignored: Int,
        mergeIntoExisting: Bool
    ) async {
        var result = FolderImportSummary()
        result.duplicates = duplicates
        result.ignored = ignored
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderImport-\(job.id.uuidString)", isDirectory: true)

        for spec in job.playlists {
            if Task.isCancelled || cancelRequested { break }
            var trackIDs: [UUID] = []
            var importedFiles = 0
            var playlistFailures = 0

            let playlistURLs = spec.relativePaths.map { root.appendingPathComponent($0) }
            status = "iCloud \(spec.name) — preparing \(playlistURLs.count) file(s)…"
            await ICloudFileMaterializer.prefetch(playlistURLs)

            for relativePath in spec.relativePaths {
                if Task.isCancelled || cancelRequested { break }
                let url = root.appendingPathComponent(relativePath)
                let fileName = url.lastPathComponent
                status = "iCloud \(fileName)…"
                do {
                    let local = try await ICloudFileMaterializer.materialize(url, in: tempDirectory, timeout: 60)
                    status = "Importing \(fileName)…"
                    let mapping = await library?.importTracksMapped(from: [local]) ?? [:]
                    if let track = mapping[local] {
                        trackIDs.append(track.id)
                        importedFiles += 1
                    } else {
                        playlistFailures += 1
                        result.failureReasons.append("\(fileName): import failed")
                    }
                    try? FileManager.default.removeItem(at: local)
                } catch {
                    playlistFailures += 1
                    result.failureReasons.append("\(fileName): \(error.localizedDescription)")
                }
                processed += 1
                status = "\(processed)/\(total) — \(fileName)"
            }

            if !trackIDs.isEmpty, let playlists {
                if spec.collidesWithExisting, mergeIntoExisting,
                   let existing = playlists.playlist(named: spec.name) {
                    playlists.addTracks(trackIDs, to: existing)
                    result.playlistsMerged += 1
                } else {
                    let name = spec.collidesWithExisting
                        ? playlists.availableName(for: spec.name)
                        : spec.name
                    _ = playlists.createPlaylist(name: name, trackIDs: trackIDs)
                    result.playlistsCreated += 1
                }
                result.tracksImported += importedFiles
            } else if importedFiles == 0 {
                result.emptyPlaylists.append(spec.name)
                result.failures += playlistFailures
            }
        }

        try? FileManager.default.removeItem(at: tempDirectory)
        if scopedAccess, let folderURL {
            folderURL.stopAccessingSecurityScopedResource()
            scopedAccess = false
        }
        FolderImportJobStore.clear()
        summary = result
        status = cancelRequested || Task.isCancelled
            ? "Import cancelled."
            : "\(result.playlistsCreated + result.playlistsMerged) playlist(s), \(result.tracksImported) track(s)."
        isRunning = false
        endBackgroundCover()
        postCompletionNotification(result)
        scheduleBackgroundProcessingIfNeeded()
    }

    private func postCompletionNotification(_ result: FolderImportSummary) {
        let content = UNMutableNotificationContent()
        content.title = "Playlist import finished"
        content.body = "\(result.playlistsCreated) created, \(result.playlistsMerged) merged, \(result.tracksImported) tracks."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "folder-import-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    private func beginBackgroundCover() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FolderImport") { [weak self] in
            Task { @MainActor in self?.endBackgroundCover() }
        }
    }

    private func endBackgroundCover() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func scheduleBackgroundProcessingIfNeeded() {
        guard FolderImportJobStore.load() != nil else { return }
        let request = BGProcessingTaskRequest(identifier: FolderImportBackground.identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    func handleBackgroundTask(_ task: BGProcessingTask) {
        scheduleBackgroundProcessingIfNeeded()
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.cancelRequested = true; self?.task?.cancel() }
        }
        resumeIfNeeded()
        Task { @MainActor in
            while isRunning {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            task.setTaskCompleted(success: true)
        }
    }
}
