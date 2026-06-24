import Foundation

final class AttributionStore {
    private let fileURL: URL
    private(set) var events: [AttributionEvent] = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("attribution-events.json")
        load()
    }

    func seedLegacyAccountIfNeeded(_ email: String?) {
        guard events.isEmpty, let email, email.isEmpty == false else { return }
        events = [AttributionEvent(timestamp: Date(timeIntervalSince1970: 946_684_800), email: email)]
        save()
    }

    func recordActiveAccount(_ email: String) {
        guard events.last?.email != email else { return }
        events.append(AttributionEvent(timestamp: Date(), email: email))
        events.sort { $0.timestamp < $1.timestamp }
        save()
    }

    func accountEmail(at date: Date) -> String {
        var current = "Unknown"
        for event in events where event.timestamp <= date {
            current = event.email
        }
        return current
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.codexHub.decode([AttributionEvent].self, from: data) else {
            events = []
            return
        }
        events = decoded.sorted { $0.timestamp < $1.timestamp }
    }

    private func save() {
        guard let data = try? JSONEncoder.codexHub.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
