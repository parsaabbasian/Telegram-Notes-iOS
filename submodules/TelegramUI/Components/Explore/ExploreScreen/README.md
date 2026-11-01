# Explore: conversations from public posts

Explore uses public broadcast-channel posts. Your Channels and Discover retain their existing data sources; cards display the real channel, publication date, excerpt, and media. Cards have stable full-width positions when pagination appends results.

## Viewer

- Natural-aspect media with a separate caption and horizontal Post / Discuss / Send / Moment actions.
- Discuss is shown only for a message with a linked comments peer. It opens Telegram's existing reply-thread flow, including its loading/error handling.
- Send opens Telegram's share picker. Nothing is sent without selecting a destination and confirming.
- Moment exports the message link and adds the current playback time as `t` in seconds.
- Select text in a text post to use Quote to chat. The selected passage is shared with its exported source link.
- Expand / Context switches between media-focused and contextual layouts. Play, sound, and progress remain available.
- Protected messages/channels cannot be shared or quoted. Album forwarding is omitted until complete message groups can be resolved reliably.
- If link export fails, the picker offers the source message instead of an unattributed quote or fabricated link.

Recommendations use caption-word overlap and channel diversity among loaded posts. They are not visual understanding or a trained personalized recommendation service. Reactions are still available through the source post; Explore does not invent engagement counts or implement a separate reaction system.

## Verification

Foundation ranking checks: compile `Sources/ExploreSimilarity.swift` with `Tests/main.swift` or run the Bazel `ExploreSimilarityTests` target. Build the full app using the repository's Make.py instructions.

Simulator checks: open a text post, select a passage and cancel Quote to chat; open video, expand/collapse context, expand a long caption, pause/unmute, open/cancel Moment; open a genuine discussion and return. Verify protected posts have no sharing actions. Check pagination, light/dark appearance, Persian text, landscape and larger text. Record transitions and inspect timestamped frames according to AGENTS.md before claiming visual verification.
