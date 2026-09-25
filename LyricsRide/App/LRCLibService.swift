import Foundation

private struct LRCLibRecord: Decodable {
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
}

private actor LyricsLookupCache {
    static let shared = LyricsLookupCache()
    private var entries: [String: [LyricLine]] = [:]

    func lines(for key: String) -> [LyricLine]? { entries[key] }
    func store(_ lines: [LyricLine], for key: String) { entries[key] = lines }
}

enum LRCLibService {
    /// LRCLIB does not accept ISRC as a request parameter. We use it as the
    /// stable cache key, while title, artist, album and duration form the
    /// matching signature sent to the service.
    static func lyrics(for track: SpotifySnapshot) async throws -> [LyricLine] {
        let cacheKey = track.isrc ?? track.spotifyID
        if !cacheKey.isEmpty, let cached = await LyricsLookupCache.shared.lines(for: cacheKey) {
            return cached
        }

        let titles = candidateTitles(from: track.title)
        for (index, title) in titles.enumerated() {
            // LRCLIB asks clients to make sequential requests with a small gap.
            if index > 0 { try? await Task.sleep(for: .milliseconds(300)) }

            guard let record = try? await fetch(
                title: title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            ), isValid(record, for: track) else { continue }

            guard let synced = record.syncedLyrics else { continue }
            let lines = LRCParser.parse(synced)
            guard !lines.isEmpty else { continue }
            if !cacheKey.isEmpty { await LyricsLookupCache.shared.store(lines, for: cacheKey) }
            return lines
        }
        throw URLError(.resourceUnavailable)
    }

    private static func fetch(title: String, artist: String, album: String?, duration: TimeInterval) async throws -> LRCLibRecord {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        if let album, !album.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "album_name", value: album))
        }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue("LyricsRide/0.1 (local iOS prototype)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.resourceUnavailable) }
        return try JSONDecoder().decode(LRCLibRecord.self, from: data)
    }

    private static func isValid(_ record: LRCLibRecord, for track: SpotifySnapshot) -> Bool {
        guard normalized(record.trackName) == normalized(track.title) || candidateTitles(from: track.title).contains(where: { normalized($0) == normalized(record.trackName) }) else {
            return false
        }
        guard normalized(record.artistName).contains(normalized(track.artist)) || normalized(track.artist).contains(normalized(record.artistName)) else {
            return false
        }
        if let recordDuration = record.duration, abs(recordDuration - track.duration) > 2.5 {
            return false
        }
        return true
    }

    private static func candidateTitles(from title: String) -> [String] {
        let cleaned = title
            .replacingOccurrences(of: #"\s*\((?i:remaster(?:ed)?|deluxe|radio edit|single version)[^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*(?i:(?:\d{4}\s*)?remaster(?:ed)?|radio edit|single version)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned == title ? [title] : [title, cleaned]
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
