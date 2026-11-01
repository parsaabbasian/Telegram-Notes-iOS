# Explore Together prototype

Together is a local navigation and discovery layer over existing Telegram forum topics. Its account-scoped registry stores group/topic IDs, display titles and an optional purpose-message ID. Shared content remains ordinary Telegram messages; other clients do not need to understand a custom payload.

## Implemented flows

- Together tab: add an existing group topic, or explicitly confirm creation where the account has permission. Topic cards show group avatars and a recent contribution.
- Explore with… on public posts and videos; selected passages also offer Explore this quote with… . Video sharing preserves the current timestamp.
- Confirmation displays the group, topic, source, timestamp and optional comment. Source content is reloaded before preparing a contribution, including public-channel, spoiler, protection and edited-quote checks.
- A contribution opens as a draft in the native topic composer. Existing rich-text drafts are preserved by structural append. Reopening an identical pending contribution does not append it again. Review in topic never sends. The native composer owns Send, payment consent, offline queuing and retry.
- Contributions and Decisions & pins use thread-scoped reads with pagination. Postbox subscriptions update cached edits; deletion events remove deleted messages. Visible contexts refresh every 30 seconds for remote pin/access changes and stop on disappearance.
- Discover uses the explicit topic title and public source posts represented by forwards or canonical links in that topic. Private comments are not recommendation text. Results show matching words and suppress unrelated candidates; the initial candidate pool is public posts already loaded in Explore.
- Polls, outcome messages and pinning use the native topic chat. Removing a Together shortcut does not delete or leave the topic.
- Ambiguous creation errors route users to check existing topics before another creation attempt, avoiding blind duplicate creation.

## Verification

Host tests in Tests/main.swift cover Persian/English relevance, exclusion of unrelated results, channel diversity, source-link identity and host boundaries, account-scoped keys, reference deduplication, serialization and attributed quote/timestamp formatting. Build the full iOS target using CLAUDE.md.

Manual acceptance remains pending: use two accounts, including one official client. Select a writable topic, prepare/cancel a contribution, preserve an existing formatted draft, and explicitly send from the native composer only when the tester intends to. Confirm the second account sees attribution and can reply, create a poll, and pin an outcome with the correct permissions. Test closed/deleted topics, membership removal, protected/edited/deleted sources, offline retry and account switching. Check RTL, larger text and both themes using recordings per AGENTS.md.

The five-group pilot has not been conducted. Recruit consenting groups, compare a planning task with ordinary forwarding, and record retrieval of contributions/decisions, repeat use and feedback. No user messages or group mutations should be sent by an agent merely to perform this pilot.

## Limits

The shortcut registry does not sync between devices; users explicitly add the same topic elsewhere. Discovery is text-based and limited to loaded public content. There is no visual model, private-chat profiling, new backend, or automatic publishing. Native Telegram is the final authority on write restrictions. The prototype does not infer that a pinned message is an agreed decision.

## Current verification result

The full simulator app build passed (`/private/tmp/telegram-together-ready.log`, 23 actions). The Foundation runner passed both existing Explore similarity checks and the Together model/attribution/ranking checks (`/private/tmp/explore-together-tests`). The build was installed on the existing logged-in simulator by replacing the app bundle only. Interactive, cross-account, accessibility and pilot acceptance remain pending until their actual results are recorded; successful compilation is not evidence of those behaviors.

## Retrieval and decision drafting

Exploration details now include local search across loaded contribution text and author names, pinned messages, and public discovery results. All query words must match; case, accents and common Persian/Arabic letter variants are normalized. Search does not fetch all history or feed private content into recommendations. Load earlier messages to widen the searchable history.

Decisions & pins offers Draft a decision for available, open topics. The user enters a proposal and optional next step, sees the destination, and opens a clearly labelled proposal in the native composer. Sending and pinning remain explicit native actions. No draft is presented as a group-approved outcome.

Visual acceptance for these additions: search should sit below the three tabs without overlapping the first card; typing should preserve keyboard focus while filtering; clearing should restore results; empty results should retain pagination. Switching tabs should preserve the query. The decision dialog should identify the group/topic, cancellation should leave the topic unchanged, and Review should preserve existing composer content. Verify these in both themes, RTL and larger text with recorded frames before claiming visual acceptance.

The retrieval/decision update passed all 21 Foundation preconditions and the full simulator build, including a final unchanged-source verification (`/private/tmp/telegram-together-search-final.log`). Visual interaction checks remain pending; XcodeBuildMCP interaction tools were unavailable in this session. Existing whitespace warnings in unrelated ChatListUI/Stories edits were left untouched.

## Viewer refinement and user acceptance

The viewer now gives media the full safe width while retaining text margins, reduces excess space in the context panel, uses horizontal action labels when three or fewer actions fit, and groups icon-only playback controls with 44-point targets. The Together entry has a group icon and capsule treatment. Playback state changes must retain icon-only styling and correct VoiceOver labels.

Before visual acceptance, record: open a photo/video, pause/play, mute/unmute, expand/collapse, expand caption, open/cancel Send and Moment, open source and return, and open/cancel Together. Check media remains uncropped, source attribution stays legible, controls do not overlap the context panel, and transitions have no flashes/clipping. Also exercise text selection, Together tab, local search/clear/no-match/load-earlier, and decision draft/cancel/native composer. Sending, joining, creating topics and pinning require deliberate tester action. Light/dark, RTL, larger text and official-client compatibility remain separate checks; no passing claim is implied by compilation.

Next-feature candidates (not implemented): a native channel preview with explicit Join; a saved-exploration resume shortcut; clearer discussion availability; and a visible explanation of which public source words produced each recommendation. Prioritize these after the current flows pass recorded user testing. Avoid synthetic activity counts, automatic joining or a parallel social graph.

2026-10-31 review: Terra (high) implemented the viewer and Notes layout refinements; Astra reviewed source/supplied screenshots. Additional fixes include RTL control/source ordering, source-header spacing at larger text sizes, caption-toggle width, right-safe-inset transport geometry, and Notes header/placeholder constraints. Notes now uses a keyboard-aware scroll container. No publishing behavior was changed.

Source-review follow-ups, not runtime-confirmed: test large accessibility text in landscape; newer Together strings remain English-only; Discover search filters its first 40 ranked results; Notes audience is not described in the composer; Notes cancel does not restore unsent edits; Escape dismissal during publication needs a separate behavior review. Proposed next features: save attributed sources/moments to Saved Messages, show Notes audience explicitly, and resume recent explorations. These are proposals, not implemented features.
