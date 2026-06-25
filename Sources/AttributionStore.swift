import Foundation

final class AttributionStore {
    private let fileURL: URL
    private let lock = NSLock()
    private(set) var events: [AttributionEvent] = []

    init() {
        let appSupport = LocalStorageSecurity.codexHubApplicationSupportDirectory()
        fileURL = appSupport.appendingPathComponent("attribution-events.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? LocalStorageSecurity.setPrivateFilePermissions(fileURL)
        }
        load()
    }

    func seedLegacyAccountIfNeeded(_ email: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard events.isEmpty, let email, email.isEmpty == false else { return }
        events = [AttributionEvent(timestamp: Date(timeIntervalSince1970: 946_684_800), email: email)]
        save()
    }

    func recordActiveAccount(_ email: String) {
        lock.lock()
        defer { lock.unlock() }
        guard events.last?.email != email else { return }
        events.append(AttributionEvent(timestamp: Date(), email: email))
        events.sort { $0.timestamp < $1.timestamp }
        save()
    }

    func resetHistory(currentEmail: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let currentEmail, currentEmail.isEmpty == false {
            events = [AttributionEvent(timestamp: Date(), email: currentEmail)]
            save()
        } else {
            events = []
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func accountEmail(at date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
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
        try? LocalStorageSecurity.writePrivateFileAtomically(data, to: fileURL)
    }
}
