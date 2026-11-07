import SwiftUI
import UniformTypeIdentifiers

/// Scans a folder, shows what will be created, then hands the work to the durable importer.
struct PlaylistFolderImportView: View {
    @EnvironmentObject private var library: MusicLibraryManager
    @EnvironmentObject private var playlists: PlaylistManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = FolderImportCoordinator.shared

    @State private var phase: Phase = .pickFolder
    @State private var showFolderPicker = false
    @State private var plan: FolderImportPlan?
    @State private var folderURL: URL?
    @State private var errorMessage: String?
    @State private var collisionStrategy: CollisionStrategy = .merge
    @State private var scopedFolder: URL?
    @State private var scanTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case pickFolder, scanning, summary, importing, finished
    }

    private enum CollisionStrategy: String, CaseIterable, Identifiable {
        case merge, createNew
        var id: String { rawValue }
        var title: String {
            switch self {
            case .merge: return "Merge into existing"
            case .createNew: return "Create new playlists"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .pickFolder:
                    Section {
                        Button { showFolderPicker = true } label: {
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
                    summarySections
                case .importing:
                    importingSections
                case .finished:
                    finishedSections
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Import Playlists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .importing ? "Cancel" : "Close") {
                        if phase == .importing { importer.cancel() } else { dismiss() }
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
        .onAppear {
            if importer.isRunning {
                phase = .importing
            } else {
                importer.clearSummary()
                phase = .pickFolder
            }
        }
        .onChange(of: importer.summary) { _, newValue in
            if newValue != nil { phase = .finished }
        }
        .onDisappear {
            scanTask?.cancel()
            scopedFolder?.stopAccessingSecurityScopedResource()
            scopedFolder = nil
        }
    }

    @ViewBuilder
    private var summarySections: some View {
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
            if !plan.collidingPlaylistNames.isEmpty {
                Section {
                    Picker("On name collision", selection: $collisionStrategy) {
                        ForEach(CollisionStrategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    ForEach(plan.collidingPlaylistNames, id: \.self) { name in
                        Text(name).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Existing playlists")
                } footer: {
                    Text(collisionStrategy == .merge
                         ? "Tracks are added to the existing playlist."
                         : "A new playlist is created next to the existing one.")
                }
            }
            if plan.isEmpty {
                Section {
                    Text("No new audio files were found in this folder.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Playlists") {
                    ForEach(plan.playlists) { playlist in
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                            Text("\(playlist.files.count) track\(playlist.files.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var displayedTotal: Int { plan?.totalTracks ?? importer.total }

    private var progress: Double {
        guard displayedTotal > 0 else { return 0 }
        return min(1, Double(importer.processed) / Double(displayedTotal))
    }

    @ViewBuilder
    private var importingSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                Text("\(importer.processed) / \(displayedTotal) files")
                    .font(.caption)
                Text(importer.status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var finishedSections: some View {
        if let summary = importer.summary {
            Section {
                Label("Import finished", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                LabeledContent("Playlists created", value: "\(summary.playlistsCreated)")
                LabeledContent("Playlists merged", value: "\(summary.playlistsMerged)")
                LabeledContent("Tracks imported", value: "\(summary.tracksImported)")
                LabeledContent("Duplicates skipped", value: "\(summary.duplicates)")
                LabeledContent("Non-audio ignored", value: "\(summary.ignored)")
                if summary.failures > 0 {
                    LabeledContent("Download/import failures", value: "\(summary.failures)")
                }
            }
            if !summary.emptyPlaylists.isEmpty {
                Section("Not created") {
                    ForEach(summary.emptyPlaylists, id: \.self) { name in
                        Text("\(name) — no importable tracks.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !summary.failureReasons.isEmpty {
                Section("Details") {
                    ForEach(summary.failureReasons.prefix(20), id: \.self) { reason in
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func scan(_ url: URL) {
        phase = .scanning
        errorMessage = nil
        folderURL = url
        let existingNames = Set(library.tracks.map(\.fileName))
        let existingPlaylists = Set(playlists.playlists.map(\.name))
        scanTask = Task {
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
        guard let folderURL else { return }
        importer.start(
            plan: plan,
            folderURL: folderURL,
            mergeIntoExisting: collisionStrategy == .merge,
            library: library,
            playlists: playlists,
            duplicates: plan.duplicateFileNames.count,
            ignored: plan.ignoredFileCount
        )
        phase = .importing
    }
}
