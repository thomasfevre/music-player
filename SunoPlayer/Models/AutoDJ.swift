import Foundation

struct AutoDJContext: Equatable {
    let favoriteIDs: Set<UUID>
    let playlistGroups: [Set<UUID>]
    let recentTrackIDs: Set<UUID>
    let excludedTrackIDs: Set<UUID>
    let preferredTracks: [Track]

    init(
        favoriteIDs: Set<UUID>,
        playlistGroups: [[UUID]],
        recentTrackIDs: Set<UUID>,
        excludedTrackIDs: Set<UUID>,
        preferredTracks: [Track] = []
    ) {
        self.favoriteIDs = favoriteIDs
        self.playlistGroups = playlistGroups.map(Set.init)
        self.recentTrackIDs = recentTrackIDs
        self.excludedTrackIDs = excludedTrackIDs
        self.preferredTracks = preferredTracks
    }
}

enum AutoDJReason: String, Codable, Equatable, Hashable {
    case successfulTransition
    case positiveFeedback
    case oftenCompleted
    case samePlaylist
    case sameAlbum
    case favorite
    case familiarArtist
    case sameGenre
    case notPlayedRecently
    case libraryPick

    var text: String {
        switch self {
        case .successfulTransition: return "Worked after this track"
        case .positiveFeedback: return "You asked for more like this"
        case .oftenCompleted: return "Often completed"
        case .samePlaylist: return "Same playlist"
        case .sameAlbum: return "Same album"
        case .favorite: return "Favorite"
        case .familiarArtist: return "Familiar artist"
        case .sameGenre: return "Same genre"
        case .notPlayedRecently: return "Not played recently"
        case .libraryPick: return "From your downloaded music"
        }
    }

    fileprivate var priority: Int {
        switch self {
        case .successfulTransition: return 80
        case .positiveFeedback: return 70
        case .oftenCompleted: return 60
        case .samePlaylist: return 50
        case .sameAlbum: return 45
        case .favorite: return 40
        case .familiarArtist: return 30
        case .sameGenre: return 20
        case .notPlayedRecently: return 10
        case .libraryPick: return 0
        }
    }
}

struct AutoDJRecommendation: Equatable {
    let track: Track
    let score: Double
    let reasons: [AutoDJReason]

    var reasonText: String {
        reasons.prefix(2).map(\.text).joined(separator: " · ")
    }
}

struct AutoDJSession {
    let library: [Track]
    var favoriteIDs: Set<UUID>
    var playlistGroups: [[UUID]]
    var excludedTrackIDs: Set<UUID> = []
    var playedTrackIDs: Set<UUID> = []
    var preferredTracks: [Track] = []
    var currentRecommendation: AutoDJRecommendation?
    var recommendationsByTrackID: [UUID: AutoDJRecommendation] = [:]
}

enum AutoDJ {
    static func recommend(
        after currentTrack: Track,
        candidates: [Track],
        context: AutoDJContext,
        history: ListeningHistory,
        limit: Int,
        now: Date = Date()
    ) -> [AutoDJRecommendation] {
        guard limit > 0 else { return [] }

        return candidates
            .filter {
                $0.id != currentTrack.id &&
                !context.excludedTrackIDs.contains($0.id)
            }
            .map {
                score(
                    $0,
                    after: currentTrack,
                    context: context,
                    history: history,
                    now: now
                )
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.track.id.uuidString < $1.track.id.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(
        _ candidate: Track,
        after currentTrack: Track,
        context: AutoDJContext,
        history: ListeningHistory,
        now: Date
    ) -> AutoDJRecommendation {
        let summary = history.summary(for: candidate.id)
        let transition = history.transition(from: currentTrack.id, to: candidate.id)
        var score = 0.0
        var reasons = Set<AutoDJReason>()

        if let transition {
            score += Double(transition.completionCount) * 20
            score += Double(transition.positiveFeedbackCount) * 22
            score -= Double(transition.earlySkipCount) * 28
            score -= Double(transition.negativeFeedbackCount) * 35
            if transition.completionCount + transition.positiveFeedbackCount > 0,
               transition.earlySkipCount + transition.negativeFeedbackCount == 0 {
                reasons.insert(.successfulTransition)
            }
        }

        score += summary.completionRate * 24
        score -= summary.earlySkipRate * 36
        score += Double(summary.replayCount) * 4
        score += Double(summary.positiveFeedbackCount) * 12
        score -= Double(summary.negativeFeedbackCount) * 24

        if summary.playCount > 0, summary.completionRate >= 0.6 {
            reasons.insert(.oftenCompleted)
        }
        if summary.positiveFeedbackCount > 0 {
            reasons.insert(.positiveFeedback)
        }

        if context.playlistGroups.contains(where: {
            $0.contains(currentTrack.id) && $0.contains(candidate.id)
        }) {
            score += 20
            reasons.insert(.samePlaylist)
        }

        if context.favoriteIDs.contains(candidate.id) {
            score += 18
            reasons.insert(.favorite)
        }

        if sameKnownValue(currentTrack.album, candidate.album) {
            score += 13
            reasons.insert(.sameAlbum)
        }

        if sameKnownValue(currentTrack.artist, candidate.artist) {
            score += 7
            reasons.insert(.familiarArtist)
        }

        if sameKnownValue(currentTrack.genre, candidate.genre) {
            score += 11
            reasons.insert(.sameGenre)
        }

        let preferenceBoost = context.preferredTracks.reduce(0.0) { partial, preferred in
            var boost = 0.0
            if sameKnownValue(preferred.album, candidate.album) { boost += 20 }
            if sameKnownValue(preferred.artist, candidate.artist) { boost += 15 }
            if sameKnownValue(preferred.genre, candidate.genre) { boost += 10 }
            return max(partial, boost)
        }
        if preferenceBoost > 0 {
            score += preferenceBoost
            reasons.insert(.positiveFeedback)
        }

        let recentlyPlayedByDate = summary.lastPlayedAt.map {
            now.timeIntervalSince($0) < 7 * 86_400
        } ?? false
        if context.recentTrackIDs.contains(candidate.id) || recentlyPlayedByDate {
            score -= 50
        } else {
            score += 10
            reasons.insert(.notPlayedRecently)
        }

        if reasons.isEmpty {
            reasons.insert(.libraryPick)
        }

        let orderedReasons = reasons.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return $0.rawValue < $1.rawValue
        }
        return AutoDJRecommendation(
            track: candidate,
            score: score,
            reasons: orderedReasons
        )
    }

    private static func sameKnownValue(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
