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

private struct SessionFileRecord: Codable {
    var path: String
    var byteCount: UInt64
    var modifiedAt: Date?
    var parsedOffset: UInt64
    var lastModel: String?
    var previousTotals: TokenTotals?
    var previousFootprint: TokenFootprint?
    var dailyUsage: [String: UsageAggregate]
}

private struct UsageLedger: Codable {
    var version: Int
    var savedAt: Date
    var files: [String: SessionFileRecord]
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
    var dailyUsage: [String: UsageAggregate]
}

private struct UsageRollup {
    let today: UsageAggregate
    let week: UsageAggregate
    let month: UsageAggregate
    let todayByAccount: [String: UsageAggregate]
    let weekByAccount: [String: UsageAggregate]
    let recentDaily: [(Date, UsageAggregate)]
    let scannedFiles: Int
}

private struct UsageScanFailure: Error {
    let message: String
}

final class TokenUsageScanner {
    private let pricingCatalog = ModelPricingCatalog.load()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("usage-ledger-v1.json")
    }()
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func scan(attribution: AttributionStore) -> UsageSnapshot {
        let result = scanCurrentMonth(attribution: attribution)
        switch result {
        case .failure(let failure):
            return UsageSnapshot(today: .zero, weekLocal: .zero, monthLocal: .zero, todayByAccount: [:], weekByAccount: [:], recentDaily: [], scannedFiles: 0, lastError: failure.message)
        case .success(let rollup):
            return UsageSnapshot(
                today: rollup.today,
                weekLocal: rollup.week,
                monthLocal: rollup.month,
                todayByAccount: rollup.todayByAccount,
                weekByAccount: rollup.weekByAccount,
                recentDaily: Array(rollup.recentDaily.prefix(5)),
                scannedFiles: rollup.scannedFiles,
                lastError: nil
            )
        }
    }

    func scanDetails(attribution: AttributionStore) -> UsageDetailSnapshot {
        let result = scanCurrentMonth(attribution: attribution)
        switch result {
        case .failure(let failure):
            return UsageDetailSnapshot(today: .zero, week: .zero, month: .zero, recentDaily: [], scannedFiles: 0, lastError: failure.message)
        case .success(let rollup):
            return UsageDetailSnapshot(
                today: rollup.today,
                week: rollup.week,
                month: rollup.month,
                recentDaily: Array(rollup.recentDaily.prefix(7)),
                scannedFiles: rollup.scannedFiles,
                lastError: nil
            )
        }
    }

    private func scanCurrentMonth(attribution: AttributionStore) -> Result<UsageRollup, UsageScanFailure> {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        guard fileManager.fileExists(atPath: root.path) else {
            return .failure(UsageScanFailure(message: "~/.codex/sessions not found"))
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? weekStart
        let files = jsonlFiles(in: root, from: monthStart, through: now, calendar: calendar)
        var ledger = loadLedger()
        var livePaths = Set<String>()

        for url in files {
            guard let metadata = metadata(for: url) else { continue }
            livePaths.insert(metadata.path)
            let record = updateRecord(for: url, metadata: metadata, existing: ledger.files[metadata.path], calendar: calendar)
            ledger.files[metadata.path] = record
        }

        ledger.files = ledger.files.filter { livePaths.contains($0.key) }
        ledger.savedAt = Date()
        saveLedger(ledger)

        let rollup = makeRollup(
            records: Array(ledger.files.values),
            todayStart: todayStart,
            weekStart: weekStart,
            monthStart: monthStart,
            calendar: calendar,
            attribution: attribution
        )
        return .success(rollup)
    }

    private func updateRecord(for url: URL, metadata: FileMetadata, existing: SessionFileRecord?, calendar: Calendar) -> SessionFileRecord {
        if let existing,
           existing.byteCount == metadata.byteCount,
           existing.modifiedAt == metadata.modifiedAt {
            return existing
        }

        let canAppend = existing != nil
            && metadata.byteCount >= (existing?.parsedOffset ?? 0)
            && (existing?.parsedOffset ?? 0) > 0
        let startOffset = canAppend ? existing?.parsedOffset ?? 0 : 0
        var state = RunningParseState(
            lastModel: canAppend ? existing?.lastModel : nil,
            previousTotals: canAppend ? existing?.previousTotals : nil,
            previousFootprint: canAppend ? existing?.previousFootprint : nil,
            dailyUsage: canAppend ? existing?.dailyUsage ?? [:] : [:]
        )
        let parsedOffset = streamFile(url, from: startOffset, calendar: calendar, state: &state) ?? startOffset

        return SessionFileRecord(
            path: metadata.path,
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            parsedOffset: parsedOffset,
            lastModel: state.lastModel,
            previousTotals: state.previousTotals,
            previousFootprint: state.previousFootprint,
            dailyUsage: state.dailyUsage
        )
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
        var buffer = Data()
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                var line = Data(buffer[..<newline])
                let byteLength = UInt64(line.count + 1)
                buffer.removeSubrange(...newline)
                consumed += byteLength
                if line.last == 13 {
                    line.removeLast()
                }
                processLine(line, calendar: calendar, state: &state)
            }
        }
        return consumed
    }

    private func processLine(_ line: Data, calendar: Calendar, state: inout RunningParseState) {
        guard lineContains(line, #""token_count""#) || lineContains(line, #""turn_context""#) else { return }
        guard let event = try? decoder.decode(CodexSessionEvent.self, from: line) else { return }

        if event.type == "turn_context" {
            if let model = event.payload?.model, model.isEmpty == false {
                state.lastModel = model
            }
            return
        }

        guard event.type == "event_msg", event.payload?.type == "token_count" else { return }
        guard let timestamp = event.timestamp,
              let eventDate = isoFormatter.date(from: timestamp) else { return }

        let cumulative = event.payload?.info?.totalTokenUsage
        let lastTurn = event.payload?.info?.lastTokenUsage
        let footprint = TokenFootprint(cumulative: cumulative, lastTurn: lastTurn)
        if state.previousFootprint == footprint {
            if let cumulative {
                state.previousTotals = cumulative
            }
            return
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
                return
            }
        } else {
            delta = nil
        }
        if let cumulative {
            state.previousTotals = cumulative
        }
        guard let normalized = delta?.normalized(), normalized.isZero == false else { return }

        let dayKey = self.dayKey(for: eventDate, calendar: calendar)
        let aggregate = makeAggregate(totals: normalized, model: state.lastModel)
        state.dailyUsage[dayKey] = (state.dailyUsage[dayKey] ?? .zero).adding(aggregate)
    }

    private func makeRollup(
        records: [SessionFileRecord],
        todayStart: Date,
        weekStart: Date,
        monthStart: Date,
        calendar: Calendar,
        attribution: AttributionStore
    ) -> UsageRollup {
        var today: UsageAggregate = .zero
        var week: UsageAggregate = .zero
        var month: UsageAggregate = .zero
        var todayByAccount: [String: UsageAggregate] = [:]
        var weekByAccount: [String: UsageAggregate] = [:]
        var daily: [Date: UsageAggregate] = [:]

        for record in records {
            for (key, aggregate) in record.dailyUsage {
                guard let date = dateFromDayKey(key, calendar: calendar), date >= monthStart else { continue }
                daily[date] = (daily[date] ?? .zero).adding(aggregate)
                month = month.adding(aggregate)
                if date >= weekStart {
                    week = week.adding(aggregate)
                    let email = attribution.accountEmail(at: date)
                    weekByAccount[email] = (weekByAccount[email] ?? .zero).adding(aggregate)
                }
                if date >= todayStart {
                    today = today.adding(aggregate)
                    let email = attribution.accountEmail(at: date)
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
            recentDaily: daily.map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 },
            scannedFiles: records.count
        )
    }

    private func makeAggregate(totals: TokenTotals, model: String?) -> UsageAggregate {
        let rates = pricingCatalog.rates(for: model)
        return UsageAggregate(totals: totals, costs: CostTotals(totals: totals, rates: rates))
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

    private func loadLedger() -> UsageLedger {
        guard let data = try? Data(contentsOf: cacheURL),
              let ledger = try? JSONDecoder.codexHub.decode(UsageLedger.self, from: data),
              ledger.version == 1 else {
            return UsageLedger(version: 1, savedAt: Date(), files: [:])
        }
        return ledger
    }

    private func saveLedger(_ ledger: UsageLedger) {
        guard let data = try? JSONEncoder.codexHub.encode(ledger) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func dateFromDayKey(_ key: String, calendar: Calendar) -> Date? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }

    private func lineContains(_ data: Data, _ marker: String) -> Bool {
        guard let markerData = marker.data(using: .utf8), markerData.isEmpty == false else { return false }
        return data.range(of: markerData) != nil
    }
}
