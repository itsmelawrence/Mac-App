import Foundation

/// Alert IDs already notified or spoken, oldest first, so the oldest are forgotten first.
/// (A `Set` has no order, so trimming it dropped arbitrary IDs and old alerts repeated.)
struct RecentAlertIDs {
    let key: String
    var defaults: UserDefaults = .standard
    var limit = 500

    func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func remember(_ ids: [String]) {
        var recent = load()
        for id in ids where !recent.contains(id) { recent.append(id) }
        defaults.set(Array(recent.suffix(limit)), forKey: key)
    }
}
