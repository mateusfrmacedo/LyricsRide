import Foundation

struct LRCLibRecord: Decodable {
    let trackName: String
    let artistName: String
    let syncedLyrics: String?
    let plainLyrics: String?
}

enum LRCLibService {
    static func lyrics(track: String, artist: String, duration: TimeInterval?) async throws -> [LyricLine] {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let duration {
            components.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }

        var request = URLRequest(url: components.url!)
        request.setValue("LyricsRide/0.1 (local iOS prototype)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.resourceUnavailable) }

        let record = try JSONDecoder().decode(LRCLibRecord.self, from: data)
        guard let synced = record.syncedLyrics else { throw URLError(.cannotParseResponse) }
        let lines = LRCParser.parse(synced)
        guard !lines.isEmpty else { throw URLError(.cannotParseResponse) }
        return lines
    }
}
