import Foundation

// English source strings for the Notes lang keys. A langpack that defines a key wins.
public enum TelegramNotesStrings {
    private static let english: [String: String] = [
        "NotesTitle": "Notes",
        "NotesAdd": "Add a note",
        "NotesEdit": "Edit note",
        "NotesEmpty": "No notes yet",
        "NotesLoading": "Loading notes...",
        "NotesCompose": "What's on your mind?",
        "NotesShare": "Share",
        "NotesPublishing": "Sharing...",
        "NotesPublishFailed": "Could not share your note. Try again.",
        "NotesAddEmoji": "Add emoji",
        "NotesDuration": "For 24 hours",
        "NotesDelete": "Delete",
        "NotesCancel": "Cancel",
        "NotesNew": "New Note",
        "NotesAudience": "Contacts · 24 hours",
        "NotesYours": "Your note",
        "NotesUnavailable": "Your account can't post right now. You may have reached your limit or need Telegram Premium."
    ]

    public static func string(_ key: String) -> String {
        let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if localized != key {
            return localized
        }
        return self.english[key] ?? key
    }
}
