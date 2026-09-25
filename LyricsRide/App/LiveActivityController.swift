import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<LyricsActivityAttributes>?
    private var stateWatcher: Task<Void, Never>?

    /// An Activity can outlive the app process. Reattach on launch so that a
    /// foreground return resumes updates instead of leaving the old content frozen.
    init() {
        activity = Activity<LyricsActivityAttributes>.activities.first
        if let activity { watch(activity) }
    }

    var isRunning: Bool { activity != nil }

    func start(track: String, artist: String, previousLine: LyricLine?, line: LyricLine, nextLine: LyricLine?, position: TimeInterval) async throws {
        await end()
        let attributes = LyricsActivityAttributes(sessionID: UUID().uuidString)
        let state = LyricsActivityAttributes.ContentState(
            trackTitle: track,
            artistName: artist,
            previousLyric: previousLine?.text,
            previousTimestamp: previousLine?.timestamp,
            lyric: line.text,
            lyricTimestamp: line.timestamp,
            translation: line.translation,
            nextLyric: nextLine?.text,
            nextTimestamp: nextLine?.timestamp,
            position: position,
            isPlaying: true
        )
        activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        if let activity { watch(activity) }
    }

    func update(track: String, artist: String, previousLine: LyricLine?, line: LyricLine, nextLine: LyricLine?, position: TimeInterval, isPlaying: Bool) async {
        guard let activity else { return }
        let state = LyricsActivityAttributes.ContentState(
            trackTitle: track,
            artistName: artist,
            previousLyric: previousLine?.text,
            previousTimestamp: previousLine?.timestamp,
            lyric: line.text,
            lyricTimestamp: line.timestamp,
            translation: line.translation,
            nextLyric: nextLine?.text,
            nextTimestamp: nextLine?.timestamp,
            position: position,
            isPlaying: isPlaying
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        stateWatcher?.cancel()
        stateWatcher = nil
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    private func watch(_ requested: Activity<LyricsActivityAttributes>) {
        stateWatcher?.cancel()
        stateWatcher = Task { [weak self] in
            for await state in requested.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                guard self?.activity?.id == requested.id else { continue }
                self?.activity = nil
            }
        }
    }
}
