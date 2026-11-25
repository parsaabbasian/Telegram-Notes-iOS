import XCTest

final class TelegramMemoryModelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        return self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func start(_ window: TelegramMemoryWindow) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(window.start))
    }

    func testWindowsCoverTheSameLocalDayInEachEarlierYear() {
        let windows = TelegramMemoryCalendar.windows(now: self.date(2026, 11, 24, 9), calendar: self.calendar, maxYears: 3)
        XCTAssertEqual(windows.map(\.yearsAgo), [1, 2, 3])
        XCTAssertEqual(self.start(windows[0]), self.date(2025, 11, 24, 0))
        XCTAssertEqual(self.start(windows[2]), self.date(2023, 11, 24, 0))
        XCTAssertEqual(windows[0].end - windows[0].start, 24 * 3600 - 1)
    }

    func testLeapDayFallsOnTheTwentyEighthInOtherYears() {
        let windows = TelegramMemoryCalendar.windows(now: self.date(2028, 2, 29), calendar: self.calendar, maxYears: 4)
        XCTAssertEqual(self.start(windows[0]), self.date(2027, 2, 28, 0))
        XCTAssertEqual(self.start(windows[3]), self.date(2024, 2, 29, 0))
    }

    func testDaylightSavingDayIsTwentyFiveHours() {
        // Clocks in Rome went back an hour on 26 October 2025.
        let windows = TelegramMemoryCalendar.windows(now: self.date(2026, 10, 26), calendar: self.calendar, maxYears: 1)
        XCTAssertEqual(windows[0].end - windows[0].start, 25 * 3600 - 1)
    }

    func testYearsAgoFindsTheWindowAndIgnoresOtherDays() {
        let windows = TelegramMemoryCalendar.windows(now: self.date(2026, 11, 24), calendar: self.calendar, maxYears: 5)
        let evening = Int32(self.date(2023, 11, 24, 23).timeIntervalSince1970)
        let nextMorning = Int32(self.date(2023, 11, 25, 0).timeIntervalSince1970)
        XCTAssertEqual(TelegramMemoryCalendar.yearsAgo(timestamp: evening, windows: windows), 3)
        XCTAssertNil(TelegramMemoryCalendar.yearsAgo(timestamp: nextMorning, windows: windows))
    }

    func testDayKey() {
        XCTAssertEqual(TelegramMemoryCalendar.dayKey(now: self.date(2026, 1, 5), calendar: self.calendar), "2026-01-05")
    }

    func testRankingPrefersMorePhotosThenOlderDays() {
        let ranked = TelegramMemoryRanking.sorted([
            TelegramMemoryCandidate(key: 1, yearsAgo: 1, itemCount: 2),
            TelegramMemoryCandidate(key: 2, yearsAgo: 3, itemCount: 4),
            TelegramMemoryCandidate(key: 3, yearsAgo: 5, itemCount: 2),
            TelegramMemoryCandidate(key: 4, yearsAgo: 2, itemCount: 40)
        ])
        XCTAssertEqual(ranked.map(\.key), [4, 2, 3, 1])
    }

    func testRankingCountsAtMostTheItemsAMemoryShows() {
        let ranked = TelegramMemoryRanking.sorted([
            TelegramMemoryCandidate(key: 1, yearsAgo: 1, itemCount: 60),
            TelegramMemoryCandidate(key: 2, yearsAgo: 4, itemCount: 12)
        ])
        XCTAssertEqual(ranked.map(\.key), [2, 1])
    }
}
