# Telegram Notes (concept prototype)

Short updates of up to 80 characters that appear as bubbles above the chat list. This is a design
concept, not a Telegram feature. It runs entirely on the device: nothing is uploaded and nobody else
sees a Note.

## What makes it Telegram, not Instagram

| Feature | What it does | Where |
| --- | --- | --- |
| Self-destruct timer | Choose 1 hour, 8 hours, 24 hours or 3 days. A ring around the avatar counts down, in place of a Story ring. | Composer chip, `updateNoteTimer` in the row |
| Spoiler Notes | The text sits under Telegram's own spoiler dust until tapped. | `InvisibleInkDustNode` in the bubble and the card |
| Poll Notes | A two-option question answered in one tap, with live results. | `TelegramNotePoll`, `PollRowView` |
| Folder audience | Share with Contacts, Close Friends or one of your chat folders. | `audienceOptions()` |
| Note card | Tap a friend's Note for the full text, time left, Telegram reactions and a reply box. | `TelegramNoteCardController` |
| Landing animation | The Note flies out of the sheet and lands on your avatar with a bounce, a ripple and sparkles. | `flyNoteToAvatar`, `playNoteLanding` |

## Demo mode

`TelegramNotesStore.isDemoMode` is `true`. While it is on:

- Notes stay in memory on the device and disappear when the app restarts.
- The sample Notes restart their timers each time the app launches, and they expire like real ones.
- Mia, Leo, Sara and Noah are fictional sample contacts with emoji avatars.
- The Explore tab, the Stories rings, the Archived Chats row and the Settings badge are hidden.
- Spoilers, polls, timers, folders, reactions and replies work only on this device. A reply is
  confirmed and goes no further.

With `isDemoMode` set to `false`, Share posts a real contacts-only Story, which needs an account that
is allowed to post Stories. The features above are hidden in that mode, because Telegram's servers have
no way to carry them yet. Real Notes would need server support.

## Build and run

You need a Mac with Xcode, your own `api_id` and `api_hash` from
[my.telegram.org](https://my.telegram.org), and a configuration file based on
`build-system/template_minimal_development_configuration.json`. Keep that file outside the repo.

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath="$HOME/telegram-configuration/configuration.json" \
  --xcodeManagedCodesigning --buildNumber=1 --configuration=debug_sim_arm64
```

The first build compiles everything and can take over an hour. Simulator builds need no provisioning
profile. To install the result:

```sh
unzip -q -o bazel-bin/Telegram/Telegram.ipa -d /tmp/telegram-app
xcrun simctl install booted /tmp/telegram-app/Payload/Telegram.app
xcrun simctl launch booted <your bundle id>
```

Log in, then pull down twice on the chat list to open the Notes row.

`versions.json` pins the Xcode version; `--overrideXcodeVersion` allows a newer one. After an Xcode
update, Bazel can keep looking for the old version. To clear that, run `bazel shutdown`, delete
`MODULE.bazel.lock` from the Bazel output base, and delete the `*system_sdk*` and `*xcode_configure*`
folders under its `external` directory. The next build recompiles everything.

## Tests

```sh
./build-input/bazel-9.2.0-darwin-arm64 test //submodules/TelegramUI/Components/TelegramNotes:TelegramNoteModelTests
```

These cover captions, the 80-character limit, poll results, timers and option validation.

On Xcode 27.2 that command builds the tests but cannot start them (`Library not loaded: libXCTestSwiftSupport.dylib`).
Run the built test binary directly instead:

```sh
D=$(xcode-select -p)/Platforms/MacOSX.platform/Developer
DYLD_LIBRARY_PATH=$D/usr/lib DYLD_FRAMEWORK_PATH=$D/Library/Frameworks \
  bazel-bin/submodules/TelegramUI/Components/TelegramNotes/TelegramNoteModelTests.xctest/Contents/MacOS/TelegramNoteModelTests
```

## Files

| File | Purpose |
| --- | --- |
| `TelegramNoteModel.swift` | Notes data with no UI: polls, options, timers, captions |
| `TelegramNotes.swift` | The store: loading, publishing, sample contacts, reactions, votes |
| `TelegramNoteComposerController.swift` | The sheet for writing a Note, and the flight animation |
| `TelegramNoteCardController.swift` | The card for a friend's Note |
| `TelegramNoteHostWindow.swift` | The separate window these sheets need to receive touches |
| `TelegramNoteRenderer.swift` | The Story image used outside demo mode |
| `StoryPeerListItemComponent.swift` (Stories) | Bubbles, countdown ring, landing animation in the row |
