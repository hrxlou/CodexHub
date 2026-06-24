import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

struct CodexAccount: Codable, Equatable {
    let selector: String
    let email: String
    let plan: String
    let fiveHourUsage: String
    let fiveHourUsedPercent: Int?
    let weeklyUsage: String
    let weeklyUsedPercent: Int?
    let lastActivity: String
    let isActive: Bool

    var label: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var usagePercent: Int? {
        guard let used = fiveHourUsedPercent else { return nil }
        return max(0, min(100, used))
    }

    var weeklyPercent: Int? {
        guard let used = weeklyUsedPercent else { return nil }
        return max(0, min(100, used))
    }

    func applyingAppServerRateLimits(_ limits: AppServerRateLimits) -> CodexAccount {
        CodexAccount(
            selector: selector,
            email: email,
            plan: plan,
            fiveHourUsage: limits.primary?.displayText(kind: .fiveHour) ?? fiveHourUsage,
            fiveHourUsedPercent: limits.primary?.displayPercent ?? fiveHourUsedPercent,
            weeklyUsage: limits.secondary?.displayText(kind: .weekly) ?? weeklyUsage,
            weeklyUsedPercent: limits.secondary?.displayPercent ?? weeklyUsedPercent,
            lastActivity: lastActivity,
            isActive: isActive
        )
    }

    func settingActive(_ active: Bool) -> CodexAccount {
        CodexAccount(
            selector: selector,
            email: email,
            plan: plan,
            fiveHourUsage: fiveHourUsage,
            fiveHourUsedPercent: fiveHourUsedPercent,
            weeklyUsage: weeklyUsage,
            weeklyUsedPercent: weeklyUsedPercent,
            lastActivity: lastActivity,
            isActive: active
        )
    }

    func withUnavailableRateLimitsIfNeeded() -> CodexAccount {
        CodexAccount(
            selector: selector,
            email: email,
            plan: plan,
            fiveHourUsage: fiveHourUsedPercent == nil ? "Unavailable" : fiveHourUsage,
            fiveHourUsedPercent: fiveHourUsedPercent,
            weeklyUsage: weeklyUsedPercent == nil || weeklyUsage == "-" ? "Unavailable" : weeklyUsage,
            weeklyUsedPercent: weeklyUsedPercent,
            lastActivity: lastActivity,
            isActive: isActive
        )
    }
}

struct AppServerRateLimits: Codable {
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
}

struct AppServerRateLimitWindow: Codable {
    enum Kind {
        case fiveHour
        case weekly
    }

    let displayPercent: Int
    let resetsAt: Date?

    func displayText(kind: Kind) -> String {
        if let resetsAt {
            let reset = kind == .weekly ? Format.shortDate(resetsAt) : Format.time(resetsAt)
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
        billedInputTokens + cachedInputTokens + outputTokens + reasoningOutputTokens
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
        guard let url = Bundle.main.url(forResource: "PriceBook", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(PriceBook.self, from: data).catalog else {
            return .fallback
        }
        return catalog
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
        self.inputCost = Double(totals.billedInputTokens) * rates.input / 1_000_000.0
        self.cachedInputCost = Double(totals.cachedInputTokens) * rates.cachedInputRate / 1_000_000.0
        self.outputCost = Double(totals.outputTokens) * rates.output / 1_000_000.0
        self.reasoningCost = Double(totals.reasoningOutputTokens) * rates.output / 1_000_000.0
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
            formatter.dateFormat = "d MMM"
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
        guard let date else { return L.text(ko: "업데이트 --", en: "Updated --") }
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        if seconds < 5 { return L.text(ko: "방금 업데이트됨", en: "Updated just now") }
        if seconds < 60 { return L.text(ko: "\(seconds)초 전 업데이트됨", en: "Updated \(seconds)s ago") }
        let minutes = seconds / 60
        if minutes < 60 { return L.text(ko: "\(minutes)분 전 업데이트됨", en: "Updated \(minutes)m ago") }
        let hours = minutes / 60
        return L.text(ko: "\(hours)시간 전 업데이트됨", en: "Updated \(hours)h ago")
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let raw = String(format: "%.2f", value)
        let trimmed = raw
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return trimmed + suffix
    }
}
