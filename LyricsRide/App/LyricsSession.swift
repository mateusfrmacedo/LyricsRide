import Foundation

@MainActor
final class LyricsSession: ObservableObject {
    enum LyricsAvailability: Equatable {
        case idle
        case loading
        case available
        case unavailable
    }

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var liveActivityIsRunning = false
    @Published private(set) var lyricsAvailability: LyricsAvailability = .idle
    @Published var message = "Pronto para testar"

    private let liveActivity = LiveActivityController()
    private var clockTask: Task<Void, Never>?
    private var lyricsFetchTask: Task<Void, Never>?
    private var startedAt: Date?
    private var startingPosition: TimeInterval = 0
    private var activeSpotifyTrackID: String?
    private var lastPublishedSignature: ActivitySignature?
    private var lastWidgetSignature: ActivitySignature?
    private var liveActivityLineCount = UserDefaults.standard.integer(forKey: "liveActivityLineCount") == 1 ? 1 : 3
    private var highContrastLyrics = UserDefaults.standard.bool(forKey: "highContrastLyrics")
    private var lyricsFontScale = UserDefaults.standard.object(forKey: "lyricsFontScale") as? Double ?? 1.0

    init() {
        liveActivityIsRunning = liveActivity.isRunning
    }

    var currentLine: LyricLine { lyrics.line(at: position) }
    var previousLine: LyricLine? { lyrics.previousLine(before: currentLine.timestamp) }
    var nextLine: LyricLine? { lyrics.nextLine(after: position) }

    /// Spotify reports the real playhead whenever its player state changes.
    /// We use that as the source of truth and interpolate only between reports.
    func useSpotify(_ track: SpotifySnapshot) {
        let trackID = track.spotifyID.isEmpty ? "\(track.title)|\(track.artist)|\(track.duration)" : track.spotifyID
        guard trackID != activeSpotifyTrackID else {
            reconcileClock(with: track)
            return
        }

        activeSpotifyTrackID = trackID
        lyricsFetchTask?.cancel()
        title = track.title
        artist = track.artist
        lyrics = []
        lyricsAvailability = .loading
        lastPublishedSignature = nil
        reconcileClock(with: track, force: true)

        lyricsFetchTask = Task { [weak self] in
            do {
                let fetchedLyrics = try await LRCLibService.lyrics(for: track)
                guard let self, self.activeSpotifyTrackID == trackID else { return }
                self.lyrics = fetchedLyrics
                self.lyricsAvailability = fetchedLyrics.isEmpty ? .unavailable : .available
                self.lastPublishedSignature = nil
                self.reconcileClock(with: track, force: true)
                self.message = "Letra sincronizada encontrada no LRCLIB"
            } catch {
                guard let self, self.activeSpotifyTrackID == trackID else { return }
                self.lyricsAvailability = .unavailable
                self.message = "Letra sincronizada não encontrada para esta faixa"
            }
        }
    }

    func updateLyricsAppearance(lineCount: Int, fontScale: Double, highContrast: Bool) {
        liveActivityLineCount = min(max(lineCount, 1), 3)
        highContrastLyrics = highContrast
        lyricsFontScale = min(max(fontScale, 0.85), 1.15)
        UserDefaults.standard.set(liveActivityLineCount, forKey: "liveActivityLineCount")
        UserDefaults.standard.set(highContrast, forKey: "highContrastLyrics")
        UserDefaults.standard.set(lyricsFontScale, forKey: "lyricsFontScale")
        Task { await publishLiveActivity(force: true) }
    }

    func startLiveActivity() {
        Task {
            do {
                try await liveActivity.start(track: title, artist: artist, previousLine: previousLine, line: currentLine, nextLine: nextLine, position: position, lineCount: liveActivityLineCount, fontScale: lyricsFontScale, highContrast: highContrastLyrics)
                liveActivityIsRunning = true
                lastPublishedSignature = activitySignature
                message = "Live Activity iniciada"
            } catch {
                message = "Não foi possível iniciar a Live Activity: \(error.localizedDescription)"
            }
        }
    }

    func stopLiveActivity() {
        Task {
            await liveActivity.end()
            liveActivityIsRunning = false
            lastPublishedSignature = nil
            message = "Live Activity encerrada"
        }
    }

    func pause() {
        updatePosition()
        isPlaying = false
        clockTask?.cancel()
        clockTask = nil
        Task { await publishLiveActivity() }
        message = "Pausado"
    }

    private func beginClock(at initialPosition: TimeInterval) {
        clockTask?.cancel()
        startingPosition = initialPosition
        position = initialPosition
        startedAt = .now
        isPlaying = true
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                // 80 ms keeps line changes perceptually immediate without asking
                // ActivityKit to redraw unnecessarily: we publish only on a new line.
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, self.isPlaying else { return }
                self.updatePosition()
                await self.publishLiveActivity()
            }
        }
    }

    private func updatePosition() {
        guard let startedAt, isPlaying else { return }
        position = startingPosition + Date.now.timeIntervalSince(startedAt)
        if position > (lyrics.last?.timestamp ?? 0) + 7 {
            startingPosition = 0
            self.startedAt = .now
            position = 0
        }
    }

    private func reconcileClock(with track: SpotifySnapshot, force: Bool = false) {
        guard !track.isPaused else {
            clockTask?.cancel()
            clockTask = nil
            startedAt = nil
            startingPosition = track.position
            position = track.position
            isPlaying = false
            Task { await publishLiveActivity(force: true) }
            return
        }

        let predictedPosition = startedAt.map { startingPosition + Date.now.timeIntervalSince($0) } ?? position
        // Correct drift only when Spotify differs materially. This prevents a tiny
        // network jitter from making the lyric move backwards and forwards.
        if !isPlaying || abs(predictedPosition - track.position) > 0.30 || force {
            beginClock(at: track.position)
            Task { await publishLiveActivity(force: true) }
        }
    }

    private var activitySignature: ActivitySignature {
        ActivitySignature(
            title: title,
            artist: artist,
            previousLyric: previousLine?.text,
            lyric: currentLine.text,
            translation: currentLine.translation,
            nextLyric: nextLine?.text,
            isPlaying: isPlaying
        )
    }

    private func publishLiveActivity(force: Bool = false) async {
        let signature = activitySignature
        if force || signature != lastWidgetSignature {
            LyricsRideWidgetStore.save(
                WidgetMusicState(
                    title: title,
                    artist: artist,
                    previousLine: previousLine?.text,
                    currentLine: currentLine.text,
                    nextLine: nextLine?.text,
                    isPlaying: isPlaying,
                    updatedAt: .now
                )
            )
            lastWidgetSignature = signature
        }

        guard liveActivityIsRunning else { return }
        guard force || signature != lastPublishedSignature else { return }
        await liveActivity.update(track: title, artist: artist, previousLine: previousLine, line: currentLine, nextLine: nextLine, position: position, isPlaying: isPlaying, lineCount: liveActivityLineCount, fontScale: lyricsFontScale, highContrast: highContrastLyrics)
        lastPublishedSignature = signature
    }
}

private struct ActivitySignature: Equatable {
    let title: String
    let artist: String
    let previousLyric: String?
    let lyric: String
    let translation: String?
    let nextLyric: String?
    let isPlaying: Bool
}
