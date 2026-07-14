import Foundation

/// Shares the latest snapshot between the menu bar app and the widget
/// via an App Group container.
enum UsageStore {
    static let appGroup = "group.dev.prongbang.claudelimit"
    private static let key = "usage_snapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> UsageSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
