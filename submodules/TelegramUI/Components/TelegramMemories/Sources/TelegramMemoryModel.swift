import Foundation

// The day a memory comes from, as a range of timestamps. It is a whole local calendar day, so it is not always 24 hours.
public struct TelegramMemoryWindow: Equatable {
    public let yearsAgo: Int
    public let start: Int32
    public let end: Int32

    public init(yearsAgo: Int, start: Int32, end: Int32) {
        self.yearsAgo = yearsAgo
        self.start = start
        self.end = end
    }

    public func contains(_ timestamp: Int32) -> Bool {
        return timestamp >= self.start && timestamp <= self.end
    }
}

public enum TelegramMemoryCalendar {
    // Telegram launched in 2013, so ten years reaches back to its earliest chats for a long time to come.
    public static let maxYears = 10

    // Today's date in each earlier year. A 29 February falls on 28 February in a year without one.
    public static func windows(now: Date, calendar: Calendar, maxYears: Int = TelegramMemoryCalendar.maxYears) -> [TelegramMemoryWindow] {
        var result: [TelegramMemoryWindow] = []
        for years in 1 ... max(1, maxYears) {
            guard let day = calendar.date(byAdding: .year, value: -years, to: now) else {
                continue
            }
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                continue
            }
            result.append(TelegramMemoryWindow(yearsAgo: years, start: Int32(start.timeIntervalSince1970), end: Int32(end.timeIntervalSince1970) - 1))
        }
        return result
    }

    public static func yearsAgo(timestamp: Int32, windows: [TelegramMemoryWindow]) -> Int? {
        return windows.first(where: { $0.contains(timestamp) })?.yearsAgo
    }

    // Identifies a local day, so a memory hidden for today comes back tomorrow.
    public static func dayKey(now: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

// One chat's photos and videos from one earlier year.
public struct TelegramMemoryCandidate: Equatable {
    public let key: Int64
    public let yearsAgo: Int
    public let itemCount: Int

    public init(key: Int64, yearsAgo: Int, itemCount: Int) {
        self.key = key
        self.yearsAgo = yearsAgo
        self.itemCount = itemCount
    }
}

public enum TelegramMemoryRanking {
    // A memory shows at most this many photos, so a busy day stays a glance rather than an album.
    public static let maxItems = 10

    // The day with the most photos comes first. On a tie the older day wins, because it is the rarer memory.
    public static func sorted(_ candidates: [TelegramMemoryCandidate]) -> [TelegramMemoryCandidate] {
        return candidates.sorted { lhs, rhs in
            let lhsCount = min(lhs.itemCount, self.maxItems)
            let rhsCount = min(rhs.itemCount, self.maxItems)
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            if lhs.yearsAgo != rhs.yearsAgo {
                return lhs.yearsAgo > rhs.yearsAgo
            }
            return lhs.key < rhs.key
        }
    }
}
