import SwiftUI
import UniformTypeIdentifiers

/// Scans a folder, shows what will be created, then imports the audio and user playlists.
struct PlaylistFolderImportView: View {
    @EnvironmentObject private var library: MusicLibraryManager
    @EnvironmentObject private var playlists: PlaylistManager
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .pickFolder
    @State private var showFolderPicker = false
    @State private var plan: FolderImportPlan?
    @State private var progress = 0.0
    @State private var detail = ""
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?
    @State private var isCancelled = false
    @State private var scopedFolder: URL?

    private enum Phase: Equatable {
        case pickFolder, scanning, summary, importing, finished
    }

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .pickFolder:
                    Section {
                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Choose a folder", systemImage: "folder")
                        }
                    } footer: {
                        Text("Each folder containing audio becomes a playlist named after it. Nested folders become separate playlists. Files already in your library are skipped.")
                    }

                case .scanning:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning folder…")
                        }
                    }

                case .summary:
                    if let plan {
                        Section("Summary") {
                            LabeledContent("Playlists", value: "\(plan.playlists.count)")
                            LabeledContent("Tracks to import", value: "\(plan.totalTracks)")
                            if !plan.duplicateFileNames.isEmpty {
                                LabeledContent("Already imported", value: "\(plan.duplicateFileNames.count)")
                            }
                            if plan.ignoredFileCount > 0 {
                                LabeledContent("Non-audio files ignored", value: "\(plan.ignoredFileCount)")
                            }
                        }
                        if plan.isEmpty {
                            Section {
                                Text("No new audio files were found in this folder.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Section("Playlists to create") {
                                ForEach(plan.playlists) { playlist in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(playlist.name)
                                            Text("\(playlist.files.count) track\(playlist.files.count == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                case .importing:
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress)
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                case .finished:
                    Section {
                        Label("Import finished", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(detail)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Playlists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .importing ? "Cancel" : "Close") {
                        if phase == .importing { cancelImport() } else { dismiss() }
                    }
                }
                if phase == .summary, let plan, !plan.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { startImport(plan) }
                    }
                }
                if phase == .finished {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { scan(url) }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            importTask?.cancel()
            scopedFolder?.stopAccessingSecurityScopedResource()
            scopedFolder = nil
        }
    }

    private func scan(_ url: URL) {
        phase = .scanning
        errorMessage = nil
        let existingNames = Set(library.tracks.map(\.fileName))
        let existingPlaylists = Set(playlists.playlists.map(\.name))
        importTask = Task {
            if url.startAccessingSecurityScopedResource() {
                scopedFolder = url
            }
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try FolderScanner.scan(root: url)
                }.value
                if Task.isCancelled { return }
                let scanned = FolderImportPlanner.plan(
                    scannedFiles: files,
                    existingLibraryFileNames: existingNames,
                    existingPlaylistNames: existingPlaylists,
                    rootFolderName: url.lastPathComponent
                )
                await MainActor.run {
                    plan = scanned
                    phase = .summary
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .pickFolder
                }
            }
        }
    }

    private func startImport(_ plan: FolderImportPlan) {
        phase = .importing
        progress = 0
        isCancelled = false
        let total = Double(max(1, plan.playlists.count))
        importTask = Task {
            var completed = 0
            var created = 0
            var imported = 0
            for playlistPlan in plan.playlists {
                if Task.isCancelled || isCancelled { break }
                let urls = playlistPlan.files.map(\.url)
                let mapping = await library.importTracksMapped(from: urls)
                guard !mapping.isEmpty else {
                    completed += 1
                    await MainActor.run { progress = Double(completed) / total }
                    continue
                }
                let trackIDs = playlistPlan.files.compactMap { mapping[$0.url]?.id }
                if !trackIDs.isEmpty {
                    await MainActor.run {
                        _ = playlists.createPlaylist(name: playlistPlan.name, trackIDs: trackIDs)
                    }
                    created += 1
                    imported += trackIDs.count
                }
                completed += 1
                let current = completed
                await MainActor.run {
                    progress = Double(current) / total
                    detail = "\(created) playlist\(created == 1 ? "" : "s"), \(imported) track\(imported == 1 ? "" : "s")"
                }
            }
            if let scopedFolder {
                scopedFolder.stopAccessingSecurityScopedResource()
                self.scopedFolder = nil
            }
            await MainActor.run {
                if isCancelled || Task.isCancelled {
                    detail = "Import cancelled. \(created) playlist\(created == 1 ? "" : "s") created."
                } else {
                    detail = "\(created) playlist\(created == 1 ? "" : "s") created with \(imported) track\(imported == 1 ? "" : "s")."
                }
                phase = .finished
            }
        }
    }

    private func cancelImport() {
        isCancelled = true
        importTask?.cancel()
    }
}
