import Foundation
import Observation

@MainActor @Observable final class AppDiagnostics {
    static let shared = AppDiagnostics()

    struct Event: Identifiable {
        let id = UUID()
        let date: Date
        let operation: String
        let message: String
    }
    struct Operation: Identifiable {
        let id: UUID
        let name: String
        let started: Date
        var stage: String
        var detail: String
        var stageStarted: Date
    }
    private(set) var events: [Event] = []
    private(set) var active: [Operation] = []
    @ObservationIgnored private var importedLines: [UUID: Int] = [:]

    func begin(_ name: String) -> UUID {
        let id = UUID()
        let now = Date()
        active.append(Operation(id: id, name: Self.redact(name), started: now, stage: "Starting", detail: "", stageStarted: now))
        append(name, "Starting")
        return id
    }

    func step(_ id: UUID?, _ stage: String, detail: String = "", at date: Date = Date()) {
        guard let id, let index = active.firstIndex(where: { $0.id == id }) else { return }
        if active[index].stage != stage {
            active[index].stage = Self.redact(stage)
            active[index].stageStarted = date
        }
        active[index].detail = Self.redact(detail)
        append(active[index].name, detail.isEmpty ? stage : "\(stage): \(detail)", at: date)
    }

    func finish(_ id: UUID, error: Error? = nil, detail: String = "") {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        let operation = active.remove(at: index)
        importedLines.removeValue(forKey: id)
        let elapsed = String(format: "%.1f s", Date().timeIntervalSince(operation.started))
        let outcome = error.map(Self.describe) ?? (detail.isEmpty ? "Completed" : detail)
        append(operation.name, "\(outcome) (\(elapsed))")
    }

    func collectDownloadEvents(from file: URL, operation: UUID) {
        guard let data = try? String(contentsOf: file, encoding: .utf8) else { return }
        // The writer can still be appending the last line.
        let lines = data.components(separatedBy: "\n").dropLast()
        let offset = importedLines[operation] ?? 0
        for line in lines.dropFirst(offset) {
            if let event = try? JSONDecoder().decode(DownloadEvent.self, from: Data(line.utf8)) {
                let date = event.timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()
                step(operation, event.stage, detail: event.message, at: date)
            }
        }
        importedLines[operation] = lines.count
    }

    func clear() { events.removeAll() }

    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let header = "c0versnow music \(version) (\(build)) — diagnostics\n"
        let current = active.map { "ACTIVE \($0.name): \($0.stage), \($0.detail), \(Int(Date().timeIntervalSince($0.started))) s total" }.joined(separator: "\n")
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let history = events.map { "\($0.date.formatted(format)) [\($0.operation)] \($0.message)" }.joined(separator: "\n")
        return header + current + "\n" + history
    }

    func checkYouTubeConnection() async {
        let id = begin("YouTube connectivity")
        step(id, "Connecting", detail: "music.youtube.com; 15 s timeout")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: URL(string: "https://music.youtube.com/")!)
            request.httpMethod = "HEAD"; request.timeoutInterval = 15
            let (_, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            finish(id, detail: "HTTP \(http?.statusCode ?? 0), host \(response.url?.host ?? "unknown")")
        } catch { finish(id, error: error) }
    }

    static func describe(_ error: Error) -> String {
        if error is CancellationError { return "Cancelled" }
        let value = error as NSError
        return redact("\(value.domain) \(value.code): \(error.localizedDescription)")
    }

    static func redact(_ text: String) -> String {
        var result = text
        let urls = try! NSRegularExpression(pattern: #"https?://[^\s<>"']+"#)
        for match in urls.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let host = URL(string: String(result[range]))?.host ?? "redacted-url"
            result.replaceSubrange(range, with: "https://\(host)/<redacted>")
        }
        for pattern in [#"(?im)\b(authorization|cookie|set-cookie|x-api-key|x-admin-key)\s*[:=][^\r\n]*"#, #"(?i)\bBearer\s+[^\s,;]+"#, #"\b\d{6,}:[A-Za-z0-9_-]{20,}\b"#] {
            result = result.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return String(result.prefix(800))
    }

    private func append(_ operation: String, _ message: String, at date: Date = Date()) {
        events.append(Event(date: date, operation: Self.redact(operation), message: Self.redact(message)))
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }
    private struct DownloadEvent: Decodable {
        let stage: String
        let message: String
        let timestamp: TimeInterval?
    }
}
