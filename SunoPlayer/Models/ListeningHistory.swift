import Foundation
import Combine

enum PlaybackSource: String, Codable, Equatable {
    case library
    case playlist
    case browser
    case queue
    case autoDJ
    case restored
}

enum ListeningEndReason: String, Codable, Equatable {
    case naturalCompletion
    case manualSkip
    case replacedBySelection
    case previous
    case deleted
    case failed
}

enum ListeningEventKind: String, Codable, Equatable {
    case playback
    case queuedNext
    case queuedLater
    case removedFromQueue
    case favoriteAdded
    case favoriteRemoved
    case positiveFeedback
    case negativeFeedback
}

struct ListeningEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ListeningEventKind
    let trackID: UUID
    let relatedTrackID: UUID?
    let date: Date
    let startedAt: Date?
    let listenedSeconds: TimeInterval?
    let duration: TimeInterval?
    let endReason: ListeningEndReason?
    let source: PlaybackSource?
    let wasReplay: Bool

    static func playback(
        id: UUID = UUID(),
        trackID: UUID,
        previousTrackID: UUID?,
        source: PlaybackSource,
        startedAt: Date,
        endedAt: Date,
        listenedSeconds: TimeInterval,
        duration: TimeInterval,
        endReason: ListeningEndReason,
        wasReplay: Bool
    ) -> ListeningEvent {
        ListeningEvent(
            id: id,
            kind: .playback,
            trackID: trackID,
            relatedTrackID: previousTrackID,
            date: endedAt,
            startedAt: startedAt,
            listenedSeconds: max(0, listenedSeconds),
            duration: max(0, duration),
            endReason: endReason,
            source: source,
            wasReplay: wasReplay
        )
    }

    static func feedback(
        id: UUID = UUID(),
        trackID: UUID,
        previousTrackID: UUID?,
        positive: Bool,
        at date: Date
    ) -> ListeningEvent {
        action(
            id: id,
            trackID: trackID,
            relatedTrackID: previousTrackID,
            kind: positive ? .positiveFeedback : .negativeFeedback,
            at: date
        )
    }

    static func action(
        id: UUID = UUID(),
        trackID: UUID,
        relatedTrackID: UUID? = nil,
        kind: ListeningEventKind,
        at date: Date
    ) -> ListeningEvent {
        precondition(kind != .playback, "Use playback(...) for playback events")
        return ListeningEvent(
            id: id,
            kind: kind,
            trackID: trackID,
            relatedTrackID: relatedTrackID,
            date: date,
            startedAt: nil,
            listenedSeconds: nil,
            duration: nil,
            endReason: nil,
            source: nil,
            wasReplay: false
        )
    }
}

struct TrackListeningSummary: Codable, Equatable {
    var playCount = 0
    var completionCount = 0
    var earlySkipCount = 0
    var lateSkipCount = 0
    var replayCount = 0
    var positiveFeedbackCount = 0
    var negativeFeedbackCount = 0
    var totalListenedSeconds: TimeInterval = 0
    var lastPlayedAt: Date?

    var completionRate: Double {
        guard playCount > 0 else { return 0 }
        return Double(completionCount) / Double(playCount)
    }

    var earlySkipRate: Double {
        guard playCount > 0 else { return 0 }
        return Double(earlySkipCount) / Double(playCount)
    }

    private enum CodingKeys: String, CodingKey {
        case playCount
        case completionCount
        case earlySkipCount
        case lateSkipCount
        case replayCount
        case positiveFeedbackCount
        case negativeFeedbackCount
        case totalListenedSeconds
        case lastPlayedAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playCount = try values.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        completionCount = try values.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        earlySkipCount = try values.decodeIfPresent(Int.self, forKey: .earlySkipCount) ?? 0
        lateSkipCount = try values.decodeIfPresent(Int.self, forKey: .lateSkipCount) ?? 0
        replayCount = try values.decodeIfPresent(Int.self, forKey: .replayCount) ?? 0
        positiveFeedbackCount = try values.decodeIfPresent(
            Int.self,
            forKey: .positiveFeedbackCount
        ) ?? 0
        negativeFeedbackCount = try values.decodeIfPresent(
            Int.self,
            forKey: .negativeFeedbackCount
        ) ?? 0
        totalListenedSeconds = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .totalListenedSeconds
        ) ?? 0
        lastPlayedAt = try values.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    }
}

struct TransitionListeningSummary: Codable, Equatable {
    let fromTrackID: UUID
    let toTrackID: UUID
    var observationCount = 0
    var completionCount = 0
    var earlySkipCount = 0
    var lateSkipCount = 0
    var positiveFeedbackCount = 0
    var negativeFeedbackCount = 0

    var successRate: Double {
        guard observationCount > 0 else { return 0 }
        return Double(completionCount + positiveFeedbackCount) / Double(observationCount)
    }

    private enum CodingKeys: String, CodingKey {
        case fromTrackID
        case toTrackID
        case observationCount
        case completionCount
        case earlySkipCount
        case lateSkipCount
        case positiveFeedbackCount
        case negativeFeedbackCount
    }

    init(fromTrackID: UUID, toTrackID: UUID) {
        self.fromTrackID = fromTrackID
        self.toTrackID = toTrackID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fromTrackID = try values.decode(UUID.self, forKey: .fromTrackID)
        toTrackID = try values.decode(UUID.self, forKey: .toTrackID)
        observationCount = try values.decodeIfPresent(Int.self, forKey: .observationCount) ?? 0
        completionCount = try values.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        earlySkipCount = try values.decodeIfPresent(Int.self, forKey: .earlySkipCount) ?? 0
        lateSkipCount = try values.decodeIfPresent(Int.self, forKey: .lateSkipCount) ?? 0
        positiveFeedbackCount = try values.decodeIfPresent(
            Int.self,
            forKey: .positiveFeedbackCount
        ) ?? 0
        negativeFeedbackCount = try values.decodeIfPresent(
            Int.self,
            forKey: .negativeFeedbackCount
        ) ?? 0
    }
}

enum ListeningThresholds {
    static func isEarlySkip(listenedSeconds: TimeInterval, duration: TimeInterval) -> Bool {
        guard duration > 0 else { return listenedSeconds < 20 }
        return listenedSeconds < min(20, duration * 0.5)
    }
}

struct ListeningHistory: Codable, Equatable {
    private(set) var summaries: [UUID: TrackListeningSummary]
    private(set) var transitions: [TransitionListeningSummary]
    private(set) var recentEvents: [ListeningEvent]
    let maxRecentEvents: Int

    init(maxRecentEvents: Int = 200) {
        self.summaries = [:]
        self.transitions = []
        self.recentEvents = []
        self.maxRecentEvents = max(1, maxRecentEvents)
    }

    mutating func record(_ event: ListeningEvent) {
        recentEvents.append(event)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }

        switch event.kind {
        case .playback:
            recordPlayback(event)
        case .positiveFeedback, .negativeFeedback:
            recordFeedback(event)
        case .queuedNext, .queuedLater, .removedFromQueue, .favoriteAdded, .favoriteRemoved:
            break
        }
    }

    func summary(for trackID: UUID) -> TrackListeningSummary {
        summaries[trackID] ?? TrackListeningSummary()
    }

    func transition(from fromTrackID: UUID, to toTrackID: UUID) -> TransitionListeningSummary? {
        transitions.first {
            $0.fromTrackID == fromTrackID && $0.toTrackID == toTrackID
        }
    }

    mutating func removeTrack(_ trackID: UUID) {
        summaries.removeValue(forKey: trackID)
        transitions.removeAll {
            $0.fromTrackID == trackID || $0.toTrackID == trackID
        }
        recentEvents.removeAll {
            $0.trackID == trackID || $0.relatedTrackID == trackID
        }
    }

    mutating func reset() {
        summaries.removeAll()
        transitions.removeAll()
        recentEvents.removeAll()
    }

    private mutating func recordPlayback(_ event: ListeningEvent) {
        guard let listenedSeconds = event.listenedSeconds,
              let duration = event.duration,
              let endReason = event.endReason else { return }

        let countsAsPlay = listenedSeconds >= 1 || endReason == .naturalCompletion
        if countsAsPlay {
            var summary = summaries[event.trackID] ?? TrackListeningSummary()
            summary.playCount += 1
            summary.totalListenedSeconds += listenedSeconds
            summary.lastPlayedAt = event.date
            if endReason == .naturalCompletion {
                summary.completionCount += 1
            }
            if endReason == .manualSkip,
               ListeningThresholds.isEarlySkip(
                   listenedSeconds: listenedSeconds,
                   duration: duration
               ) {
                summary.earlySkipCount += 1
            }
            if endReason == .manualSkip,
               !ListeningThresholds.isEarlySkip(
                   listenedSeconds: listenedSeconds,
                   duration: duration
               ) {
                summary.lateSkipCount += 1
            }
            if event.wasReplay {
                summary.replayCount += 1
            }
            summaries[event.trackID] = summary
        }

        guard countsAsPlay, let previousTrackID = event.relatedTrackID else { return }
        updateTransition(from: previousTrackID, to: event.trackID) { transition in
            transition.observationCount += 1
            if endReason == .naturalCompletion {
                transition.completionCount += 1
            }
            if endReason == .manualSkip,
               ListeningThresholds.isEarlySkip(
                   listenedSeconds: listenedSeconds,
                   duration: duration
               ) {
                transition.earlySkipCount += 1
            }
            if endReason == .manualSkip,
               !ListeningThresholds.isEarlySkip(
                   listenedSeconds: listenedSeconds,
                   duration: duration
               ) {
                transition.lateSkipCount += 1
            }
        }
    }

    private mutating func recordFeedback(_ event: ListeningEvent) {
        var summary = summaries[event.trackID] ?? TrackListeningSummary()
        if event.kind == .positiveFeedback {
            summary.positiveFeedbackCount += 1
        } else {
            summary.negativeFeedbackCount += 1
        }
        summaries[event.trackID] = summary

        guard let previousTrackID = event.relatedTrackID else { return }
        updateTransition(from: previousTrackID, to: event.trackID) { transition in
            if event.kind == .positiveFeedback {
                transition.positiveFeedbackCount += 1
            } else {
                transition.negativeFeedbackCount += 1
            }
        }
    }

    private mutating func updateTransition(
        from fromTrackID: UUID,
        to toTrackID: UUID,
        update: (inout TransitionListeningSummary) -> Void
    ) {
        let index = transitions.firstIndex {
            $0.fromTrackID == fromTrackID && $0.toTrackID == toTrackID
        }
        if let index {
            update(&transitions[index])
        } else {
            var transition = TransitionListeningSummary(
                fromTrackID: fromTrackID,
                toTrackID: toTrackID
            )
            update(&transition)
            transitions.append(transition)
        }
    }
}

@MainActor
final class ListeningHistoryStore: ObservableObject {
    @Published private(set) var history: ListeningHistory
    @Published private(set) var lastError: String?

    private let fileURL: URL

    init(
        fileURL: URL? = nil,
        maxRecentEvents: Int = 200
    ) {
        let resolvedFileURL = fileURL ?? ListeningHistoryStore.defaultFileURL
        self.fileURL = resolvedFileURL
        if FileManager.default.fileExists(atPath: resolvedFileURL.path) {
            do {
                let data = try Data(contentsOf: resolvedFileURL)
                self.history = try JSONDecoder().decode(ListeningHistory.self, from: data)
                self.lastError = nil
            } catch {
                self.history = ListeningHistory(maxRecentEvents: maxRecentEvents)
                self.lastError = "Listening history could not be read: \(error.localizedDescription)"
            }
        } else {
            self.history = ListeningHistory(maxRecentEvents: maxRecentEvents)
            self.lastError = nil
        }
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("listening-history.json")
    }

    @discardableResult
    func record(_ event: ListeningEvent) -> Bool {
        update { $0.record(event) }
    }

    @discardableResult
    func record(_ events: [ListeningEvent]) -> Bool {
        guard !events.isEmpty else { return true }
        return update { history in
            for event in events {
                history.record(event)
            }
        }
    }

    func summary(for trackID: UUID) -> TrackListeningSummary {
        history.summary(for: trackID)
    }

    func transition(from fromTrackID: UUID, to toTrackID: UUID) -> TransitionListeningSummary? {
        history.transition(from: fromTrackID, to: toTrackID)
    }

    @discardableResult
    func removeTrack(_ trackID: UUID) -> Bool {
        update { $0.removeTrack(trackID) }
    }

    @discardableResult
    func reset() -> Bool {
        update { $0.reset() }
    }

    func clearError() {
        lastError = nil
    }

    private func update(_ mutation: (inout ListeningHistory) -> Void) -> Bool {
        var updated = history
        mutation(&updated)
        do {
            let data = try JSONEncoder().encode(updated)
            try data.write(to: fileURL, options: .atomic)
            history = updated
            lastError = nil
            return true
        } catch {
            lastError = "Listening history could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
