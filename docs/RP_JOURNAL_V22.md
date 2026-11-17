# RP Core v22 — Journal Memory

## What changed

- Character identity still comes from the existing card; current RP state and lorebook still come from the v21 runtime.
- A character's memory now has three separate storage layers:
  1. `rp_journal_queue`: actual saved user/character turns awaiting consolidation, atomically written with `penpal_chat_messages`;
  2. `rp_journal_entries`: first-person diaries tied to a character and originating conversation, with date/time;
  3. `rp_continuity`: a compact, editable, always-injected view of self, confirmed user facts, relationship, unfinished threads and topics to avoid repeating.
- The journal writer uses the already-configured OpenAI-compatible Chat Completions API. It does not create a separate API key, import chat history from elsewhere, run background timers, or upload audio files.
- Normal chat saves the raw turn first and never fails because journal compilation fails. Consolidation is attempted after 6+ saved turns, a cross-conversation transition, a date boundary, or by explicit user action. It processes up to 8 turns from one source conversation at a time and keeps a bounded bridge of pending evidence until successful.
- Continuous memory and the latest 3 diary entries are included on each new conversation, without relying on keywords. A few most recent pending turns bridge the gap before consolidation. Keyword-matched `episode` recall in the v21 runtime is retired; manually pinned notes still work.
- A successful LLM-authored daily music letter may be registered as diary source evidence. Failed/local fallback letters do not pretend to be character memories.

## SQLite v21 -> v22

Additive tables and indexes only. `onUpgrade` creates three new tables and `onCreate` creates them for new databases. Existing character cards, conversations, v21 memories, letters, music sources, playlists and listening history are preserved.

`rp_journal_queue` includes original saved turn excerpts (max 1,200 characters each), source conversation, timestamp and digestion marker. Processed excerpts are retained for 180 days to help remove derived memories when deleting chat sources; older processed excerpts can be removed. Unprocessed excerpts are not discarded by retention.

`rp_journal_entries` contains the short diary text, source conversation and local day. `rp_continuity` is keyed by immutable character card ID and uses a revision counter to prevent overwriting an updated user edit during consolidation.

## Source deletion and privacy

- Deleting a chat thread deletes journal queue rows and diary entries of that thread and invalidates its character's continuity. This is deliberately conservative: it prevents retained summary content from preserving material whose evidence was deleted.
- Deleting a diary entry also invalidates continuity. The remaining diaries can be used for a fresh compilation. Until then the stale continuity is NOT supplied to LLM.
- `RpRepository.clearMemories()` now clears journals and continuity as well as v21 memories. Deleting a character card clears all RP tables for that card. The old memory-clear actions that delete chats clear the associated journal data too. Clearing only archived letters now keeps the independent `rp:general` RP chat and its diary; only letter-linked RP derivatives are withdrawn, and the shared continuity is invalidated for reconstruction.
- No journal text, album names, user utterances, API credentials or private addresses are written to diagnostics. Journal source text is sent to the model provider only if the user has enabled their own LLM API and memory setting.
- Fictional character events are narrative context, not evidence of an actual shared experience. The journal prompt explicitly distinguishes character self-reflection and verified user facts.

## UI

`RP 角色状态与世界书` -> `角色日记与连续记忆`:

- See pending turns, manually request journal consolidation, browse diary entries.
- View/edit five continuous-memory sections; edit is saved immediately and increments revision.
- Delete individual diary entries. Derived continuity is invalidated immediately rather than silently keeping withdrawn facts.

## Runtime details

Consolidation is forward-only and explicitly foreground-driven. No interval timer or automatic catch-up when the app is closed. Failed LLM response/JSON parsing leaves pending evidence untouched for retry. A model that is disabled does not block chat; new conversations still receive the most recent undigested turns.

There are cost and latency implications. A cross-thread transition can trigger one extra LLM request to compact a previous conversation; an ordinary chat does not call the extra model every turn.

## Verification still required on target workstation

Run `python apply_to_repo.py /path/to/SylphyMusic --check`, then install and run `dart format` on modified files followed by the ordinary Android/Windows compile per repo instructions. This delivery environment does not include Flutter/Dart and does not claim the application compiled.

Key acceptance scenarios: same-card conversation A -> B recalls authentic facts after one turn; disabled memory sends no journal; malformed model JSON preserves queue; deletion of conversation removes derived data; role switch does not mix memories; migration from v21 does not erase music or earlier chat data; LLM-generated letters are diarized only when authoring succeeded.
