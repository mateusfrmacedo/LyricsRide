import Foundation

enum LRCParser {
    /// Parses standard line-synced LRC. Multiple timestamps on one line are supported.
    static func parse(_ source: String) -> [LyricLine] {
        let timestamp = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2}(?:\.\d{1,3})?)\]"#)

        return source
            .split(whereSeparator: \.isNewline)
            .flatMap { rawLine -> [LyricLine] in
                let line = String(rawLine)
                let range = NSRange(line.startIndex..., in: line)
                let matches = timestamp?.matches(in: line, range: range) ?? []
                let lyric = timestamp?.stringByReplacingMatches(in: line, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces) ?? line

                return matches.compactMap { match in
                    guard
                        let minuteRange = Range(match.range(at: 1), in: line),
                        let secondRange = Range(match.range(at: 2), in: line),
                        let minutes = TimeInterval(line[minuteRange]),
                        let seconds = TimeInterval(line[secondRange])
                    else { return nil }

                    return LyricLine(timestamp: minutes * 60 + seconds, text: lyric, translation: nil)
                }
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
