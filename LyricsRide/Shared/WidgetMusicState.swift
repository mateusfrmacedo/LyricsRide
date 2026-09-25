import Foundation
import WidgetKit

/// Small, non-copyright-sensitive snapshot shared with the Home Screen
/// widget. It is refreshed only when the song or lyric line changes.
struct WidgetMusicState: Codable, Equatable {
    let title: String
    let artist: String
    let previousLine: String?
    let currentLine: String
    let nextLine: String?
    let isPlaying: Bool
    let updatedAt: Date

    static let empty = WidgetMusicState(
        title: "Lyrics Ride",
        artist: "Abra o app e toque uma música",
        previousLine: nil,
        currentLine: "",
        nextLine: nil,
        isPlaying: false,
        updatedAt: .now
    )
}

enum LyricsRideWidgetStore {
    static let appGroup = "group.com.mateus.lyricsride"
    static let key = "now-playing-widget-state"
    static let kind = "LyricsRideHomeWidget"

    static func load() -> WidgetMusicState {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WidgetMusicState.self, from: data) else {
            return .empty
        }
        return state
    }

    static func save(_ state: WidgetMusicState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
