import Foundation

struct UsageWindow: Codable, Equatable {
    let utilization: Double?
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// One entry of the API's `limits` array — per-model weekly limits
/// (e.g. Fable) arrive here as `kind == "weekly_scoped"`.
struct UsageLimit: Codable, Equatable {
    struct Scope: Codable, Equatable {
        struct Model: Codable, Equatable {
            let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        let model: Model?
    }

    let kind: String?
    let percent: Double?
    let resetsAt: Date?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind, percent, scope
        case resetsAt = "resets_at"
    }
}

struct UsageSnapshot: Codable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let limits: [UsageLimit]?
    var fetchedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
        case fetchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try c.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try c.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try c.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        limits = try c.decodeIfPresent([UsageLimit].self, forKey: .limits)
        fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
    }

    init(fiveHour: UsageWindow?, sevenDay: UsageWindow?,
         sevenDayOpus: UsageWindow?, sevenDaySonnet: UsageWindow?,
         limits: [UsageLimit]? = nil,
         fetchedAt: Date = Date()) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.limits = limits
        self.fetchedAt = fetchedAt
    }

    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 15 * 60 }

    /// Weekly per-model limits (e.g. Fable) from the `limits` array,
    /// falling back to the legacy seven_day_* fields on older payloads.
    var weeklyModelWindows: [(name: String, window: UsageWindow)] {
        let scoped = (limits ?? []).compactMap { limit -> (String, UsageWindow)? in
            guard limit.kind == "weekly_scoped",
                  let name = limit.scope?.model?.displayName,
                  let percent = limit.percent else { return nil }
            return (name, UsageWindow(utilization: percent, resetsAt: limit.resetsAt))
        }
        if !scoped.isEmpty { return scoped }

        var legacy: [(String, UsageWindow)] = []
        if let opus = sevenDayOpus, opus.utilization != nil { legacy.append(("Opus", opus)) }
        if let sonnet = sevenDaySonnet, sonnet.utilization != nil { legacy.append(("Sonnet", sonnet)) }
        return legacy
    }

    static var placeholder: UsageSnapshot {
        UsageSnapshot(
            fiveHour: UsageWindow(utilization: 33, resetsAt: Date().addingTimeInterval(3600 * 2)),
            sevenDay: UsageWindow(utilization: 13, resetsAt: Date().addingTimeInterval(86400 * 3)),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            limits: [
                UsageLimit(
                    kind: "weekly_scoped",
                    percent: 7,
                    resetsAt: Date().addingTimeInterval(86400 * 3),
                    scope: .init(model: .init(displayName: "Fable"))
                )
            ]
        )
    }
}

enum UsageDateParsing {
    /// Decoder for the API payload: `resets_at` is ISO 8601 with fractional seconds.
    static func makeAPIDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            if let s = try? container.decode(String.self) {
                if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(s)")
            }
            let t = try container.decode(Double.self)
            return Date(timeIntervalSince1970: t)
        }
        return decoder
    }
}
