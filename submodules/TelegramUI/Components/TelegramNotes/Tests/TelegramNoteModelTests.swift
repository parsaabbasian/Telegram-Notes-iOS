import XCTest

final class TelegramNoteModelTests: XCTestCase {
    func testCaptionRoundTrip() {
        XCTAssertEqual(TelegramNoteCaption.noteText(caption: TelegramNoteCaption.caption(text: "Coffee ☕️")), "Coffee ☕️")
        XCTAssertNil(TelegramNoteCaption.noteText(caption: "An ordinary Story"))
        XCTAssertNil(TelegramNoteCaption.noteText(caption: TelegramNoteCaption.prefix + "   "))
    }

    func testValidationTrimsAndEnforcesTheLimit() {
        XCTAssertEqual(TelegramNoteCaption.validated("  Hi \n"), "Hi")
        XCTAssertNil(TelegramNoteCaption.validated("   "))
        XCTAssertNotNil(TelegramNoteCaption.validated(String(repeating: "a", count: 80)))
        XCTAssertNil(TelegramNoteCaption.validated(String(repeating: "a", count: 81)))
        // A family emoji is one character on screen but eleven UTF-16 units.
        XCTAssertEqual(TelegramNoteCaption.length("👨‍👩‍👧‍👦"), 11)
    }

    func testPollPercentagesAlwaysAddUpTo100() {
        for votes in [[1, 2], [1, 1, 1], [0, 0], [14, 9], [2, 3, 5, 7], [1, 0], [333, 333, 334]] {
            let poll = TelegramNotePoll(options: votes.map { "\($0)" }, votes: votes)
            let sum = poll.percentages.reduce(0, +)
            XCTAssertEqual(sum, poll.totalVotes == 0 ? 0 : 100, "votes \(votes)")
        }
        XCTAssertEqual(TelegramNotePoll(options: ["a", "b"], votes: [14, 9]).percentages, [61, 39])
    }

    func testVoteCountsOnceAndStaysChosen() {
        var poll = TelegramNotePoll(options: ["a", "b"], votes: [1, 1])
        poll = poll.voted(index: 1)
        XCTAssertEqual(poll.votes, [1, 2])
        XCTAssertEqual(poll.chosenIndex, 1)
        XCTAssertEqual(poll.voted(index: 0), poll)
        XCTAssertEqual(TelegramNotePoll(options: ["a"], votes: [0]).voted(index: 5).votes, [0])
    }

    func testPollOptionsNeedTwoDifferentAnswers() {
        XCTAssertTrue(TelegramNoteOptions().isValid)
        XCTAssertTrue(TelegramNoteOptions(pollOptions: ["Tea", "Coffee"]).isValid)
        XCTAssertFalse(TelegramNoteOptions(pollOptions: ["Tea", " "]).isValid)
        XCTAssertFalse(TelegramNoteOptions(pollOptions: ["Tea", " Tea "]).isValid)
        XCTAssertFalse(TelegramNoteOptions(pollOptions: ["Tea"]).isValid)
        XCTAssertEqual(TelegramNoteOptions(pollOptions: [" Tea ", "Coffee"]).poll?.options, ["Tea", "Coffee"])
    }

    func testTimerFractionAndLabel() {
        XCTAssertEqual(TelegramNoteTimer.fractionLeft(timestamp: 0, expiration: 100, now: 0), 1.0)
        XCTAssertEqual(TelegramNoteTimer.fractionLeft(timestamp: 0, expiration: 100, now: 25), 0.75)
        XCTAssertEqual(TelegramNoteTimer.fractionLeft(timestamp: 0, expiration: 100, now: 500), 0.0)
        XCTAssertEqual(TelegramNoteTimer.fractionLeft(timestamp: 10, expiration: 10, now: 10), 0.0)
        XCTAssertEqual(TelegramNoteTimer.left(expiration: 7200, now: 0), .hours(2))
        XCTAssertEqual(TelegramNoteTimer.left(expiration: 3601, now: 0), .hours(2))
        XCTAssertEqual(TelegramNoteTimer.left(expiration: 3599, now: 0), .minutes(60))
        XCTAssertEqual(TelegramNoteTimer.left(expiration: 10, now: 0), .minutes(1))
        XCTAssertEqual(TelegramNoteTimer.left(expiration: 0, now: 100), .minutes(1))
    }
}
