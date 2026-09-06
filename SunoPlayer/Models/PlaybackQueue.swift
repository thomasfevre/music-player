import Foundation

// MARK: - PlaybackQueue
/// Pure, testable playback-queue navigation. Holds no AVFoundation state.
/// The owning `AudioPlayerManager` drives the actual player from the indices this returns.
struct PlaybackQueue {

    /// Result of a `previous()` request.
    enum PreviousAction: Equatable {
        case restart            // restart the current track from 0
        case play(index: Int)   // load the track at this index
        case none               // queue empty — do nothing
    }

    private(set) var baseOrder: [Track] = []
    private(set) var shuffledOrder: [Track] = []
    private(set) var shuffleEnabled: Bool = false
    var repeatMode: RepeatMode = .off
    private(set) var currentIndex: Int = 0

    var activeOrder: [Track] { shuffleEnabled ? shuffledOrder : baseOrder }
    var isEmpty: Bool { activeOrder.isEmpty }

    var currentTrack: Track? { track(at: currentIndex) }
    var upcomingTracks: [Track] {
        guard currentIndex + 1 < activeOrder.count else { return [] }
        return Array(activeOrder[(currentIndex + 1)...])
    }

    func track(at index: Int) -> Track? {
        activeOrder.indices.contains(index) ? activeOrder[index] : nil
    }

    /// Replace the queue and select `track` as current.
    /// `shuffleSeed` lets tests inject a deterministic ordering instead of `shuffled()`.
    mutating func setQueue(_ tracks: [Track], startAt track: Track, shuffleSeed: (([Track]) -> [Track])? = nil) {
        baseOrder = tracks
        if shuffleEnabled {
            let shuffled = shuffleSeed?(tracks) ?? tracks.shuffled()
            shuffledOrder = Self.bringToFront(track, in: shuffled)
        }
        currentIndex = activeOrder.firstIndex(of: track) ?? 0
    }

    /// Advance to the next track. Returns the index to play, or `nil` if playback
    /// should stop (end of queue with repeat off). For `.one`, returns the current index.
    mutating func next() -> Int? {
        guard !isEmpty else { return nil }
        if repeatMode == .one { return currentIndex }
        let candidate = currentIndex + 1
        if candidate < activeOrder.count {
            currentIndex = candidate
        } else if repeatMode == .all {
            currentIndex = 0
        } else {
            return nil
        }
        return currentIndex
    }

    /// Go to the previous track. Restarts the current track if more than 3s in,
    /// or if at the start of the queue with repeat off.
    mutating func previous(currentTime: TimeInterval) -> PreviousAction {
        guard !isEmpty else { return .none }
        if currentTime > 3 { return .restart }
        let candidate = currentIndex - 1
        if candidate >= 0 {
            currentIndex = candidate
            return .play(index: currentIndex)
        }
        if repeatMode == .all {
            currentIndex = activeOrder.count - 1
            return .play(index: currentIndex)
        }
        return .restart
    }

    /// Enable/disable shuffle, keeping the current track selected.
    /// When enabling, the current track is moved to the front of the shuffled order.
    /// When disabling, the index is resynced to the current track's position in the base order.
    mutating func setShuffle(_ enabled: Bool, shuffleSeed: (([Track]) -> [Track])? = nil) {
        guard enabled != shuffleEnabled else { return }
        let current = currentTrack
        shuffleEnabled = enabled
        if enabled {
            let shuffled = shuffleSeed?(baseOrder) ?? baseOrder.shuffled()
            shuffledOrder = current.map { Self.bringToFront($0, in: shuffled) } ?? shuffled
            currentIndex = 0
        } else {
            // Resync index into the (non-shuffled) base order so next/previous stay correct.
            currentIndex = current.flatMap { baseOrder.firstIndex(of: $0) } ?? 0
        }
    }

    /// Remove a track from both orders (e.g. it was deleted). Returns true if it was the current track.
    /// Keeps `currentIndex` pointing at the same logical track when the removed one was not current.
    @discardableResult
    mutating func remove(_ track: Track) -> Bool {
        let removedCurrent = currentTrack == track
        let previousCurrent = currentTrack
        baseOrder.removeAll { $0 == track }
        shuffledOrder.removeAll { $0 == track }
        if removedCurrent {
            currentIndex = min(currentIndex, max(0, activeOrder.count - 1))
        } else if let previousCurrent, let idx = activeOrder.firstIndex(of: previousCurrent) {
            currentIndex = idx
        } else {
            currentIndex = min(currentIndex, max(0, activeOrder.count - 1))
        }
        return removedCurrent
    }

    /// Inserts a track directly after the current track. A queued copy is moved instead of
    /// duplicated, while the currently playing item is never removed.
    mutating func enqueueNext(_ track: Track) {
        guard let current = currentTrack else {
            setQueue([track], startAt: track)
            return
        }
        guard track != current else { return }
        var order = activeOrder
        order.removeAll { $0 == track }
        guard let currentPosition = order.firstIndex(of: current) else { return }
        order.insert(track, at: currentPosition + 1)
        replaceActiveOrder(order, keeping: current)
    }

    /// Appends a track to the end of the queue, moving any queued copy to the end.
    mutating func enqueueLater(_ track: Track) {
        guard let current = currentTrack else {
            setQueue([track], startAt: track)
            return
        }
        var order = activeOrder
        if track != current {
            order.removeAll { $0 == track }
            order.append(track)
        }
        replaceActiveOrder(order, keeping: current)
    }

    /// Reorders only the tracks after the current item. Offsets use SwiftUI `onMove` semantics.
    mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let current = currentTrack else { return }
        let prefix = Array(activeOrder.prefix(currentIndex + 1))
        let reordered = Playlist.moved(
            upcomingTracks,
            fromOffsets: source,
            toOffset: destination
        )
        replaceActiveOrder(prefix + reordered, keeping: current)
    }

    /// Removes tracks by their index in `upcomingTracks`.
    mutating func removeUpcoming(at offsets: IndexSet) {
        guard let current = currentTrack else { return }
        let prefix = Array(activeOrder.prefix(currentIndex + 1))
        var remaining = upcomingTracks
        for index in offsets.sorted(by: >) where remaining.indices.contains(index) {
            remaining.remove(at: index)
        }
        replaceActiveOrder(prefix + remaining, keeping: current)
    }

    mutating func clearUpcoming() {
        guard let current = currentTrack else { return }
        replaceActiveOrder(Array(activeOrder.prefix(currentIndex + 1)), keeping: current)
    }

    /// Replaces only the future portion of the queue while preserving playback history
    /// and the current track. The caller owns ordering and duplicate policy.
    mutating func replaceUpcoming(with tracks: [Track]) {
        guard let current = currentTrack else { return }
        let prefix = Array(activeOrder.prefix(currentIndex + 1))
        replaceActiveOrder(prefix + tracks, keeping: current)
    }

    private mutating func replaceActiveOrder(_ order: [Track], keeping current: Track) {
        baseOrder = order
        if shuffleEnabled { shuffledOrder = order }
        currentIndex = order.firstIndex(of: current) ?? 0
    }

    private static func bringToFront(_ track: Track, in array: [Track]) -> [Track] {
        guard let idx = array.firstIndex(of: track) else { return array }
        var copy = array
        copy.remove(at: idx)
        copy.insert(track, at: 0)
        return copy
    }
}
