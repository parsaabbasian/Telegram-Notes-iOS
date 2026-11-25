# Telegram Memories (concept prototype)

Each day, Telegram looks back through your private chats for photos and videos you shared on this date in
earlier years. If it finds some, a card appears above the chat list: "3 years ago today · You and Mia · 4 photos".
Tap it to see them full screen, then send them back to Mia with one tap.

## Why it suits Telegram

- **Only Telegram can do it.** Your chats live in the cloud for years, on every device. Messengers that keep
  history on the phone, or delete it, have nothing to look back on.
- **It starts conversations.** Streaks push people to send something every day. A memory gives them a warm
  reason to write to someone they have not talked to in a while.
- **It works today.** The search uses Telegram's existing global message search, which already filters by
  media type and date range. No server change is needed.

## How it works

| Part | What it does | Where |
| --- | --- | --- |
| Finding memories | Searches private chats for photos and videos from today's date in each of the last 10 years, one year at a time. Groups them by person and year, and ranks the day with the most photos first. | `TelegramMemoriesStore.refresh()` |
| Dates | Uses whole local calendar days, so daylight-saving days are 23 or 25 hours long. 29 February shows on 28 February in other years. | `TelegramMemoryModel.swift` |
| The card | Sits in the chat list's header panels, where Telegram shows birthday reminders. The × hides memories for today. | `TelegramMemoryPanelComponent` |
| The viewer | Opens by zooming from the card's photo and plays each photo for 5 seconds, like a Story. Tap to move through the photos, hold to pause and swipe down to close. | `TelegramMemoryViewerController` |
| Send back | Sends the photos to the person as an album, captioned "📸 3 years ago today". It reuses the original media, so nothing is uploaded again. | `TelegramMemoriesStore.send(_:completion:)` |
| Hiding | The menu offers "Don't Show Memories with Mia" and "Hide for Today". Both are remembered on the device. | `hideMemories(with:)`, `hideForToday()` |

## Privacy

- Only private chats with people are searched. Saved Messages, groups, channels and bots are left out, and
  secret chats are never on the server to begin with.
- The search runs from the device, and nothing new is stored on Telegram's servers.
- There are no notifications. A memory waits quietly in the chat list.
- Anyone can be left out for good with "Don't Show Memories with…".

## Demo mode

While `TelegramNotesStore.isDemoMode` is on, Memories shows two sample memories with the fictional contacts
from Notes: a Rome trip with Mia 3 years ago and a concert with Leo 1 year ago. Their pictures are drawn in
code (`TelegramMemoryDemo.swift`), and Send only confirms on the device. Hidden memories come back at the next
launch, like the sample Notes.

With demo mode off, Memories searches the real account and Send posts real messages.

## Not done yet

- A switch in Settings to turn Memories off completely.
- Videos show their first frame and do not play.
- Friendship anniversaries ("3 years since your first message") would fit the same card.

## Tests

```sh
./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramUI/Components/TelegramMemories:TelegramMemoryModelTests
```

These cover the date windows, leap days, daylight saving and ranking. On Xcode 27.2, run the built test binary
directly, as described in the Notes README.

## Files

| File | Purpose |
| --- | --- |
| `TelegramMemoryModel.swift` | Dates and ranking, with no UI |
| `TelegramMemories.swift` | The store: search, grouping, hiding and sending |
| `TelegramMemoryPanelComponent.swift` | The card above the chat list |
| `TelegramMemoryViewerController.swift` | The full-screen viewer |
| `TelegramMemoryImageView.swift` | Shows a chat photo, a video frame or a demo picture |
| `TelegramMemoryDemo.swift` | The sample memories and their drawn pictures |
| `TelegramMemoriesStrings.swift` | English strings |
