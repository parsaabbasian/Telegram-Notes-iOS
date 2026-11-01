import Foundation

// English source strings for the Explore lang keys. A langpack that defines a key wins.
enum ExploreStrings {
    private static let english: [String: String] = [
        "ExploreTitle": "Explore",
        "ExploreTabChannels": "Your Channels",
        "ExploreTabDiscover": "Discover",
        "ExploreEmptyChannelsTitle": "Your Channels",
        "ExploreEmptyChannels": "Posts from channels you join will appear here.",
        "ExploreEmptyDiscoverTitle": "Suggested Channels",
        "ExploreEmptyDiscover": "No recommended posts yet. Try refreshing.",
        "ExploreOpenDiscover": "Discover Channels",
        "ExploreRefresh": "Refresh",
        "ExplorePhoto": "Photo",
        "ExploreVideo": "Video",
        "ExploreText": "Text post",
        "ExploreOpenChannel": "Open in channel",
        "ExploreShare": "Send",
        "ExploreDiscuss": "Discuss",
        "ExploreMoment": "Moment",
        "ExploreExpandMedia": "Expand",
        "ExploreShowContext": "Context",
        "ExploreQuote": "Quote to chat",
        "ExploreReadDiscuss": "Read & join the discussion  ›",
        "ExploreOpenConversation": "Open · Bring this to a chat  ›",
        "ExplorePostAction": "Post",
        "ExploreSound": "Sound",
        "ExplorePlay": "Play",
        "ExplorePause": "Pause",
        "ExploreCaptionMore": "More",
        "ExploreCaptionLess": "Less",
        "ExploreExpandCaption": "Show full caption",
        "ExploreCollapseCaption": "Collapse caption",
        "ExplorePreviousPost": "Previous post",
        "ExploreNextPost": "Next post",
        "ExploreMute": "Mute",
        "ExploreUnmute": "Unmute",
        "ExploreViews": "views",
        "ExploreAlbumItems": "items",
        "ExploreFeedTitle": "Explore feed",
        "ExploreClose": "Close"
    ]

    static func string(_ key: String) -> String {
        let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if localized != key {
            return localized
        }
        return self.english[key] ?? key
    }
}
