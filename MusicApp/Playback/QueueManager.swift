import Foundation

enum RepeatMode: String, CaseIterable, Codable, Identifiable {
    case off, all, one
    var id: String { rawValue }
    var title: String { switch self { case .off: "Repeat off"; case .all: "Repeat all"; case .one: "Repeat one" } }
}

struct QueueEntry: Identifiable, Equatable {
    let id = UUID()
    let songID: UUID
}

struct QueueManager {
    var entries: [QueueEntry] = []
    var index = 0
    var current: QueueEntry? { entries.indices.contains(index) ? entries[index] : nil }

    mutating func replace(_ songIDs: [UUID], startingAt index: Int) {
        entries = songIDs.map { QueueEntry(songID: $0) }
        self.index = entries.isEmpty ? 0 : min(max(0, index), entries.count - 1)
    }

    @discardableResult mutating func advance(automatic: Bool, repeatMode: RepeatMode) -> Bool {
        guard !entries.isEmpty else { return false }
        if automatic, repeatMode == .one { return true }
        if index + 1 < entries.count { index += 1; return true }
        if repeatMode == .all { index = 0; return true }
        return false
    }

    mutating func insert(_ songID: UUID, next: Bool) {
        let entry = QueueEntry(songID: songID)
        if next, !entries.isEmpty { entries.insert(entry, at: index + 1) }
        else { entries.append(entry) }
    }

    mutating func shuffleUpcoming() {
        guard index + 1 < entries.count else { return }
        let upcoming = entries[(index + 1)...].shuffled()
        entries.replaceSubrange((index + 1)..., with: upcoming)
    }

    mutating func remove(_ offsets: IndexSet) {
        let selectedID = current?.id
        let removedBefore = offsets.filter { $0 < index }.count
        for offset in offsets.sorted(by: >) { entries.remove(at: offset) }
        if let selectedID, let newIndex = entries.firstIndex(where: { $0.id == selectedID }) { index = newIndex }
        else { index = min(max(0, index - removedBefore), max(0, entries.count - 1)) }
    }
}
