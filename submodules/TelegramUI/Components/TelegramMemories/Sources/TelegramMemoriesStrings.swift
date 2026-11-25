import Foundation

// English source strings for the Memories lang keys. A langpack that defines a key wins.
public enum TelegramMemoriesStrings {
    private static let english: [String: String] = [
        "MemoriesYearAgo": "1 year ago today",
        "MemoriesYearsAgo": "%d years ago today",
        "MemoriesYearAgoShort": "1 year ago",
        "MemoriesYearsAgoShort": "%d years ago",
        "MemoriesWith": "You and %@",
        "MemoriesPhoto": "1 photo",
        "MemoriesPhotos": "%d photos",
        "MemoriesVideo": "1 video",
        "MemoriesVideos": "%d videos",
        "MemoriesMoments": "%d photos and videos",
        "MemoriesSendTo": "Send to %@",
        "MemoriesSent": "Sent",
        "MemoriesSendFailed": "Couldn't send. Try again.",
        "MemoriesHidePerson": "Don't Show Memories with %@",
        "MemoriesHideToday": "Hide for Today",
        "MemoriesClose": "Close",
        "MemoriesMore": "More",
        "MemoriesOpen": "Open memory"
    ]

    public static func string(_ key: String) -> String {
        let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if localized != key {
            return localized
        }
        return self.english[key] ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        return String(format: self.string(key), arguments: arguments)
    }
}
