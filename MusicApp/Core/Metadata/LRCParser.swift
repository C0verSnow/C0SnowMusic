import Foundation

struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: Double
    let text: String
}

enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        let pattern = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/
        let offsetPattern = /\[offset:([+-]?\d+)\]/
        let offset = text.firstMatch(of: offsetPattern).flatMap { Double($0.1) }.map { $0 / 1000 } ?? 0
        var entries: [(Double, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let matches = line.matches(of: pattern)
            guard let last = matches.last else { continue }
            let words = String(line[last.range.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(match.1), let seconds = Double(match.2), seconds < 60 else { continue }
                let fraction = match.3.map { Double("0." + $0)! } ?? 0
                entries.append((max(0, minutes * 60 + seconds + fraction + offset), words))
            }
        }
        return entries.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
