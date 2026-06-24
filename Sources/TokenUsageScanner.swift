import Foundation

private struct TokenLogLine: Decodable {
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

private struct UsageSignature: Hashable {
    let totalTokenUsage: TokenTotals?
    let lastTokenUsage: TokenTotals?
}

private extension Data {
    func containsAscii(_ marker: String) -> Bool {
        guard let needle = marker.data(using: .utf8), needle.isEmpty == false else { return false }
        return range(of: needle) != nil
    }
}

final class TokenUsageScanner {
    private let pricingCatalog = ModelPricingCatalog.load()
    private let decoder = JSONDecoder()
    private let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("usage-detail-cache.json")
    }()
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func scan(attribution: AttributionStore) -> UsageSnapshot {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        guard FileManager.default.fileExists(atPath: root.path) else {
            return UsageSnapshot(today: .zero, weekLocal: .zero, monthLocal: .zero, todayByAccount: [:], weekByAccount: [:], recentDaily: [], scannedFiles: 0, lastError: "~/.codex/sessions not found")
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? weekStart
        var today: UsageAggregate = .zero
        var weekLocal: UsageAggregate = .zero
        var monthLocal: UsageAggregate = .zero
        var todayByAccount: [String: UsageAggregate] = [:]
        var weekByAccount: [String: UsageAggregate] = [:]
        var daily: [Date: UsageAggregate] = [:]
        var scannedFiles = 0

        let files = jsonlFilesForDateRange(root: root, start: todayStart, end: now, calendar: calendar)
        for file in files {
            scannedFiles += 1
            processFile(
                file,
                todayStart: todayStart,
                weekStart: weekStart,
                monthStart: monthStart,
                calendar: calendar,
                attribution: attribution,
                today: &today,
                weekLocal: &weekLocal,
                monthLocal: &monthLocal,
                todayByAccount: &todayByAccount,
                weekByAccount: &weekByAccount,
                daily: &daily
            )
        }

        let recentDaily = daily
            .map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
            .prefix(5)
            .map { ($0.0, $0.1) }

        return UsageSnapshot(
            today: today,
            weekLocal: weekLocal,
            monthLocal: monthLocal,
            todayByAccount: todayByAccount,
            weekByAccount: weekByAccount,
            recentDaily: recentDaily,
            scannedFiles: scannedFiles,
            lastError: nil
        )
    }

    func scanDetails(attribution: AttributionStore) -> UsageDetailSnapshot {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        guard FileManager.default.fileExists(atPath: root.path) else {
            return UsageDetailSnapshot(today: .zero, week: .zero, month: .zero, recentDaily: [], scannedFiles: 0, lastError: "~/.codex/sessions not found")
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? weekStart
        var today: UsageAggregate = .zero
        var weekLocal: UsageAggregate = .zero
        var monthLocal: UsageAggregate = .zero
        var todayByAccount: [String: UsageAggregate] = [:]
        var weekByAccount: [String: UsageAggregate] = [:]
        var daily: [Date: UsageAggregate] = [:]
        var scannedFiles = 0

        let files = jsonlFilesForDateRange(root: root, start: monthStart, end: now, calendar: calendar)
        let newestFileMTime = newestModificationDate(for: files)
        let cacheKey = detailCacheKey(monthStart: monthStart, calendar: calendar)
        if let cached = loadDetailCache(cacheKey: cacheKey, newestFileMTime: newestFileMTime, scannedFiles: files.count) {
            return cached
        }

        for file in files {
            scannedFiles += 1
            processFile(
                file,
                todayStart: todayStart,
                weekStart: weekStart,
                monthStart: monthStart,
                calendar: calendar,
                attribution: attribution,
                today: &today,
                weekLocal: &weekLocal,
                monthLocal: &monthLocal,
                todayByAccount: &todayByAccount,
                weekByAccount: &weekByAccount,
                daily: &daily
            )
        }

        let recentDaily = daily
            .map { ($0.key, $0.value) }
            .sorted { $0.0 > $1.0 }
            .prefix(7)
            .map { ($0.0, $0.1) }

        let snapshot = UsageDetailSnapshot(
            today: today,
            week: weekLocal,
            month: monthLocal,
            recentDaily: recentDaily,
            scannedFiles: scannedFiles,
            lastError: nil
        )
        saveDetailCache(snapshot: snapshot, cacheKey: cacheKey, newestFileMTime: newestFileMTime)
        return snapshot
    }

    private func processFile(
        _ file: URL,
        todayStart: Date,
        weekStart: Date,
        monthStart: Date,
        calendar: Calendar,
        attribution: AttributionStore,
        today: inout UsageAggregate,
        weekLocal: inout UsageAggregate,
        monthLocal: inout UsageAggregate,
        todayByAccount: inout [String: UsageAggregate],
        weekByAccount: inout [String: UsageAggregate],
        daily: inout [Date: UsageAggregate]
    ) {
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { return }

        var previousTotals: TokenTotals?
        var lastSignature: UsageSignature?
        var lastModel: String?

        for rawLine in data.split(separator: 10, omittingEmptySubsequences: true) {
            let line = rawLine.last == 13 ? rawLine.dropLast() : rawLine
            processLine(
                Data(line),
                previousTotals: &previousTotals,
                lastSignature: &lastSignature,
                lastModel: &lastModel,
                todayStart: todayStart,
                weekStart: weekStart,
                monthStart: monthStart,
                calendar: calendar,
                attribution: attribution,
                today: &today,
                weekLocal: &weekLocal,
                monthLocal: &monthLocal,
                todayByAccount: &todayByAccount,
                weekByAccount: &weekByAccount,
                daily: &daily
            )
        }
    }

    private func processLine(
        _ lineData: Data,
        previousTotals: inout TokenTotals?,
        lastSignature: inout UsageSignature?,
        lastModel: inout String?,
        todayStart: Date,
        weekStart: Date,
        monthStart: Date,
        calendar: Calendar,
        attribution: AttributionStore,
        today: inout UsageAggregate,
        weekLocal: inout UsageAggregate,
        monthLocal: inout UsageAggregate,
        todayByAccount: inout [String: UsageAggregate],
        weekByAccount: inout [String: UsageAggregate],
        daily: inout [Date: UsageAggregate]
    ) {
        guard lineData.containsAscii(#""token_count""#) || lineData.containsAscii(#""turn_context""#) else {
            return
        }
        guard let event = try? decoder.decode(TokenLogLine.self, from: lineData) else { return }

        if event.type == "turn_context" {
            if let model = event.payload?.model, model.isEmpty == false {
                lastModel = model
            }
            return
        }

        guard event.type == "event_msg", event.payload?.type == "token_count" else { return }
        guard let timestamp = event.timestamp,
              let eventDate = isoFormatter.date(from: timestamp) else { return }

        let currentTotals = event.payload?.info?.totalTokenUsage
        let lastUsage = event.payload?.info?.lastTokenUsage
        let signature = UsageSignature(totalTokenUsage: currentTotals, lastTokenUsage: lastUsage)
        if let lastSignature, lastSignature == signature {
            if let currentTotals { previousTotals = currentTotals }
            return
        }
        lastSignature = signature

        let delta: TokenTotals?
        if let lastUsage {
            delta = lastUsage
        } else if let currentTotals {
            if let previousTotals {
                delta = currentTotals.delta(since: previousTotals)
            } else {
                previousTotals = currentTotals
                return
            }
        } else {
            delta = nil
        }
        if let currentTotals { previousTotals = currentTotals }
        guard let normalized = delta?.normalized(), normalized.isZero == false else { return }

        let aggregate = makeAggregate(totals: normalized, model: lastModel)
        let day = calendar.startOfDay(for: eventDate)
        daily[day] = (daily[day] ?? .zero).adding(aggregate)
        if eventDate >= monthStart {
            monthLocal = monthLocal.adding(aggregate)
        }
        if eventDate >= weekStart {
            weekLocal = weekLocal.adding(aggregate)
            let email = attribution.accountEmail(at: eventDate)
            weekByAccount[email] = (weekByAccount[email] ?? .zero).adding(aggregate)
        }
        if eventDate >= todayStart {
            today = today.adding(aggregate)
            let email = attribution.accountEmail(at: eventDate)
            todayByAccount[email] = (todayByAccount[email] ?? .zero).adding(aggregate)
        }
    }

    private func makeAggregate(totals: TokenTotals, model: String?) -> UsageAggregate {
        let rates = pricingCatalog.rates(for: model)
        return UsageAggregate(totals: totals, costs: CostTotals(totals: totals, rates: rates))
    }

    private func jsonlFilesForActiveWeek(root: URL, now: Date, calendar: Calendar) -> [URL] {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return jsonlFilesForDateRange(root: root, start: weekStart, end: now, calendar: calendar)
    }

    private func jsonlFilesForDateRange(root: URL, start: Date, end: Date, calendar: Calendar) -> [URL] {
        var files: [URL] = []
        var date = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while date <= endDay {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let dayRoot = root
                .appendingPathComponent(String(format: "%04d", components.year ?? 0), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", components.day ?? 0), isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: dayRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                files.append(url)
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        return files
    }

    private func detailCacheKey(monthStart: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func newestModificationDate(for files: [URL]) -> Date? {
        files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else { return nil }
            return values.contentModificationDate
        }
        .max()
    }

    private func loadDetailCache(cacheKey: String, newestFileMTime: Date?, scannedFiles: Int) -> UsageDetailSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder.codexHub.decode(UsageDetailCacheFile.self, from: data),
              cache.cacheKey == cacheKey,
              cache.scannedFiles == scannedFiles,
              cache.newestFileMTime == newestFileMTime else {
            return nil
        }
        return cache.snapshot
    }

    private func saveDetailCache(snapshot: UsageDetailSnapshot, cacheKey: String, newestFileMTime: Date?) {
        let cache = UsageDetailCacheFile(
            cacheKey: cacheKey,
            newestFileMTime: newestFileMTime,
            scannedFiles: snapshot.scannedFiles,
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            recentDaily: snapshot.recentDaily.map { CachedDailyUsage(date: $0.0, aggregate: $0.1) },
            generatedAt: Date()
        )
        guard let data = try? JSONEncoder.codexHub.encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
