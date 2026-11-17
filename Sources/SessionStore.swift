import Foundation

enum SessionStore {
    static func load(from url: URL) -> SessionTracker? {
        guard let data = try? Data(contentsOf: url),
              let tracker = try? JSONDecoder().decode(SessionTracker.self, from: data),
              let last = tracker.lastSample, last.isValid else { return nil }
        if let session = tracker.session {
            guard session.start.isValid, session.start.onBattery, last.onBattery,
                  session.start.date <= last.date, session.start.percent >= last.percent else { return nil }
        }
        return tracker
    }

    static func save(_ tracker: SessionTracker, to url: URL) throws {
        let data = try JSONEncoder().encode(tracker)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
