import Foundation

/// Reads the 5-hour / weekly rate-limit percentages Claude Desktop already
/// tracks for its own "Plan usage" panel, so Nudge can surface the same
/// numbers in the menu bar without polling any API itself.
///
/// Idea borrowed from claude-menubar-buddy (github.com/spyza008), which
/// reflects these same percentages as its pet's mood. We don't have a mood
/// system, so this surfaces as plain text in the menu instead.
enum UsageStats {
    struct Snapshot {
        let fiveHourPct: Int?
        let weeklyPct: Int?
    }

    private static let planUsageURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

    /// `nil` fields (not a missing file) mean: file exists but the most
    /// recent sample didn't include that number — still show what we have
    /// rather than hiding the whole menu row.
    static func snapshot() -> Snapshot {
        guard
            let data = try? Data(contentsOf: planUsageURL),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let samples = obj["samples"] as? [[String: Any]],
            let last = samples.last,
            let u = last["u"] as? [String: Any]
        else {
            return Snapshot(fiveHourPct: nil, weeklyPct: nil)
        }
        return Snapshot(fiveHourPct: u["fh"] as? Int, weeklyPct: u["sd"] as? Int)
    }

    static func menuTitle(for snapshot: Snapshot) -> String {
        guard snapshot.fiveHourPct != nil || snapshot.weeklyPct != nil else {
            return "Usage: unavailable"
        }
        let fh = snapshot.fiveHourPct.map { "\($0)%" } ?? "—"
        let sd = snapshot.weeklyPct.map { "\($0)%" } ?? "—"
        return "Usage — 5h: \(fh) · Weekly: \(sd)"
    }
}
