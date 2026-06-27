import Foundation

struct UsageHistoryRow: Codable, Equatable {
    let date: Date
    let accountEmail: String
    let model: String
    let totals: TokenTotals
    let costs: CostTotals
    let updatedAt: Date

    var aggregate: UsageAggregate {
        UsageAggregate(totals: totals, costs: costs)
    }

    func adding(_ other: UsageHistoryRow, updatedAt: Date) -> UsageHistoryRow {
        UsageHistoryRow(
            date: date,
            accountEmail: accountEmail,
            model: model,
            totals: totals.adding(other.totals),
            costs: costs.adding(other.costs),
            updatedAt: updatedAt
        )
    }
}

final class UsageHistoryStore {
    private struct HistoryFile: Codable {
        var version: Int
        var savedAt: Date
        var rows: [UsageHistoryRow]
    }

    private struct RowKey: Hashable {
        let day: Date
        let accountEmail: String
        let model: String
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar
    private let retentionDays: Int
    private let lock = NSLock()

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        retentionDays: Int = 365
    ) {
        let appSupport = LocalStorageSecurity.codexHubApplicationSupportDirectory()
        self.fileURL = fileURL ?? appSupport.appendingPathComponent("usage-history-v1.json")
        self.fileManager = fileManager
        self.calendar = calendar
        self.retentionDays = retentionDays
        if fileManager.fileExists(atPath: self.fileURL.path) {
            try? LocalStorageSecurity.setPrivateFilePermissions(self.fileURL)
        }
    }

    var storageURL: URL {
        fileURL
    }

    func replaceRows(_ rows: [UsageHistoryRow], now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = retentionStart(endingAt: now)
        let merged = mergeRows(rows, cutoff: cutoff, updatedAt: now)
        saveLocked(merged, now: now)
    }

    func loadRows(now: Date = Date()) -> [UsageHistoryRow] {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = retentionStart(endingAt: now)
        let loaded = loadLocked()
        let rows = loaded.filter { $0.date >= cutoff }
        if rows.count != loaded.count {
            saveLocked(rows, now: now)
        }
        return rows.sorted { left, right in
            if left.date != right.date { return left.date < right.date }
            if left.accountEmail != right.accountEmail { return left.accountEmail < right.accountEmail }
            return left.model < right.model
        }
    }

    func makeSnapshot(days: Int, now: Date = Date(), scannedFiles: Int = 0) -> DashboardSnapshot {
        let rows = loadRows(now: now)
        return makeSnapshot(from: rows, days: days, now: now, scannedFiles: scannedFiles)
    }

    func makeSnapshot(
        from rows: [UsageHistoryRow],
        days: Int,
        now: Date = Date(),
        scannedFiles: Int = 0
    ) -> DashboardSnapshot {
        let dayCount = max(1, days)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let filtered = rows.filter { $0.date >= start && $0.date <= today }

        var total: UsageAggregate = .zero
        var daily: [Date: UsageAggregate] = [:]
        var byAccount: [String: UsageAggregate] = [:]
        var byModel: [String: UsageAggregate] = [:]

        for row in filtered {
            let day = calendar.startOfDay(for: row.date)
            let aggregate = row.aggregate
            total = total.adding(aggregate)
            daily[day] = (daily[day] ?? .zero).adding(aggregate)
            byAccount[row.accountEmail] = (byAccount[row.accountEmail] ?? .zero).adding(aggregate)
            byModel[row.model] = (byModel[row.model] ?? .zero).adding(aggregate)
        }

        let dailySeries = (0..<dayCount).compactMap { offset -> DashboardSeriesPoint? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DashboardSeriesPoint(date: date, aggregate: daily[date] ?? .zero)
        }
        let calendarHeatmap = Array(dailySeries.suffix(30)).map {
            DashboardHeatmapDay(date: $0.date, aggregate: $0.aggregate)
        }

        return DashboardSnapshot(
            total: total,
            dailySeries: dailySeries,
            accountBreakdown: breakdown(from: byAccount),
            modelBreakdown: breakdown(from: byModel),
            activitySeries: [],
            calendarHeatmap: calendarHeatmap,
            scannedFiles: scannedFiles,
            lastUpdatedAt: filtered.map(\.updatedAt).max()
        )
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
    }

    private func retentionStart(endingAt now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(retentionDays - 1), to: today) ?? today
    }

    private func mergeRows(_ rows: [UsageHistoryRow], cutoff: Date, updatedAt: Date) -> [UsageHistoryRow] {
        var merged: [RowKey: UsageHistoryRow] = [:]
        for row in rows where row.date >= cutoff {
            let key = RowKey(
                day: calendar.startOfDay(for: row.date),
                accountEmail: normalized(row.accountEmail, fallback: "Unknown"),
                model: normalized(row.model, fallback: "Unknown")
            )
            let normalizedRow = UsageHistoryRow(
                date: key.day,
                accountEmail: key.accountEmail,
                model: key.model,
                totals: row.totals,
                costs: row.costs,
                updatedAt: updatedAt
            )
            if let existing = merged[key] {
                merged[key] = existing.adding(normalizedRow, updatedAt: updatedAt)
            } else {
                merged[key] = normalizedRow
            }
        }
        return merged.values.sorted { left, right in
            if left.date != right.date { return left.date < right.date }
            if left.accountEmail != right.accountEmail { return left.accountEmail < right.accountEmail }
            return left.model < right.model
        }
    }

    private func loadLocked() -> [UsageHistoryRow] {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder.codexHub.decode(HistoryFile.self, from: data),
              history.version == 1 else {
            return []
        }
        return history.rows
    }

    private func saveLocked(_ rows: [UsageHistoryRow], now: Date) {
        let history = HistoryFile(version: 1, savedAt: now, rows: rows)
        guard let data = try? JSONEncoder.codexHub.encode(history) else { return }
        try? LocalStorageSecurity.writePrivateFileAtomically(data, to: fileURL)
    }

    private func breakdown(from values: [String: UsageAggregate]) -> [DashboardBreakdown] {
        values
            .map { DashboardBreakdown(label: $0.key, aggregate: $0.value) }
            .sorted { left, right in
                if left.aggregate.billingTokenTotal != right.aggregate.billingTokenTotal {
                    return left.aggregate.billingTokenTotal > right.aggregate.billingTokenTotal
                }
                if left.aggregate.costs.totalCost != right.aggregate.costs.totalCost {
                    return left.aggregate.costs.totalCost > right.aggregate.costs.totalCost
                }
                return left.label < right.label
            }
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
