import ActivityKit
import Foundation

/// The compact state shared by the app and the Widget extension.
/// Keep this small: ActivityKit limits each Live Activity update to 4 KB.
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trackTitle: String
        var artistName: String
        var previousLyric: String?
        var previousTimestamp: Double?
        var lyric: String
        var lyricTimestamp: Double?
        var translation: String?
        var nextLyric: String?
        var nextTimestamp: Double?
        var position: Double
        var isPlaying: Bool
        /// Optional so an activity already on screen from an older app version
        /// can still be decoded after the extension is updated.
        var displayLineCount: Int?
        var fontScale: Double?
        var highContrast: Bool?
    }

    var sessionID: String
}
