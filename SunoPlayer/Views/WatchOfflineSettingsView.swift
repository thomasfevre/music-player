import SwiftUI

struct WatchOfflineSettingsView: View {
    @ObservedObject private var sync = WatchOfflineManager.shared
    @EnvironmentObject private var library: MusicLibraryManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCancel = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Music without your iPhone", systemImage: "applewatch")
                        .font(.headline)
                    Text(sync.connection).foregroundStyle(.secondary)
                    if sync.checkingInventory { ProgressView("Checking saved track IDs…") }
                }
                Section("Transfer music") {
                    Button("Send whole library (\(library.tracks.count))") { sync.send(library.tracks) }
                        .disabled(library.tracks.isEmpty)
                    Button("Differential refresh") { sync.refresh(library.tracks) }
                        .disabled(library.tracks.isEmpty)
                    Button("Check Watch inventory") { sync.checkInventory() }
                    Text("Refresh asks the Watch what is actually saved, then sends missing IDs only. It never removes music. A whole-library send also skips tracks already saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Status") {
                    LabeledContent("Queued on iPhone", value: "\(count(.queued))")
                    LabeledContent("In system transfer", value: "\(count(.transferring))")
                    LabeledContent("Waiting for save receipt", value: "\(count(.awaitingReceipt))")
                    LabeledContent("Confirmed on Watch", value: "\(sync.ledger.persistedIDs.count)")
                    LabeledContent("Failed", value: "\(count(.failed))")
                    LabeledContent("Cancelled", value: "\(count(.cancelled))")
                    if let date = sync.ledger.inventoryDate {
                        LabeledContent("Last inventory") { Text(date, style: .relative) }
                    }
                    Text("At most 3 transfers await transport or a save receipt. watchOS controls timing; keep both devices near each other, preferably charging. A transport completion is not a saved track.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Queue controls") {
                    Button(sync.ledger.paused ? "Resume queue" : "Pause new transfers") {
                        if sync.ledger.paused { sync.resume() } else { sync.pause() }
                    }
                    Button("Retry failed tracks") { sync.retryFailures() }.disabled(count(.failed) == 0)
                    Button("Cancel pending transfers", role: .destructive) { confirmCancel = true }
                    Text("Pause leaves system transfers running. Cancel is best effort: music already delivered may still be saved. Neither action deletes Watch music.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let diagnostic = sync.diagnostic {
                    Section("Diagnostic") { Text(diagnostic).foregroundStyle(.red) }
                }
                if count(.failed) > 0 {
                    Section("Failed tracks") {
                        ForEach(sync.ledger.jobs.filter { $0.phase == .failed }) { job in
                            VStack(alignment: .leading) {
                                Text(job.title)
                                Text(job.error ?? "Unknown failure").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Watch Offline")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Cancel all pending transfers?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel pending transfers", role: .destructive) { sync.cancelAll() }
            }
        }
        .onAppear { sync.checkInventory() }
    }

    private func count(_ phase: TransferPhase) -> Int { sync.ledger.jobs.filter { $0.phase == phase }.count }
}
