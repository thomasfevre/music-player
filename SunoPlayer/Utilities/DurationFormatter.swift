import Foundation

enum DurationFormatter {
    /// Formats a TimeInterval into "m:ss" or "h:mm:ss" string.
    static func format(_ interval: TimeInterval) -> String {
        guard interval.isFinite && !interval.isNaN && interval >= 0 else {
            return "0:00"
        }
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
