import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

struct CodexAccount: Codable, Equatable {
    let selector: String
    let identity: String
    let email: String
    let alias: String?
    let plan: String
    let fiveHourUsage: String
    let fiveHourUsedPercent: Int?
    let fiveHourQuotaKind: AppServerRateLimitWindow.Kind?
    let weeklyUsage: String
    let weeklyUsedPercent: Int?
    let weeklyQuotaKind: AppServerRateLimitWindow.Kind?
    let lastActivity: String
    let lastUsedAt: Date?
    let isActive: Bool

    init(
        selector: String,
        identity: String? = nil,
        email: String,
        alias: String? = nil,
        plan: String,
        fiveHourUsage: String,
        fiveHourUsedPercent: Int?,
        fiveHourQuotaKind: AppServerRateLimitWindow.Kind? = nil,
        weeklyUsage: String,
        weeklyUsedPercent: Int?,
        weeklyQuotaKind: AppServerRateLimitWindow.Kind? = nil,
        lastActivity: String,
        lastUsedAt: Date? = nil,
        isActive: Bool
    ) {
        self.selector = selector
        self.identity = identity ?? selector
        self.email = email
        self.alias = alias
        self.plan = plan
        self.fiveHourUsage = fiveHourUsage
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.fiveHourQuotaKind = fiveHourQuotaKind
        self.weeklyUsage = weeklyUsage
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyQuotaKind = weeklyQuotaKind
        self.lastActivity = lastActivity
        self.lastUsedAt = lastUsedAt
        self.isActive = isActive
    }

    var label: String {
        if let alias, alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return alias
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var planLabel: String? {
        let normalized = plan
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "chatgpt_", with: "")
            .replacingOccurrences(of: "chatgpt-", with: "")
        guard normalized.isEmpty == false, normalized != "unknown" else { return nil }
        if normalized.contains("education") || normalized.contains("edu") {
            return "edu"
        }
        if normalized.contains("enterprise") {
            return "ent"
        }
        if normalized.contains("team") || normalized.contains("business") {
            return "team"
        }
        if normalized.contains("plus") {
            return "plus"
        }
        if normalized.contains("pro") {
            return "pro"
        }
        if normalized.contains("go") {
            return "go"
        }
        if normalized.contains("free") {
            return "free"
        }
        return String(normalized.prefix(8))
    }

    var usagePercent: Int? {
        guard let used = fiveHourUsedPercent else { return nil }
        return max(0, min(100, used))
    }

    var primaryQuotaLabel: String {
        (fiveHourQuotaKind ?? .fiveHour).label
    }

    var secondaryQuotaLabel: String {
        (weeklyQuotaKind ?? .weekly).label
    }

    var shouldShowSecondaryQuota: Bool {
        weeklyUsedPercent != nil
    }

    var weeklyPercent: Int? {
        guard let used = weeklyUsedPercent else { return nil }
        return max(0, min(100, used))
    }

    func applyingAppServerRateLimits(_ limits: AppServerRateLimits) -> CodexAccount {
        let nextFiveHourQuotaKind = limits.primary?.displayKind(fallback: .fiveHour) ?? fiveHourQuotaKind
        let shouldClearSecondary = limits.secondary == nil && nextFiveHourQuotaKind == .monthly
        return CodexAccount(
            selector: selector,
            identity: identity,
            email: email,
            alias: alias,
            plan: limits.planType ?? plan,
            fiveHourUsage: limits.primary?.displayText(fallbackKind: .fiveHour) ?? fiveHourUsage,
            fiveHourUsedPercent: limits.primary?.displayPercent ?? fiveHourUsedPercent,
            fiveHourQuotaKind: nextFiveHourQuotaKind,
            weeklyUsage: limits.secondary?.displayText(fallbackKind: .weekly) ?? (shouldClearSecondary ? "-" : weeklyUsage),
            weeklyUsedPercent: limits.secondary?.displayPercent ?? (shouldClearSecondary ? nil : weeklyUsedPercent),
            weeklyQuotaKind: limits.secondary?.displayKind(fallback: .weekly) ?? (shouldClearSecondary ? nil : weeklyQuotaKind),
            lastActivity: lastActivity,
            lastUsedAt: lastUsedAt,
            isActive: isActive
        )
    }

    func settingActive(_ active: Bool) -> CodexAccount {
        CodexAccount(
            selector: selector,
            identity: identity,
            email: email,
            alias: alias,
            plan: plan,
            fiveHourUsage: fiveHourUsage,
            fiveHourUsedPercent: fiveHourUsedPercent,
            fiveHourQuotaKind: fiveHourQuotaKind,
            weeklyUsage: weeklyUsage,
            weeklyUsedPercent: weeklyUsedPercent,
            weeklyQuotaKind: weeklyQuotaKind,
            lastActivity: lastActivity,
            lastUsedAt: lastUsedAt,
            isActive: active
        )
    }

    func withUnavailableRateLimitsIfNeeded() -> CodexAccount {
        CodexAccount(
            selector: selector,
            identity: identity,
            email: email,
            alias: alias,
            plan: plan,
            fiveHourUsage: fiveHourUsedPercent == nil ? L.unavailable : fiveHourUsage,
            fiveHourUsedPercent: fiveHourUsedPercent,
            fiveHourQuotaKind: fiveHourQuotaKind,
            weeklyUsage: weeklyUsedPercent == nil || weeklyUsage == "-" ? L.unavailable : weeklyUsage,
            weeklyUsedPercent: weeklyUsedPercent,
            weeklyQuotaKind: weeklyQuotaKind,
            lastActivity: lastActivity,
            lastUsedAt: lastUsedAt,
            isActive: isActive
        )
    }
}

struct AppServerRateLimits: Codable {
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let planType: String?

    init(primary: AppServerRateLimitWindow?, secondary: AppServerRateLimitWindow?, planType: String? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

struct AppServerRateLimitWindow: Codable {
    enum Kind: String, Codable {
        case fiveHour
        case weekly
        case monthly
        case unknown

        var label: String {
            switch self {
            case .fiveHour: return "5h"
            case .weekly: return "1w"
            case .monthly: return "1mo"
            case .unknown: return "-"
            }
        }

        var usesDateReset: Bool {
            self != .fiveHour
        }

        static func inferred(windowDurationMinutes: Double?, resetsAt: Date?, observedAt: Date = Date(), fallback: Kind) -> Kind {
            if let windowDurationMinutes {
                if windowDurationMinutes >= 28 * 24 * 60 {
                    return .monthly
                }
                if windowDurationMinutes >= 6 * 24 * 60 {
                    return .weekly
                }
                if windowDurationMinutes > 0 {
                    return .fiveHour
                }
            }
            guard fallback == .unknown else { return fallback }
            guard let resetsAt else { return fallback }
            let remaining = resetsAt.timeIntervalSince(observedAt)
            guard remaining > 0 else { return fallback }
            if remaining >= 14 * 24 * 60 * 60 {
                return .monthly
            }
            if remaining >= 24 * 60 * 60 {
                return .weekly
            }
            return .fiveHour
        }
    }

    let displayPercent: Int
    let resetsAt: Date?
    let kind: Kind?
    let windowDurationMinutes: Double?

    init(displayPercent: Int, resetsAt: Date?, kind: Kind? = nil, windowDurationMinutes: Double? = nil) {
        self.displayPercent = displayPercent
        self.resetsAt = resetsAt
        self.kind = kind
        self.windowDurationMinutes = windowDurationMinutes
    }

    func displayKind(fallback: Kind) -> Kind {
        kind ?? Kind.inferred(windowDurationMinutes: windowDurationMinutes, resetsAt: resetsAt, fallback: fallback)
    }

    func displayText(fallbackKind: Kind) -> String {
        let displayKind = displayKind(fallback: fallbackKind)
        if let resetsAt {
            let reset = displayKind.usesDateReset ? Format.shortDate(resetsAt) : Format.time(resetsAt)
            return "\(displayPercent)% (\(reset))"
        }
        return "\(displayPercent)%"
    }
}

struct TokenTotals: Codable, Equatable, Hashable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    static let zero = TokenTotals(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0)

    init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, reasoningOutputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        let input = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        let cached = (try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens))
            ?? (legacyContainer.flatMap { try? $0.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) }) ?? 0
        let output = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        let reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens) ?? 0
        let total = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        self.init(inputTokens: input, cachedInputTokens: cached, outputTokens: output, reasoningOutputTokens: reasoning, totalTokens: total)
    }

    var billedInputTokens: Int {
        let normalizedInput = max(inputTokens, 0)
        let clampedCached = max(min(cachedInputTokens, normalizedInput), 0)
        return max(normalizedInput - clampedCached, 0)
    }

    var billingTokenTotal: Int {
        billedInputTokens + cachedInputTokens + outputTokens
    }

    var isZero: Bool {
        inputTokens == 0 && cachedInputTokens == 0 && outputTokens == 0 && reasoningOutputTokens == 0 && totalTokens == 0
    }

    func normalized() -> TokenTotals {
        let normalizedInput = max(inputTokens, 0)
        let clampedCached = max(min(cachedInputTokens, normalizedInput), 0)
        let normalizedOutput = max(outputTokens, 0)
        let normalizedReasoning = min(max(reasoningOutputTokens, 0), normalizedOutput)
        let fallbackTotal = normalizedInput + normalizedOutput
        let normalizedTotal = totalTokens > 0 ? totalTokens : fallbackTotal
        return TokenTotals(
            inputTokens: normalizedInput,
            cachedInputTokens: clampedCached,
            outputTokens: normalizedOutput,
            reasoningOutputTokens: normalizedReasoning,
            totalTokens: max(normalizedTotal, 0)
        )
    }

    func delta(since previous: TokenTotals) -> TokenTotals {
        TokenTotals(
            inputTokens: max(inputTokens - previous.inputTokens, 0),
            cachedInputTokens: max(cachedInputTokens - previous.cachedInputTokens, 0),
            outputTokens: max(outputTokens - previous.outputTokens, 0),
            reasoningOutputTokens: max(reasoningOutputTokens - previous.reasoningOutputTokens, 0),
            totalTokens: max(totalTokens - previous.totalTokens, 0)
        )
    }

    func adding(_ other: TokenTotals) -> TokenTotals {
        TokenTotals(
            inputTokens: inputTokens + other.inputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            outputTokens: outputTokens + other.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }
}

struct ModelRates: Codable, Equatable {
    let input: Double
    let cachedInput: Double?
    let output: Double

    var cachedInputRate: Double {
        cachedInput ?? input
    }
}

struct ModelPricingCatalog: Codable, Equatable {
    let defaultRates: ModelRates
    let models: [String: ModelRates]
    let aliases: [String: String]

    static let fallback = ModelPricingCatalog(
        defaultRates: ModelRates(input: 1.25, cachedInput: 0.125, output: 10.0),
        models: [:],
        aliases: [:]
    )

    static func load() -> ModelPricingCatalog {
        guard let url = priceBookURL(),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(PriceBook.self, from: data).catalog else {
            return .fallback
        }
        return catalog
    }

    private static func priceBookURL() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "PriceBook", withExtension: "json") {
            return url
        }
        if let url = Bundle.module.url(forResource: "PriceBook", withExtension: "json", subdirectory: "Resources") {
            return url
        }
        #endif
        return Bundle.main.url(forResource: "PriceBook", withExtension: "json")
    }

    func rates(for model: String?) -> ModelRates {
        guard let model, model.isEmpty == false else { return defaultRates }
        if let exact = models[model] { return exact }
        if let alias = aliases[model], let aliased = models[alias] { return aliased }
        return defaultRates
    }
}

private struct PriceBook: Decodable {
    let schema: Int
    let fallback: PricePoint
    let entries: [Entry]
    let alias: [Alias]

    var catalog: ModelPricingCatalog? {
        guard schema == 1 else { return nil }
        var models: [String: ModelRates] = [:]
        for entry in entries {
            let rates = entry.price.rates
            for model in entry.models {
                models[model] = rates
            }
        }
        return ModelPricingCatalog(
            defaultRates: fallback.rates,
            models: models,
            aliases: Dictionary(uniqueKeysWithValues: alias.map { ($0.from, $0.to) })
        )
    }

    struct Entry: Decodable {
        let models: [String]
        let price: PricePoint
    }

    struct Alias: Decodable {
        let from: String
        let to: String
    }
}

private struct PricePoint: Decodable {
    let inputPerMTok: Double
    let cachedInputPerMTok: Double?
    let outputPerMTok: Double

    var rates: ModelRates {
        ModelRates(input: inputPerMTok, cachedInput: cachedInputPerMTok, output: outputPerMTok)
    }
}

struct CostTotals: Codable, Equatable {
    let inputCost: Double
    let cachedInputCost: Double
    let outputCost: Double
    let reasoningCost: Double

    static let zero = CostTotals(inputCost: 0, cachedInputCost: 0, outputCost: 0, reasoningCost: 0)

    var totalCost: Double {
        inputCost + cachedInputCost + outputCost + reasoningCost
    }

    init(inputCost: Double, cachedInputCost: Double, outputCost: Double, reasoningCost: Double) {
        self.inputCost = inputCost
        self.cachedInputCost = cachedInputCost
        self.outputCost = outputCost
        self.reasoningCost = reasoningCost
    }

    init(totals: TokenTotals, rates: ModelRates) {
        let reasoningTokens = max(0, min(totals.reasoningOutputTokens, totals.outputTokens))
        let nonReasoningOutputTokens = max(totals.outputTokens - reasoningTokens, 0)
        self.inputCost = Double(totals.billedInputTokens) * rates.input / 1_000_000.0
        self.cachedInputCost = Double(totals.cachedInputTokens) * rates.cachedInputRate / 1_000_000.0
        self.outputCost = Double(nonReasoningOutputTokens) * rates.output / 1_000_000.0
        self.reasoningCost = Double(reasoningTokens) * rates.output / 1_000_000.0
    }

    func adding(_ other: CostTotals) -> CostTotals {
        CostTotals(
            inputCost: inputCost + other.inputCost,
            cachedInputCost: cachedInputCost + other.cachedInputCost,
            outputCost: outputCost + other.outputCost,
            reasoningCost: reasoningCost + other.reasoningCost
        )
    }
}

struct UsageAggregate: Codable, Equatable {
    let totals: TokenTotals
    let costs: CostTotals

    static let zero = UsageAggregate(totals: .zero, costs: .zero)

    var billingTokenTotal: Int {
        totals.billingTokenTotal
    }

    var isZero: Bool {
        totals.isZero && costs.totalCost == 0
    }

    func adding(_ other: UsageAggregate) -> UsageAggregate {
        UsageAggregate(totals: totals.adding(other.totals), costs: costs.adding(other.costs))
    }
}

struct AccountUsageSummary {
    let email: String
    let aggregate: UsageAggregate
}

struct UsageSnapshot {
    let today: UsageAggregate
    let todayByAccount: [String: UsageAggregate]
    let recentDaily: [(Date, UsageAggregate)]
    let scannedFiles: Int
    let lastError: String?
}

struct UsageDetailSnapshot {
    let today: UsageAggregate
    let week: UsageAggregate
    let month: UsageAggregate
    let weekByAccount: [String: UsageAggregate]
    let monthByAccount: [String: UsageAggregate]
    let recentDaily: [(Date, UsageAggregate)]
    let scannedFiles: Int
    let lastError: String?
}

struct DashboardSnapshot {
    let total: UsageAggregate
    let dailySeries: [DashboardSeriesPoint]
    let accountBreakdown: [DashboardBreakdown]
    let modelBreakdown: [DashboardBreakdown]
    let activitySeries: [DashboardSeriesPoint]
    let calendarHeatmap: [DashboardHeatmapDay]
    let scannedFiles: Int
    let lastUpdatedAt: Date?

    static let empty = DashboardSnapshot(
        total: .zero,
        dailySeries: [],
        accountBreakdown: [],
        modelBreakdown: [],
        activitySeries: [],
        calendarHeatmap: [],
        scannedFiles: 0,
        lastUpdatedAt: nil
    )

    var isEmpty: Bool {
        total.isZero && dailySeries.allSatisfy { $0.aggregate.isZero }
    }
}

struct DashboardSeriesPoint: Identifiable, Equatable {
    let date: Date
    let aggregate: UsageAggregate

    var id: Date { date }
}

struct DashboardBreakdown: Identifiable, Equatable {
    let label: String
    let aggregate: UsageAggregate

    var id: String { label }
}

struct DashboardHeatmapDay: Identifiable, Equatable {
    let date: Date
    let aggregate: UsageAggregate

    var id: Date { date }
}

struct AttributionEvent: Codable, Equatable {
    let timestamp: Date
    let email: String
}

extension JSONDecoder {
    static var codexHub: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var codexHub: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

struct Format {
    static func percentUsed(_ used: Int?) -> String {
        guard let used else { return "--" }
        return "\(max(0, min(100, used)))%"
    }

    static func percentRemaining(fromUsed used: Int?) -> String {
        guard let remaining = remainingPercent(fromUsed: used) else { return "--" }
        return "\(remaining)%"
    }

    static func remainingPercent(fromUsed used: Int?) -> Int? {
        guard let used else { return nil }
        return max(0, min(100, 100 - used))
    }

    static func resetTime(from usage: String) -> String {
        guard let open = usage.firstIndex(of: "("), let close = usage.firstIndex(of: ")"), open < close else { return "--:--" }
        let inner = usage[usage.index(after: open)..<close]
        let parts = inner.split(separator: ":")
        guard parts.count >= 2 else { return String(inner) }
        return "\(parts[0]):\(parts[1].prefix(2))"
    }

    static func weeklyResetDate(from usage: String) -> String {
        guard let open = usage.firstIndex(of: "("), let close = usage.firstIndex(of: ")"), open < close else { return "--" }
        let inner = String(usage[usage.index(after: open)..<close])
        if let range = inner.range(of: " on ") {
            return normalizedWeeklyDate(String(inner[range.upperBound...]))
        }
        return normalizedWeeklyDate(inner)
    }

    static func quotaReset(from usage: String, kind: AppServerRateLimitWindow.Kind) -> String {
        kind.usesDateReset ? weeklyResetDate(from: usage) : resetTime(from: usage)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if AppLanguage.current == .korean {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "M월 d일"
        } else {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    static func chartAxisDate(_ date: Date, component: Calendar.Component = .day) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current == .korean ? Locale(identifier: "ko_KR") : Locale(identifier: "en_US_POSIX")
        switch component {
        case .month:
            formatter.dateFormat = AppLanguage.current == .korean ? "M월" : "MMM"
        default:
            formatter.dateFormat = AppLanguage.current == .korean ? "M월 d일" : "MMM d"
        }
        return formatter.string(from: date)
    }

    private static func normalizedWeeklyDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "--" }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/").compactMap { Int($0) }
            if parts.count == 2 {
                var components = Calendar.current.dateComponents([.year], from: Date())
                components.month = parts[0]
                components.day = parts[1]
                if let date = Calendar.current.date(from: components) {
                    return shortDate(date)
                }
            }
        }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        for format in ["d MMM", "MMM d", "d MMM yyyy", "yyyy-MM-dd"] {
            parser.dateFormat = format
            if let date = parser.date(from: trimmed) {
                return shortDate(date)
            }
        }

        return trimmed
    }

    static func tokens(_ value: Int) -> String {
        let absValue = abs(value)
        if AppLanguage.current == .english {
            if absValue >= 1_000_000_000 {
                return compact(Double(value) / 1_000_000_000.0, suffix: "b")
            }
            if absValue >= 1_000_000 {
                return compact(Double(value) / 1_000_000.0, suffix: "m")
            }
            if absValue >= 1_000 {
                return compact(Double(value) / 1_000.0, suffix: "k")
            }
            return "\(value)"
        }
        if absValue >= 100_000_000 {
            return compact(Double(value) / 100_000_000.0, suffix: "억")
        }
        if absValue >= 10_000 {
            return "\(Int((Double(value) / 10_000.0).rounded()))만"
        }
        if absValue >= 1_000 {
            return "\(Int((Double(value) / 1_000.0).rounded()))천"
        }
        return "\(value)"
    }

    static func preciseTokens(_ value: Int) -> String {
        let absValue = abs(value)
        if AppLanguage.current == .english {
            if absValue >= 1_000_000_000 {
                return fixedCompact(Double(value) / 1_000_000_000.0, suffix: "b", decimals: 2)
            }
            if absValue >= 1_000_000 {
                return fixedCompact(Double(value) / 1_000_000.0, suffix: "m", decimals: 2)
            }
            if absValue >= 1_000 {
                return fixedCompact(Double(value) / 1_000.0, suffix: "k", decimals: 1)
            }
            return "\(value)"
        }
        if absValue >= 100_000_000 {
            return fixedCompact(Double(value) / 100_000_000.0, suffix: "억", decimals: 2)
        }
        if absValue >= 10_000 {
            return fixedCompact(Double(value) / 10_000.0, suffix: "만", decimals: 1)
        }
        if absValue >= 1_000 {
            return fixedCompact(Double(value) / 1_000.0, suffix: "천", decimals: 1)
        }
        return "\(value)"
    }

    static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func summary(_ aggregate: UsageAggregate) -> String {
        "\(tokens(aggregate.billingTokenTotal)) · \(money(aggregate.costs.totalCost))"
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        if AppLanguage.current == .korean {
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일"
        } else {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return L.text(ko: "아직 업데이트되지 않음", en: "Not updated yet") }
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        if seconds < 60 { return L.text(ko: "방금 업데이트", en: "Updated just now") }
        let minutes = seconds / 60
        if minutes < 60 { return L.text(ko: "\(minutes)분 전 업데이트", en: "Updated \(minutes)m ago") }
        let hours = minutes / 60
        return L.text(ko: "\(hours)시간 전 업데이트", en: "Updated \(hours)h ago")
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let raw = String(format: "%.2f", value)
        let trimmed = raw
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return trimmed + suffix
    }
}

private extension Format {
    static func fixedCompact(_ value: Double, suffix: String, decimals: Int) -> String {
        let format = "%.\(decimals)f"
        var text = String(format: format, value)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return "\(text)\(suffix)"
    }
}
