import Foundation
import CoreGraphics

// The parts of a Note that need no UI, kept apart so they can be tested on the host.

public struct TelegramNotePoll: Equatable {
    public var options: [String]
    public var votes: [Int]
    public var chosenIndex: Int?

    public init(options: [String], votes: [Int], chosenIndex: Int? = nil) {
        self.options = options
        self.votes = votes
        self.chosenIndex = chosenIndex
    }

    public var totalVotes: Int {
        return self.votes.reduce(0, +)
    }

    // Whole percentages that always add up to 100: the largest remainders take the rounding.
    public var percentages: [Int] {
        let total = self.totalVotes
        if total == 0 {
            return self.votes.map { _ in 0 }
        }
        var result = self.votes.map { $0 * 100 / total }
        let remainders = self.votes.enumerated().sorted { lhs, rhs in
            return lhs.element * 100 % total > rhs.element * 100 % total
        }
        var missing = 100 - result.reduce(0, +)
        for (index, _) in remainders where missing > 0 {
            result[index] += 1
            missing -= 1
        }
        return result
    }

    public func voted(index: Int) -> TelegramNotePoll {
        guard self.chosenIndex == nil, self.votes.indices.contains(index) else {
            return self
        }
        var result = self
        result.votes[index] += 1
        result.chosenIndex = index
        return result
    }
}

public enum TelegramNoteAudience: Equatable {
    case contacts
    case closeFriends
    case folder(id: Int32, title: String)
}

public struct TelegramNoteOptions: Equatable {
    public static let periods: [Int32] = [1 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60, 72 * 60 * 60]
    public static let maxPollOptionLength = 24

    public var period: Int32
    public var isSpoiler: Bool
    public var pollOptions: [String]?
    public var audience: TelegramNoteAudience

    public init(period: Int32 = TelegramNoteCaption.period, isSpoiler: Bool = false, pollOptions: [String]? = nil, audience: TelegramNoteAudience = .contacts) {
        self.period = period
        self.isSpoiler = isSpoiler
        self.pollOptions = pollOptions
        self.audience = audience
    }

    // A poll needs two different answers; a Note without a poll is always fine.
    public var isValid: Bool {
        guard let pollOptions else {
            return true
        }
        let trimmed = pollOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmed.count == 2 && !trimmed.contains(where: { $0.isEmpty }) && trimmed[0] != trimmed[1]
    }

    public var poll: TelegramNotePoll? {
        return self.pollOptions.map { options in
            let trimmed = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return TelegramNotePoll(options: trimmed, votes: trimmed.map { _ in 0 })
        }
    }
}

public enum TelegramNoteTimer {
    public enum Left: Equatable {
        case hours(Int)
        case minutes(Int)
    }

    // How much of the Note's life is left, from 1 when it was shared to 0 when it expires.
    public static func fractionLeft(timestamp: Int32, expiration: Int32, now: Int32) -> CGFloat {
        let total = expiration - timestamp
        if total <= 0 {
            return 0.0
        }
        return max(0.0, min(1.0, CGFloat(expiration - now) / CGFloat(total)))
    }

    public static func left(expiration: Int32, now: Int32) -> Left {
        let seconds = max(0, expiration - now)
        if seconds >= 60 * 60 {
            return .hours(Int(ceil(Double(seconds) / 3600.0)))
        }
        return .minutes(max(1, Int(ceil(Double(seconds) / 60.0))))
    }
}

// A published Note is a contacts-only Story whose caption starts with the prefix, so any Telegram client can read it.
public enum TelegramNoteCaption {
    public static let prefix = "📝 Note · "
    public static let maxLength = 80
    public static let period: Int32 = 24 * 60 * 60
    public static let imageSize = CGSize(width: 1080.0, height: 1920.0)

    public static func caption(text: String) -> String {
        return self.prefix + text
    }

    public static func noteText(caption: String) -> String? {
        guard caption.hasPrefix(self.prefix) else {
            return nil
        }
        let text = String(caption.dropFirst(self.prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // Length is counted in UTF-16 units, so an emoji fits only when its whole sequence fits.
    public static func length(_ text: String) -> Int {
        return text.utf16.count
    }

    public static func validated(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || self.length(trimmed) > self.maxLength {
            return nil
        }
        return trimmed
    }
}
