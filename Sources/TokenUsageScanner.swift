import Foundation

private struct CodexSessionEvent: Decodable {
    let type: String
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let model: String?
        let info: Info?

        struct Info: Decodable {
            let totalTokenUsage: TokenTotals?
            let lastTokenUsage: TokenTotals?

            enum CodingKeys: String, CodingKey {
                case totalTokenUsage = "total_token_usage"
                case lastTokenUsage = "last_token_usage"
            }
        }
    }
}

private struct TokenFootprint: Codable, Equatable {
    let cumulative: TokenTotals?
    let lastTurn: TokenTotals?
}

private struct SessionUsageEntry: Codable, Equatable {
    let timestamp: Date
    let aggregate: UsageAggregate
}

private struct SessionFileRecord: Codable, Equatable {
    var path: String
    var byteCount: UInt64
    var modifiedAt: Date?
    var parsedOffset: UInt64
    var appendFingerprint: String?
    var lastModel: String?
    var previousTotals: TokenTotals?
    var previousFootprint: TokenFootprint?
    var usageEvents: [SessionUsageEntry]
}

private struct UsageLedger: Codable, Equatable {
    var version: Int
    var savedAt: Date
    var files: [String: SessionFileRecord]
}

private struct LedgerLoadResult {
    var ledger: UsageLedger
    var loadedFromCache: Bool
}

private struct FileMetadata {
    let path: String
    let byteCount: UInt64
    let modifiedAt: Date?
}

private struct RunningParseState {
    var lastModel: String?
    var previousTotals: TokenTotals?
    var previousFootprint: TokenFootprint?
    var usageEvents: [SessionUsageEntry]
}

private struct UsageRollup {
    let today: UsageAggregate
    let week: UsageAggregate
    let month: UsageAggregate
    let todayByAccount: [String: UsageAggregate]
    let weekByAccount: [String: UsageAggregate]
    let monthByAccount: [String: UsageAggregate]
    let recentDaily: [(Date, UsageAggregate)]
    let scannedFiles: Int
}

private struct UsageScanFailure: Error {
    let message: String
}

struct UsageScanProgress {
    let completedFiles: Int
    let totalFiles: Int
    let completedBytes: UInt64
    let totalBytes: UInt64

    var fraction: Double {
        guard totalBytes > 0 else {
            return totalFiles == 0 ? 1 : Double(completedFiles) / Double(totalFiles)
        }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

private enum RollupMode {
    case todayOnly
    case full
}

private struct UsageAttribution {
    let historicalEmail: String?
    let attribution: AttributionStore

    func email(for date: Date) -> String {
        let resolved = attribution.accountEmail(at: date)
        if resolved == "Unknown" {
            return historicalEmail ?? "Unknown"
        }
        return resolved
    }
}

final class TokenUsageScanner {
    private let pricingCatalog = ModelPricingCatalog.load()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let scanQueue = DispatchQueue(label: "local.codexhub.token-usage-scanner")
    private let ledgerEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("usage-ledger-v2.json")
    }()
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func scan(attribution: AttributionStore, accounts: [CodexAccount]) -> UsageSnapshot {
        scanQueue.sync {
            scanUnlocked(attribution: attribution, accounts: accounts)
        }
    }

    func scanDetails(
        attribution: AttributionStore,
        accounts: [CodexAccount],
        progress: ((UsageScanProgress) -> Void)? = nil
    ) -> UsageDetailSnapshot {
        scanQueue.sync {
            scanDetailsUnlocked(attribution: attribution, accounts: accounts, progress: progress)
        }
    }

    private func scanUnlocked(attribution: AttributionStore, accounts: [CodexAccount]) -> UsageSnapshot {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: Date())
        let result = scanSessions(from: rangeStart, attribution: attribution, accounts: accounts, rollupMode: .todayOnly)
        switch result {
        case .failure(let failure):
            return UsageSnapshot(today: .zero, todayByAccount: [:], recentDaily: [], scannedFiles: 0, lastError: failure.message)
        case .success(let rollup):
            return UsageSnapshot(
                today: rollup.today,
                todayByAccount: rollup.todayByAccount,
                recentDaily: Array(rollup.recentDaily.prefix(5)),
                scannedFiles: rollup.scannedFiles,
                lastError: nil
            )
        }
    }

    private func scanDetailsUnlocked(
        attribution: AttributionStore,
        accounts: [CodexAccount],
        progress: ((UsageScanProgress) -> Void)?
    ) -> UsageDetailSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? weekStart
        let result = scanSessions(from: min(weekStart, monthStart), attribution: attribution, accounts: accounts, rollupMode: .full, progress: progress)
        switch result {
        case .failure(let failure):
            return UsageDetailSnapshot(today: .zero, week: .zero, month: .zero, weekByAccount: [:], monthByAccount: [:], recentDaily: [], scannedFiles: 0, lastError: failure.message)
        case .success(let rollup):
            return UsageDetailSnapshot(
                today: rollup.today,
                week: rollup.week,
                month: rollup.month,
                weekByAccount: rollup.weekByAccount,
                monthByAccount: rollup.monthByAccount,
                recentDaily: recentCalendarDays(from: rollup.recentDaily, endingAt: todayStart, count: 3, calendar: calendar),
                scannedFiles: rollup.scannedFiles,
                lastError: nil
            )
        }
    }

    private func scanSessions(
        from rangeStart: Date,
        attribution: AttributionStore,
        accounts: [CodexAccount],
        rollupMode: RollupMode,
        progress: ((UsageScanProgress) -> Void)? = nil
    ) -> Result<UsageRollup, UsageScanFailure> {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        guard fileManager.fileExists(atPath: root.path) else {
            return .failure(UsageScanFailure(message: L.text(ko: "~/.codex/sessions를 찾을 수 없습니다", en: "~/.codex/sessions not found")))
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? weekStart
        let retentionStart = min(weekStart, monthStart)
        let files = jsonlFiles(in: root, from: rangeStart, through: now, calendar: calendar)
        let loaded = loadLedger()
        var ledger = loaded.ledger
        var ledgerChanged = false
        var completedBytes: UInt64 = 0
        let metadataList = files.compactMap { metadata(for: $0) }
        let estimatedBytes = metadataList.map { estimatedBytesToRead(metadata: $0, existing: ledger.files[$0.path]) }
        let totalBytes = estimatedBytes.reduce(UInt64(0), +)
        progress?(UsageScanProgress(completedFiles: 0, totalFiles: metadataList.count, completedBytes: 0, totalBytes: totalBytes))

        for (index, metadata) in metadataList.enumerated() {
            let url = URL(fileURLWithPath: metadata.path)
            let existing = ledger.files[metadata.path]
            let record = updateRecord(for: url, metadata: metadata, existing: ledger.files[metadata.path], calendar: calendar)
            if existing != record {
                ledger.files[metadata.path] = record
                ledgerChanged = true
            }
            completedBytes += estimatedBytes[index]
            progress?(UsageScanProgress(
                completedFiles: index + 1,
                totalFiles: metadataList.count,
                completedBytes: completedBytes,
                totalBytes: totalBytes
            ))
        }

        if pruneExpiredRecords(&ledger, retentionStart: retentionStart) {
            ledgerChanged = true
        }
        if ledgerChanged {
            ledger.savedAt = now
            saveLedger(ledger)
        }
        if loaded.loadedFromCache || ledgerChanged {
            cleanupLegacyCachesIfSafe()
        }

        let attributionPolicy = UsageAttribution(
            historicalEmail: historicalAccountEmail(from: accounts),
            attribution: attribution
        )
        let rollupRecords: [SessionFileRecord]
        switch rollupMode {
        case .todayOnly:
            rollupRecords = files.compactMap { ledger.files[$0.path] }
        case .full:
            rollupRecords = Array(ledger.files.values)
        }
        let rollup = makeRollup(
            records: rollupRecords,
            todayStart: todayStart,
            weekStart: weekStart,
            monthStart: monthStart,
            calendar: calendar,
            attribution: attributionPolicy,
            mode: rollupMode
        )
        return .success(rollup)
    }

    private func updateRecord(for url: URL, metadata: FileMetadata, existing: SessionFileRecord?, calendar: Calendar) -> SessionFileRecord {
        if let existing,
           existing.byteCount == metadata.byteCount,
           existing.parsedOffset == metadata.byteCount {
            var next = existing
            next.modifiedAt = metadata.modifiedAt
            return next
        }

        let canAppend = canAppendSafely(to: url, metadata: metadata, existing: existing)
        let startOffset = canAppend ? existing?.parsedOffset ?? 0 : 0
        var state = RunningParseState(
            lastModel: canAppend ? existing?.lastModel : nil,
            previousTotals: canAppend ? existing?.previousTotals : nil,
            previousFootprint: canAppend ? existing?.previousFootprint : nil,
            usageEvents: canAppend ? existing?.usageEvents ?? [] : []
        )
        let parsedOffset = streamFile(url, from: startOffset, calendar: calendar, state: &state) ?? startOffset

        return SessionFileRecord(
            path: metadata.path,
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            parsedOffset: parsedOffset,
            appendFingerprint: appendFingerprint(for: url, upTo: parsedOffset),
            lastModel: state.lastModel,
            previousTotals: state.previousTotals,
            previousFootprint: state.previousFootprint,
            usageEvents: state.usageEvents
        )
    }

    private func canAppendSafely(to url: URL, metadata: FileMetadata, existing: SessionFileRecord?) -> Bool {
        guard let existing,
              existing.parsedOffset > 0,
              metadata.byteCount > existing.parsedOffset,
              metadata.byteCount >= existing.byteCount,
              let fingerprint = existing.appendFingerprint else {
            return false
        }

        // JSONL session files are expected to grow append-only. Before parsing only
        // the new bytes, verify the parsed prefix still matches the ledger.
        // If the previous scan stopped before an in-progress trailing line, reading
        // from parsedOffset lets the now-complete line be processed without reparsing
        // the whole active session file.
        return appendFingerprint(for: url, upTo: existing.parsedOffset) == fingerprint
    }

    private func estimatedBytesToRead(metadata: FileMetadata, existing: SessionFileRecord?) -> UInt64 {
        guard let existing else { return metadata.byteCount }
        if existing.byteCount == metadata.byteCount,
           existing.parsedOffset == metadata.byteCount {
            return 0
        }
        if canAppendSafely(to: URL(fileURLWithPath: metadata.path), metadata: metadata, existing: existing) {
            return metadata.byteCount - existing.parsedOffset
        }
        return metadata.byteCount
    }

    private func streamFile(_ url: URL, from offset: UInt64, calendar: Calendar, state: inout RunningParseState) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }

        var consumed = offset
        var carry = Data()
        while true {
            let chunk = handle.readData(ofLength: 256 * 1024)
            if chunk.isEmpty { break }
            var buffer = carry
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            var searchStart = lineStart
            while let newline = buffer[searchStart...].firstIndex(of: 10) {
                var line = Data(buffer[lineStart..<newline])
                let byteLength = UInt64(line.count + 1)
                consumed += byteLength
                if line.last == 13 {
                    line.removeLast()
                }
                _ = processLine(line, calendar: calendar, state: &state)
                lineStart = buffer.index(after: newline)
                searchStart = lineStart
            }
            carry = lineStart < buffer.endIndex ? Data(buffer[lineStart..<buffer.endIndex]) : Data()
        }
        if carry.isEmpty == false, processLine(carry, calendar: calendar, state: &state) {
            consumed += UInt64(carry.count)
        }
        return consumed
    }

    private func processLine(_ line: Data, calendar: Calendar, state: inout RunningParseState) -> Bool {
        guard lineContains(line, #""token_count""#) || lineContains(line, #""turn_context""#) else { return true }
        guard let event = try? decoder.decode(CodexSessionEvent.self, from: line) else { return false }

        if event.type == "turn_context" {
            if let model = event.payload?.model, model.isEmpty == false {
                state.lastModel = model
            }
            return true
        }

        guard event.type == "event_msg", event.payload?.type == "token_count" else { return true }
        guard let timestamp = event.timestamp,
              let eventDate = isoFormatter.date(from: timestamp) else { return true }

        let cumulative = event.payload?.info?.totalTokenUsage
        let lastTurn = event.payload?.info?.lastTokenUsage
        let footprint = TokenFootprint(cumulative: cumulative, lastTurn: lastTurn)
        if state.previousFootprint == footprint {
            if let cumulative {
                state.previousTotals = cumulative
            }
            return true
        }
        state.previousFootprint = footprint

        let delta: TokenTotals?
        if let lastTurn {
            delta = lastTurn
        } else if let cumulative {
            if let previous = state.previousTotals {
                delta = cumulative.delta(since: previous)
            } else {
                state.previousTotals = cumulative
                return true
            }
        } else {
            delta = nil
        }
        if let cumulative {
            state.previousTotals = cumulative
        }
        guard let normalized = delta?.normalized(), normalized.isZero == false else { return true }

        let aggregate = makeAggregate(totals: normalized, model: state.lastModel)
        state.usageEvents.append(SessionUsageEntry(timestamp: eventDate, aggregate: aggregate))
        return true
    }

    private func makeRollup(
        records: some Sequence<SessionFileRecord>,
        todayStart: Date,
        weekStart: Date,
        monthStart: Date,
        calendar: Calendar,
        attribution: UsageAttribution,
        mode: RollupMode
    ) -> UsageRollup {
        var today: UsageAggregate = .zero
        var week: UsageAggregate = .zero
        var month: UsageAggregate = .zero
        var todayByAccount: [String: UsageAggregate] = [:]
        var weekByAccount: [String: UsageAggregate] = [:]
        var monthByAccount: [String: UsageAggregate] = [:]
        var daily: [Date: UsageAggregate] = [:]
        var recordCount = 0
        let dailyStart = mode == .todayOnly ? todayStart : min(weekStart, monthStart)

        for record in records {
            recordCount += 1
            for entry in record.usageEvents {
                guard entry.timestamp >= dailyStart else { continue }
                let date = calendar.startOfDay(for: entry.timestamp)
                let aggregate = entry.aggregate
                let email = attribution.email(for: entry.timestamp)
                daily[date] = (daily[date] ?? .zero).adding(aggregate)
                if mode == .full, entry.timestamp >= monthStart {
                    month = month.adding(aggregate)
                    monthByAccount[email] = (monthByAccount[email] ?? .zero).adding(aggregate)
                }
                if mode == .full, date >= weekStart {
                    week = week.adding(aggregate)
                    weekByAccount[email] = (weekByAccount[email] ?? .zero).adding(aggregate)
                }
                if date >= todayStart {
                    today = today.adding(aggregate)
                    todayByAccount[email] = (todayByAccount[email] ?? .zero).adding(aggregate)
                }
            }
        }

        return UsageRollup(
            today: today,
            week: week,
            month: month,
            todayByAccount: todayByAccount,
            weekByAccount: weekByAccount,
            monthByAccount: monthByAccount,
            recentDaily: daily.map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 },
            scannedFiles: recordCount
        )
    }

    private func makeAggregate(totals: TokenTotals, model: String?) -> UsageAggregate {
        let rates = pricingCatalog.rates(for: model)
        return UsageAggregate(totals: totals, costs: CostTotals(totals: totals, rates: rates))
    }

    private func recentCalendarDays(
        from rows: [(Date, UsageAggregate)],
        endingAt todayStart: Date,
        count: Int,
        calendar: Calendar
    ) -> [(Date, UsageAggregate)] {
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { (calendar.startOfDay(for: $0.0), $0.1) })
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return (date, lookup[date] ?? .zero)
        }
    }

    private func jsonlFiles(in root: URL, from start: Date, through end: Date, calendar: Calendar) -> [URL] {
        var files: [URL] = []
        var date = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while date <= endDay {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let dayRoot = root
                .appendingPathComponent(String(format: "%04d", components.year ?? 0), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", components.day ?? 0), isDirectory: true)
            if let enumerator = fileManager.enumerator(
                at: dayRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    files.append(url)
                }
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        return files
    }

    private func metadata(for url: URL) -> FileMetadata? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let fileSize = values.fileSize else { return nil }
        return FileMetadata(path: url.path, byteCount: UInt64(max(fileSize, 0)), modifiedAt: values.contentModificationDate)
    }

    private func appendFingerprint(for url: URL, upTo offset: UInt64) -> String? {
        guard offset > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let window: UInt64 = 4096
        let headLength = min(window, offset)
        let tailStart = offset > window ? offset - window : 0
        let tailLength = offset - tailStart
        var sample = Data()

        do {
            try handle.seek(toOffset: 0)
            sample.append(handle.readData(ofLength: Int(headLength)))
            if tailStart > headLength {
                try handle.seek(toOffset: tailStart)
                sample.append(handle.readData(ofLength: Int(tailLength)))
            }
        } catch {
            return nil
        }

        return "\(offset):\(fnv1a64(sample))"
    }

    private func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private func loadLedger() -> LedgerLoadResult {
        guard let data = try? Data(contentsOf: cacheURL),
              let ledger = try? JSONDecoder.codexHub.decode(UsageLedger.self, from: data),
              ledger.version == 2 else {
            return LedgerLoadResult(ledger: UsageLedger(version: 2, savedAt: Date(), files: [:]), loadedFromCache: false)
        }
        return LedgerLoadResult(ledger: ledger, loadedFromCache: true)
    }

    private func saveLedger(_ ledger: UsageLedger) {
        guard let data = try? ledgerEncoder.encode(ledger) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func historicalAccountEmail(from accounts: [CodexAccount]) -> String? {
        accounts.first { account in
            let email = account.email.lowercased()
            return email.hasPrefix("n") || email.contains("snu")
        }?.email ?? accounts.first?.email
    }

    private func pruneExpiredRecords(_ ledger: inout UsageLedger, retentionStart: Date) -> Bool {
        var changed = false
        var retained: [String: SessionFileRecord] = [:]
        retained.reserveCapacity(ledger.files.count)
        for (path, record) in ledger.files {
            var next = record
            let currentEvents = record.usageEvents.filter { $0.timestamp >= retentionStart }
            if currentEvents.count != record.usageEvents.count {
                next.usageEvents = currentEvents
                changed = true
            }
            if next.usageEvents.isEmpty,
               let modifiedAt = next.modifiedAt,
               modifiedAt < retentionStart {
                changed = true
                continue
            }
            retained[path] = next
        }
        if retained.count != ledger.files.count {
            changed = true
        }
        if changed {
            ledger.files = retained
        }
        return changed
    }

    private func cleanupLegacyCachesIfSafe() {
        let directory = cacheURL.deletingLastPathComponent()
        for filename in ["usage-ledger-v1.json", "usage-detail-cache.json"] {
            let url = directory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func lineContains(_ data: Data, _ marker: String) -> Bool {
        guard let markerData = marker.data(using: .utf8), markerData.isEmpty == false else { return false }
        return data.range(of: markerData) != nil
    }
}
