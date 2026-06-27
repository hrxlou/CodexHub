import Foundation

struct AppServerRateLimitParser {
    private struct AppServerResponse: Decodable {
        let id: Int?
        let result: AppServerRateLimitResult?
    }

    private struct AppServerRateLimitResult: Decodable {
        let rateLimits: AppServerRateLimitSnapshot?
        let rateLimitsByLimitId: [String: AppServerRateLimitSnapshot]?
    }

    private struct AppServerRateLimitSnapshot: Decodable {
        let primary: AppServerRateLimitWindowPayload?
        let secondary: AppServerRateLimitWindowPayload?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case primary
            case secondary
            case planType
            case planTypeSnake = "plan_type"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primary = try container.decodeIfPresent(AppServerRateLimitWindowPayload.self, forKey: .primary)
            secondary = try container.decodeIfPresent(AppServerRateLimitWindowPayload.self, forKey: .secondary)
            planType = try container.decodeIfPresent(String.self, forKey: .planType)
                ?? container.decodeIfPresent(String.self, forKey: .planTypeSnake)
        }
    }

    static func parseJSONRPCLine(_ line: String) -> AppServerRateLimits? {
        guard let data = line.data(using: .utf8),
              let response = try? JSONDecoder().decode(AppServerResponse.self, from: data),
              response.id == 2 else { return nil }
        let snapshot = response.result?.rateLimitsByLimitId?["codex"] ?? response.result?.rateLimits
        guard let snapshot else { return nil }
        return AppServerRateLimits(
            primary: snapshot.primary.map { makeWindow($0, fallbackKind: .fiveHour) },
            secondary: snapshot.secondary.map { makeWindow($0, fallbackKind: .weekly) },
            planType: snapshot.planType
        )
    }

    static func makeWindow(
        _ payload: AppServerRateLimitWindowPayload,
        fallbackKind: AppServerRateLimitWindow.Kind
    ) -> AppServerRateLimitWindow {
        let used = Int(payload.usedPercent.rounded())
        let clampedUsed = max(0, min(100, used))
        let reset = payload.resetsAt.map { Date(timeIntervalSince1970: $0) }
        return AppServerRateLimitWindow(
            displayPercent: clampedUsed,
            resetsAt: reset,
            kind: AppServerRateLimitWindow.Kind.inferred(
                windowDurationMinutes: payload.windowDurationMins,
                resetsAt: reset,
                fallback: fallbackKind
            ),
            windowDurationMinutes: payload.windowDurationMins
        )
    }
}

struct AppServerRateLimitWindowPayload: Decodable {
    let usedPercent: Double
    let resetsAt: Double?
    let windowDurationMins: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case resetsAt
        case windowDurationMins
        case usedPercentSnake = "used_percent"
        case resetsAtSnake = "resets_at"
        case windowDurationMinsSnake = "window_duration_mins"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
            ?? container.decode(Double.self, forKey: .usedPercentSnake)
        resetsAt = try container.decodeIfPresent(Double.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Double.self, forKey: .resetsAtSnake)
        windowDurationMins = try container.decodeIfPresent(Double.self, forKey: .windowDurationMins)
            ?? container.decodeIfPresent(Double.self, forKey: .windowDurationMinsSnake)
    }
}
