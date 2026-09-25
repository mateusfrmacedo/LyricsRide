import Foundation

struct LyricLine: Identifiable, Hashable {
    let timestamp: TimeInterval
    let text: String
    let translation: String?

    var id: TimeInterval { timestamp }
}

extension Array where Element == LyricLine {
    func line(at position: TimeInterval) -> LyricLine {
        last(where: { $0.timestamp <= position }) ?? first ?? LyricLine(timestamp: 0, text: "Sem letra disponível", translation: nil)
    }

    func nextLine(after position: TimeInterval) -> LyricLine? {
        first(where: { $0.timestamp > position })
    }

    func previousLine(before position: TimeInterval) -> LyricLine? {
        last(where: { $0.timestamp < position })
    }
}
